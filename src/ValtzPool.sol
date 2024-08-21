// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import "./Constants.sol";
import "./IRoleAuthority.sol";
import "./lib/Interval.sol";
import "./Error.sol";

interface IValtzPool {
    /* /////////////////////////////////////////////////////////////////////////
                                    EVENTS
    ///////////////////////////////////////////////////////////////////////// */

    event Start(uint40 startTime);
    event ValtzDeposit(address indexed depositor, uint256 amount);
    event ValtzRedeem(address indexed redeemer, uint256 amount);

    /* /////////////////////////////////////////////////////////////////////////
                                    STRUCTS
    ///////////////////////////////////////////////////////////////////////// */

    struct ValidationData {
        bytes32 validatorID;
        LibInterval.Interval interval;
    }

    struct ValidationAttestation {
        ValidationData validation;
        bytes signature;
        address signer;
    }

    struct RedemptionAuthorizationData {
        bytes32 subnetID;
        bytes32 validatorID;
        // TODO - what does a p-chain address provide in order to prove validator control/ownership? or can the validator actually perform signatures?
        bytes nodeOwnershipProof;
        address authorizedRedeemer;
        uint40 timestamp;
    }

    struct RedemptionAuthorization {
        RedemptionAuthorizationData data;
        bytes signature;
        address pChainSigner;
    }

    struct PoolConfig {
        address owner;
        string name;
        string symbol;
        bytes32 subnetID;
        IERC20 token;
        uint40 term;
        uint256 tokenDepositsMax;
        uint24 boostRate;
        uint256 maxRedeemablePerValidationAttestation;
    }

    function initialize(PoolConfig memory config) external;
}

contract ValtzPool is IValtzPool, Initializable, ERC20PermitUpgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /* /////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    ///////////////////////////////////////////////////////////////////////// */

    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    uint24 public constant BOOST_RATE_PRECISION = 1e6;

    IRoleAuthority public immutable roleAuthority;

    /* /////////////////////////////////////////////////////////////////////////
                                     STORAGE
    ///////////////////////////////////////////////////////////////////////// */

    bytes32 public subnetID;
    IERC20 public token;
    uint40 public term;
    uint256 public tokenDepositsMax;
    uint24 public boostRate;
    uint256 public maxRedeemablePerValidationAttestation;
    uint40 public startTime;
    uint256 public tokenDepositsTotal;
    mapping(bytes32 => LibInterval.Interval[]) public validationIntervals;

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
        term = config.term;
        tokenDepositsMax = config.tokenDepositsMax;
        boostRate = config.boostRate;
        maxRedeemablePerValidationAttestation = config.maxRedeemablePerValidationAttestation;
    }

    // function supportsInterface(bytes4 interfaceId)
    //     public
    //     view
    //     virtual
    //     override(AccessControlUpgradeable)
    //     returns (bool)
    // {
    //     return AccessControlUpgradeable.supportsInterface(interfaceId);
    // }

    function _calculateBoostedAmount(uint256 amount) internal view returns (uint256) {
        return amount + (amount * boostRate) / BOOST_RATE_PRECISION;
    }

    function deposit(uint256 tokens, address receiver) public onlyActive returns (uint256) {
        require(tokens <= maxDeposit(), "Deposit exceeds max limit");
        tokenDepositsTotal += tokens;
        token.safeTransferFrom(msg.sender, address(this), tokens);
        _mint(receiver, tokens);
        return tokens;
    }

    function redeem(uint256 amount, address receiver, ValidationAttestation memory attestation)
        public
        onlyActive
        returns (uint256 tokens)
    {
        _checkAttestation(attestation);
        _consumeInterval(attestation.validation.validatorID, attestation.validation.interval);

        tokens = _calculateBoostedAmount(amount);
        _burn(msg.sender, amount);
        token.safeTransfer(receiver, tokens);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    OWNER
    ///////////////////////////////////////////////////////////////////////// */

    function start() public onlyOwner onlyBeforeActive {
        startAt(uint40(block.timestamp));
    }

    function startAt(uint40 _startTime) public onlyOwner onlyBeforeActive {
        require(startTime == 0, "Already active");
        require(_startTime >= block.timestamp, "Must either cancel or set to start in future block");
        startTime = _startTime;
        token.safeTransferFrom(msg.sender, address(this), rewardsAmount());
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    VIEW
    ///////////////////////////////////////////////////////////////////////// */

    function rewardsAmount() public view returns (uint256) {
        return _calculateBoostedAmount(tokenDepositsMax) - tokenDepositsMax;
    }

    function attestationsNeededToRedeem(uint256 amount) public view returns (uint256) {
        return Math.ceilDiv(amount, maxRedeemablePerValidationAttestation);
    }

    function maxDeposit() public view returns (uint256) {
        return tokenDepositsMax > tokenDepositsTotal ? tokenDepositsMax - tokenDepositsTotal : 0;
    }

    /* /////////////////////////////////////////////////////////////////////////
                                VALIDATION ATTESTATION
    ///////////////////////////////////////////////////////////////////////// */

    function _consumeInterval(bytes32 validatorID, LibInterval.Interval memory interval) internal {
        LibInterval.Interval[] storage intervals = validationIntervals[validatorID];
        for (uint256 i = 0; i < intervals.length; i++) {
            if (LibInterval.overlap(intervals[i], interval)) {
                revert("ValidationAttestation: overlapping interval");
            }
        }
        intervals.push(interval);
    }

    function _checkAttestation(ValidationAttestation memory attestation) internal view {
        if (!roleAuthority.hasRole(VALTZ_SIGNER_ROLE, attestation.signer)) {
            revert InvalidAttestationSigner();
        }

        bytes32 messageHash = keccak256(abi.encode(attestation.validation));
        if (
            !SignatureChecker.isValidSignatureNow(
                attestation.signer, messageHash, attestation.signature
            )
        ) {
            revert InvalidAttestationSignature();
        }
    }

    function _checkAuthorization(RedemptionAuthorization memory authorization) internal view {
        // TODO!
        // - recover the signer from the signature
        // - check that msg.sender is the authorizedRedeemer
        // - check that the timestamp is within the last X minutes
        // - validate nodeOwnershipProof
        // - check that the signer is the validator's owner (or is the validator?)

        (address recovered, ECDSA.RecoverError err,) =
            ECDSA.tryRecover(keccak256(abi.encode(authorization.data)), authorization.signature);
        if (err != ECDSA.RecoverError.NoError) {
            revert InvalidAuthorizationSignature();
        }
        if (recovered != authorization.pChainSigner) {
            revert InvalidAuthorizationSigner();
        }

        /// TODO - validate authorization.data.nodeOwnershipProof to ensure node owner is the pChain address

        if (authorization.data.authorizedRedeemer != msg.sender) {
            revert UnauthorizedRedeemer();
        }

        if (authorization.data.timestamp + 5 minutes < block.timestamp) {
            revert ExpiredAuthorization();
        }
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    ///////////////////////////////////////////////////////////////////////// */

    modifier onlyBeforeActive() {
        require(startTime == 0, "Already activated");
        _;
    }

    modifier onlyActive() {
        require(startTime > 0, "Not activated");
        require(block.timestamp < startTime + term, "No longer active");
        _;
    }

    modifier onlyAfterActive() {
        require(block.timestamp < startTime + term, "No longer active");
        _;
    }
}
