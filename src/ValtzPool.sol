// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import "./lib/DelegatedAuth.sol";
import "./lib/Interval.sol";
import "./lib/AttestedValidation.sol";
import "./ValtzConstants.sol";
import "./interfaces/IRoleAuthority.sol";
import "./ValtzEvents.sol";

error UnauthorizedRedeemer();
error InvalidAuthScope();
error ExpiredAuthorization();
error InvalidAttestationSigner();
error RedemptionAmountExceeds();
error WithdrawDisabled();
error InvalidValidationAttestation();

interface IValtzPool {
    struct PoolConfig {
        address owner;
        string name;
        string symbol;
        bytes32 subnetID;
        uint40 poolTerm;
        IERC20 token;
        uint40 validatorTerm;
        uint256 validatorRedeemable;
        uint256 max;
        uint24 boostRate;
    }

    function initialize(PoolConfig memory config) external;
}

contract ValtzPool is IValtzPool, Initializable, ERC20PermitUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using LibInterval for LibInterval.Interval;

    /* /////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    ///////////////////////////////////////////////////////////////////////// */

    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    uint24 public constant BOOST_RATE_PRECISION = 1e6;

    IRoleAuthority public immutable roleAuthority;

    /* /////////////////////////////////////////////////////////////////////////
                                     STORAGE
    ///////////////////////////////////////////////////////////////////////// */

    /// @notice The subnet ID that the pool is associated with
    bytes32 public subnetID;

    /// @notice How long the pool is active, after which unclaimed deposits and rewards are forfeited
    uint40 public poolTerm;

    /// @notice The token that is being staked in the pool
    IERC20 public token;

    /// @notice The required amount of time a validator must be attested to in order to redeem
    uint40 public validatorTerm;

    /// @notice The maximum amount of tokens that can be deposited into the pool
    uint256 public max;

    /// @notice The rate at which rewards are boosted
    uint24 public boostRate;

    /// @notice The max amount of tokens redeemable for an attested validator interval of `validatorTerm` duration.
    uint256 public validatorRedeemable;

    /// @notice Whether the pool has been started
    bool public started;

    /// @notice The time at which the pool starts accepting deposits
    uint40 public startTime;

    /// @notice The total amount staked
    uint256 public totalDeposited;

    /// @notice The total amount staked
    uint256 public availableRewards;

    mapping(bytes32 => LibInterval.Interval[]) public _validatorIntervals;

    constructor(IRoleAuthority _roleAuthority) {
        roleAuthority = _roleAuthority;
        _disableInitializers();
    }

    function initialize(PoolConfig memory config) external override initializer {
        __ERC20_init(config.name, config.symbol);
        __ERC20Permit_init(config.name);
        __Ownable_init(config.owner);

        subnetID = config.subnetID;
        token = config.token;
        poolTerm = config.poolTerm;
        validatorTerm = config.validatorTerm;
        max = config.max;
        boostRate = config.boostRate;
        validatorRedeemable = config.validatorRedeemable;
    }

    function deposit(uint256 tokens, address receiver) public onlyActive returns (uint256) {
        require(tokens <= maxDeposit(), "Deposit would exceed pool max");
        totalDeposited += tokens;
        token.safeTransferFrom(msg.sender, address(this), tokens);
        _mint(receiver, tokens);
        return tokens;
    }

    function redeem(
        uint256 amount,
        address receiver,
        AttestedValidation.Validation memory attestedValidation,
        DelegatedAuth.SignedAuth memory signedAuth
    ) public onlyActive returns (uint256 withdrawAmount) {
        // TODO - ensure the subnet ID matches the pool's subnet ID
        require(amount <= validatorRedeemable, "Redeem amount exceeds validator stake");

        AttestedValidation._assertValidAttestation(attestedValidation, _domainSeparatorV4());
        if (!roleAuthority.hasRole(VALTZ_SIGNER_ROLE, attestedValidation.signer)) {
            revert InvalidAttestationSigner();
        }

        DelegatedAuth._assertAuth(
            signedAuth,
            attestedValidation.data.nodeRewardOwner,
            msg.sender,
            address(this),
            _domainSeparatorV4()
        );
        _consumeInterval(attestedValidation.data.nodeID, attestedValidation.data.interval);

        totalDeposited -= amount;
        _burn(msg.sender, amount);
        uint256 rewardAmount = calculateReward(amount);
        availableRewards -= rewardAmount;
        withdrawAmount = amount + rewardAmount;
        token.safeTransfer(receiver, withdrawAmount);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    OWNER
    ///////////////////////////////////////////////////////////////////////// */

    function start() public onlyOwner onlyBeforeActive {
        startAt(uint40(block.timestamp));
    }

    function startAt(uint40 _startTime) public onlyOwner onlyBeforeActive {
        require(!started, "Already active");
        started = true;
        require(_startTime >= block.timestamp, "Must start in current or future block");
        startTime = _startTime;
        availableRewards = calculateReward(max);
        token.safeTransferFrom(msg.sender, address(this), availableRewards);
    }

    function rescueERC20(IERC20 _token, address to, uint256 amount) public onlyOwner {
        if (!isClosed()) {
            require(_token != token, "Cannot rescue primary token unless pool is closed");
        }
        _token.safeTransfer(to, amount);
    }

    function rescueNative(address payable to, uint256 amount) public onlyOwner {
        to.sendValue(amount);
    }

    function rescueERC1155(IERC1155 _token, uint256 tokenId, address to, uint256 amount)
        public
        onlyOwner
    {
        _token.safeTransferFrom(address(this), to, tokenId, amount, "");
    }

    function rescueERC721(IERC721 _token, uint256 tokenId, address to) public onlyOwner {
        _token.safeTransferFrom(address(this), to, tokenId);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    VIEW
    ///////////////////////////////////////////////////////////////////////// */

    function calculateReward(uint256 amount) public view returns (uint256) {
        return (amount * boostRate) / BOOST_RATE_PRECISION;
    }

    function rewardPool() public view returns (uint256) {
        return calculateReward(max);
    }

    function attestationsNeededToRedeem(uint256 amount) public view returns (uint256) {
        return Math.ceilDiv(amount, validatorRedeemable);
    }

    function maxDeposit() public view returns (uint256) {
        return max > totalDeposited ? max - totalDeposited : 0;
    }

    function endTime() public view returns (uint40) {
        return startTime + poolTerm;
    }

    function isOpen() public view returns (bool) {
        return started && (block.timestamp < endTime());
    }

    function isClosed() public view returns (bool) {
        return started && (block.timestamp >= endTime());
    }

    function validatorIntervals(bytes32 nodeID)
        public
        view
        returns (LibInterval.Interval[] memory)
    {
        return _validatorIntervals[nodeID];
    }

    /* /////////////////////////////////////////////////////////////////////////
                                VALIDATION ATTESTATION
    ///////////////////////////////////////////////////////////////////////// */

    function _consumeInterval(bytes32 nodeID, LibInterval.Interval memory interval) internal {
        if (interval.term != validatorTerm) {
            revert("ValidationAttestation: attested term != required validation term");
        }

        LibInterval.Interval[] storage intervals = _validatorIntervals[nodeID];
        if (interval.overlapsAny(intervals)) {
            revert("ValidationAttestation: interval overlaps with previously recorded validation");
        }
        intervals.push(interval);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    ///////////////////////////////////////////////////////////////////////// */

    modifier onlyBeforeActive() {
        require(!started, "Pool is not active");
        _;
    }

    modifier onlyNotActive() {
        require(!started || isClosed(), "Pool is active");
        _;
    }

    modifier onlyActive() {
        require(started && !isClosed(), "Pool is not active");
        _;
    }

    modifier onlyClosed() {
        require(isClosed(), "Pool is active");
        _;
    }
}
