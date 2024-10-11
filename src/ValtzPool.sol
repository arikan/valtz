// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts-upgradeable/utils/cryptography/MessageHashUtilsUpgradeable.sol";

// import {console2} from "forge-std/console2.sol";

import "./lib/Interval.sol";
import "./lib/Events.sol";
import "./ValtzConstants.sol";
import "./interfaces/IRoleAuthority.sol";

interface IValtzPool {
    struct PoolConfig {
        address owner;
        string name;
        string symbol;
        bytes32 subnetID;
        uint40 poolTerm;
        IERC20 token;
        uint40 validatorDuration;
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
                                    ERRORS
    ///////////////////////////////////////////////////////////////////////// */

    error RedeemAmountTooHigh(uint256);
    error InvalidSignedAt(uint40);
    error NullReceiver();
    error InvalidSigner(address);
    error InvalidChainId(uint256);
    error InvalidTarget(address);
    error InvalidRedemptionStart();
    error ExpiredRedemption();
    error InvalidSubnetID(bytes32);
    error InvalidDuration(uint40);
    error InvalidRedeemer(address);
    error InvalidTokenAmount();
    error DepositExceedsMax();
    error AlreadyActive();
    error MustStartInCurrentOrFutureBlock();
    error PoolNotActive();
    error CannotRescuePrimaryToken();
    error IntervalOverlap();

    /* /////////////////////////////////////////////////////////////////////////
                                    STRUCTS
    ///////////////////////////////////////////////////////////////////////// */

    struct ValidationRedemptionData {
        uint256 chainId;
        address target;
        uint40 signedAt;
        bytes32 nodeID;
        bytes32 subnetID;
        address redeemer;
        uint40 duration;
        uint40 start;
        uint40 end;
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    ///////////////////////////////////////////////////////////////////////// */

    /**
     * @dev The time-to-live (TTL) for a Valtz signature, defined as a constant.
     * This value represents the duration (in minutes) for which a Valtz signature is considered valid.
     * After this period, the signature will expire and no longer be valid.
     */
    uint256 public constant VALTZ_SIGNATURE_TTL = 5 minutes;

    /**
     * @dev The precision used for boost rate calculations.
     * This constant defines the number of decimal places to consider
     * when calculating boost rates, set to 1e6 (1,000,000).
     */
    uint24 public constant BOOST_RATE_PRECISION = 1e6;

    /**
     * @notice The role authority contract that manages roles and permissions.
     * @dev This is an immutable variable, meaning it can only be set once during contract deployment.
     */
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

    /// @notice The required amount of time a validator must have validated in order to redeem
    uint40 public validatorDuration;

    /// @notice The maximum amount of tokens that can be deposited into the pool
    uint256 public max;

    /// @notice The rate at which rewards are boosted
    uint24 public boostRate;

    /// @notice The max amount redeemable for a signed proof of validation of validatorDuration.
    uint256 public validatorRedeemable;

    /// @notice Whether the pool has been started
    bool public started;

    /// @notice The time at which the pool starts accepting deposits
    uint40 public startTime;

    /// @notice The total amount staked
    uint256 public totalDeposited;

    /// @notice The total amount staked
    uint256 public availableRewards;

    mapping(bytes32 => LibInterval.Interval[]) private _validatorIntervals;

    constructor(IRoleAuthority _roleAuthority) {
        roleAuthority = _roleAuthority;
        _disableInitializers();
    }

    /**
     * @notice Initializes the ValtzPool contract with the given configuration.
     * @dev This function can only be called once due to the `initializer` modifier.
     * @param config The configuration parameters for the pool.
     */
    function initialize(PoolConfig memory config) external override initializer {
        __ERC20_init(config.name, config.symbol);
        __ERC20Permit_init(config.name);
        _transferOwnership(config.owner);

        subnetID = config.subnetID;
        token = config.token;
        poolTerm = config.poolTerm;
        validatorDuration = config.validatorDuration;
        max = config.max;
        boostRate = config.boostRate;
        validatorRedeemable = config.validatorRedeemable;
    }

    /**
     * @notice Deposits a specified amount of tokens into the pool, receiving pool tokens in return.
     * @dev This function can only be called when the contract is active.
     * @param tokens The amount of tokens to deposit.
     * @param receiver The address of the receiver who will receive the pool tokens.
     */
    function deposit(uint256 tokens, address receiver) public onlyActive {
        // Checks
        if (tokens <= 0) {
            revert InvalidTokenAmount();
        }
        if (tokens > maxDeposit()) {
            revert DepositExceedsMax();
        }

        // Effects
        totalDeposited += tokens;
        _mint(receiver, tokens);

        // Interactions
        token.safeTransferFrom(msg.sender, address(this), tokens);

        emit ValtzEvents.ValtzPoolDeposit(msg.sender, receiver, tokens);
    }

    /**
     * @notice Redeems the user's tokens from the pool.
     * @dev This function allows users to redeem their deposited tokens along with any rewards earned.
     * @param amount The amount of tokens to redeem.
     * @param receiver The address to which the redeemed tokens should be sent.
     * @param valtzSignedData The data signed by the Valtz signer, checked by the pool contract
     * @param valtzSignature The signature of the Valtz signer.
     */
    function redeem(
        uint256 amount,
        address receiver,
        bytes memory valtzSignedData,
        bytes memory valtzSignature
    ) public onlyActive returns (uint256 withdrawAmount) {
        if (amount > validatorRedeemable) {
            revert RedeemAmountTooHigh(amount);
        }
        if (receiver == address(0)) {
            revert NullReceiver();
        }

        bytes32 hashed = ECDSA.toEthSignedMessageHash(valtzSignedData);
        address signer = ECDSA.recover(hashed, valtzSignature);
        if (!roleAuthority.hasRole(VALTZ_SIGNER_ROLE, signer)) {
            revert InvalidSigner(signer);
        }

        ValidationRedemptionData memory data =
            abi.decode(valtzSignedData, (ValidationRedemptionData));

        _validateRedemptionData(data);

        _consumeInterval(data.nodeID, LibInterval.Interval(data.start, data.end));

        totalDeposited -= amount;
        _burn(msg.sender, amount);
        uint256 rewardAmount = calculateReward(amount);
        availableRewards -= rewardAmount;
        withdrawAmount = amount + rewardAmount;
        token.safeTransfer(receiver, withdrawAmount);

        emit ValtzEvents.ValtzPoolRedeem(msg.sender, receiver, amount, withdrawAmount);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    OWNER
    ///////////////////////////////////////////////////////////////////////// */

    /**
     * @notice Starts the ValtzPool.
     * @dev This function can only be called by the owner and only if the pool is not already active.
     */
    function start() public onlyOwner onlyBeforeActive {
        startAt(uint40(block.timestamp));
    }

    /**
     * @notice Sets the start time for the pool.
     * @dev This function can only be called by the owner and only before the pool becomes active.
     * @param _startTime The start time to be set for the pool, represented as a uint40.
     */
    function startAt(uint40 _startTime) public onlyOwner onlyBeforeActive {
        if (started) {
            revert AlreadyActive();
        }
        started = true;
        if (_startTime < block.timestamp) {
            revert MustStartInCurrentOrFutureBlock();
        }
        startTime = _startTime;
        availableRewards = calculateReward(max);
        token.safeTransferFrom(msg.sender, address(this), availableRewards);
        emit ValtzEvents.ValtzPoolStart(_startTime);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    VIEW
    ///////////////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the reward based on the given amount.
     * @param amount The amount for which the reward is to be calculated.
     * @return The calculated reward.
     */
    function calculateReward(uint256 amount) public view returns (uint256) {
        return (amount * boostRate) / BOOST_RATE_PRECISION;
    }

    /**
     * @notice Retrieves the current reward pool balance.
     * @dev This function returns the total amount of rewards available in the pool.
     * @return The current reward pool balance as a uint256.
     */
    function rewardPool() public view returns (uint256) {
        return calculateReward(max);
    }

    /**
     * @notice Returns the maximum amount that can be deposited into the pool.
     * @dev This function provides the upper limit for deposits.
     * @return The maximum deposit amount as a uint256.
     */
    function maxDeposit() public view returns (uint256) {
        return max > totalDeposited ? max - totalDeposited : 0;
    }

    /**
     * @notice The end time of the pool.
     * @dev This function provides the end time of the pool in Unix timestamp format.
     * @return The end time of the pool as a uint40 value.
     */
    function endTime() public view returns (uint40) {
        return startTime + poolTerm;
    }

    /**
     * @notice Whether the pool is currently open.
     * @return bool indicating whether the pool is open.
     */
    function isOpen() public view returns (bool) {
        return started && (block.timestamp < endTime());
    }

    /**
     * @notice Checks if the pool is closed.
     * @dev This function returns a boolean indicating the closed status of the pool.
     * @return bool True if the pool is closed, false otherwise.
     */
    function isClosed() public view returns (bool) {
        return started && (block.timestamp >= endTime());
    }

    /**
     * @notice Retrieves the intervals associated with a specific validator node.
     * @param nodeID The unique identifier of the validator node.
     * @return An array of intervals during which the validator node was active.
     */
    function validatorIntervals(bytes32 nodeID)
        public
        view
        returns (LibInterval.Interval[] memory)
    {
        return _validatorIntervals[nodeID];
    }

    /* /////////////////////////////////////////////////////////////////////////
                                VALIDATION CHECKS
    ///////////////////////////////////////////////////////////////////////// */

    function _validateRedemptionData(ValidationRedemptionData memory data) internal view {
        if (data.chainId != block.chainid) {
            revert InvalidChainId(data.chainId);
        }

        if (data.target != address(this)) {
            revert InvalidTarget(data.target);
        }

        if (
            block.timestamp < data.signedAt || block.timestamp > data.signedAt + VALTZ_SIGNATURE_TTL
        ) {
            revert InvalidSignedAt(data.signedAt);
        }

        if (data.subnetID != subnetID) {
            revert InvalidSubnetID(data.subnetID);
        }

        if (data.duration != validatorDuration) {
            revert InvalidDuration(data.duration);
        }

        if (data.redeemer != msg.sender) {
            revert InvalidRedeemer(data.redeemer);
        }
    }

    function _consumeInterval(bytes32 nodeID, LibInterval.Interval memory interval) internal {
        LibInterval.Interval[] storage intervals = _validatorIntervals[nodeID];
        if (interval.overlapsAny(intervals)) {
            revert IntervalOverlap();
        }
        intervals.push(interval);
    }

    /* /////////////////////////////////////////////////////////////////////////
                                    RESCUE
    ///////////////////////////////////////////////////////////////////////// */

    function rescueERC20(IERC20 _token, address to, uint256 amount) public onlyOwner {
        if (!isClosed()) {
            if (_token == token) {
                revert CannotRescuePrimaryToken();
            }
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
                                    MODIFIERS
    ///////////////////////////////////////////////////////////////////////// */

    modifier onlyBeforeActive() {
        if (started) {
            revert PoolNotActive();
        }
        _;
    }

    modifier onlyActive() {
        if (!started || isClosed()) {
            revert PoolNotActive();
        }
        _;
    }
}
