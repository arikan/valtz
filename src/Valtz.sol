// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ReceiptToken.sol";

contract Valtz is Ownable {
    using SafeERC20 for IERC20;

    struct Pool {
        IERC20 token;
        uint256 rewardBalance;
        uint256 lockedBalance;
        uint256 boostRate;
        uint256 requiredDuration;
        bytes32 subnetID;
        address creator;
    }

    mapping(uint256 => Pool) public pools;
    uint256 public poolCount;

    mapping(uint256 => ReceiptToken) public receiptTokens;

    // Allowlist mapping creators to their specific subnets
    mapping(address => bytes32) public allowedCreators;

    event PoolCreated(
        uint256 indexed poolId,
        address indexed creator,
        address token,
        uint256 rewardAmount,
        uint256 boostRate,
        uint256 requiredDuration,
        bytes32 subnetID
    );
    event Deposited(uint256 indexed poolId, address indexed depositor, uint256 amount);
    event RewardClaimed(uint256 indexed poolId, address indexed claimer, uint256 depositAmount, uint256 rewardAmount);
    event RewardWithdrawn(uint256 indexed poolId, address indexed creator, uint256 amount);
    event PoolRewardIncreased(uint256 indexed poolId, uint256 additionalReward);
    event CreatorAllowed(address indexed account, bytes32 subnetID);
    event CreatorRemoved(address indexed account, bytes32 subnetID);

    constructor() Ownable(msg.sender) {}

    function allowCreator(address _account, bytes32 _subnetID) external onlyOwner {
        allowedCreators[_account] = _subnetID;
        emit CreatorAllowed(_account, _subnetID);
    }

    function removeCreator(address _account) external onlyOwner {
        bytes32 subnetID = allowedCreators[_account];
        require(subnetID != bytes32(0), "Creator not in allow list");

        for (uint256 i = 0; i < poolCount; i++) {
            require(pools[i].subnetID != subnetID, "Cannot remove creator with existing pools");
        }

        delete allowedCreators[_account];
        emit CreatorRemoved(_account, subnetID);
    }

    /**
     * @notice Creates a new staking pool
     * @dev Only allowed creators for a specific subnet can create pools
     * @param _token The ERC20 token used for staking and rewards
     * @param _rewardAmount The initial amount of tokens for rewards
     * @param _boostRate The boost rate for rewards (1-100)
     * @param _requiredDuration The required staking duration
     * @param _subnetID The ID of the subnet for this pool
     */
    function createPool(
        IERC20 _token,
        uint256 _rewardAmount,
        uint256 _boostRate,
        uint256 _requiredDuration,
        bytes32 _subnetID
    ) external {
        require(allowedCreators[msg.sender] == _subnetID, "Caller is not allowed to create pools for this subnet");
        require(_rewardAmount > 0, "Reward amount must be greater than 0");
        require(_boostRate > 0 && _boostRate <= 100, "Boost rate must be between 1 and 100");
        require(_requiredDuration > 0, "Required duration must be greater than 0");

        uint256 poolId = poolCount;
        Pool storage newPool = pools[poolId];
        newPool.token = _token;
        newPool.rewardBalance = _rewardAmount;
        newPool.boostRate = _boostRate;
        newPool.requiredDuration = _requiredDuration;
        newPool.subnetID = _subnetID;
        newPool.creator = msg.sender;

        string memory receiptName = string(abi.encodePacked("Receipt Token for Pool ", poolId));
        string memory receiptSymbol = string(abi.encodePacked("RP", poolId));
        ReceiptToken receiptToken = new ReceiptToken(receiptName, receiptSymbol, address(this));
        receiptTokens[poolId] = receiptToken;

        _token.safeTransferFrom(msg.sender, address(this), _rewardAmount);

        poolCount++;

        emit PoolCreated(poolId, msg.sender, address(_token), _rewardAmount, _boostRate, _requiredDuration, _subnetID);
    }

    /**
     * @notice Allows users to deposit tokens into a specific pool
     * @dev Mints receipt tokens to represent the user's stake and the reward
     * @param _poolId The ID of the pool to deposit into
     * @param _amount The amount of tokens to deposit
     */
    function depositToPool(uint256 _poolId, uint256 _amount) external {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        require(_amount > 0, "Amount must be greater than 0");

        uint256 maxDepositLimit = getMaxDepositLimit(_poolId);
        require(pool.lockedBalance + _amount <= maxDepositLimit, "Deposit would exceed pool limit");

        pool.token.safeTransferFrom(msg.sender, address(this), _amount);
        pool.lockedBalance += _amount;

        receiptTokens[_poolId].mint(msg.sender, _amount);

        emit Deposited(_poolId, msg.sender, _amount);
    }

    /**
     * @notice Allows users to claim rewards and withdraw their stake
     * @dev Requires a valid proof of staking duration
     * @param _poolId The ID of the pool to claim from
     * @param _amount The amount of receipt/futures token (burned after transferring deposit + rewards)
     * @param _validationProof Proof of required staking duration
     */
    function claimReward(uint256 _poolId, uint256 _amount, bytes memory _validationProof) external {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        require(_amount > 0, "Amount must be greater than 0");

        require(
            _verifyValidationProof(_validationProof, _poolId, _amount, pool.requiredDuration),
            "Invalid validation proof"
        );

        uint256 reward = calculateReward(_amount, pool.boostRate);

        require(pool.rewardBalance >= reward, "Insufficient reward balance");
        require(pool.lockedBalance >= _amount, "Insufficient locked balance");

        ReceiptToken receiptToken = receiptTokens[_poolId];

        require(receiptToken.balanceOf(msg.sender) >= _amount, "Insufficient receipt tokens");
        require(
            receiptToken.allowance(msg.sender, address(this)) >= _amount, "Insufficient allowance for receipt tokens"
        );

        receiptToken.burn(msg.sender, _amount);

        pool.token.safeTransfer(msg.sender, _amount + reward);
        pool.rewardBalance -= reward;
        pool.lockedBalance -= _amount;

        emit RewardClaimed(_poolId, msg.sender, _amount, reward);
    }

    /**
     * @notice Allows pool creators to withdraw excess rewards
     * @dev Only the pool creator can withdraw, and only excess rewards can be withdrawn
     * @param _poolId The ID of the pool to withdraw from
     * @param _amount The amount of rewards to withdraw
     */
    function withdrawReward(uint256 _poolId, uint256 _amount) external {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        require(msg.sender == pool.creator, "Only pool creator can withdraw rewards");

        uint256 availableForWithdrawal = pool.rewardBalance - pool.lockedBalance;
        require(_amount <= availableForWithdrawal, "Amount exceeds available balance");

        pool.token.safeTransfer(msg.sender, _amount);
        pool.rewardBalance -= _amount;

        emit RewardWithdrawn(_poolId, msg.sender, _amount);
    }

    /**
     * @notice Allows pool creators to increase the reward balance of a pool
     * @dev Only the pool creator can increase rewards
     * @param _poolId The ID of the pool to increase rewards for
     * @param _additionalReward The amount of additional rewards to add
     */
    function increasePoolReward(uint256 _poolId, uint256 _additionalReward) external {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        require(msg.sender == pool.creator, "Only pool creator can increase reward");
        require(_additionalReward > 0, "Additional reward must be greater than 0");

        pool.token.safeTransferFrom(msg.sender, address(this), _additionalReward);
        pool.rewardBalance += _additionalReward;

        emit PoolRewardIncreased(_poolId, _additionalReward);
    }

    function calculateReward(uint256 _amount, uint256 _boostRate) internal pure returns (uint256) {
        return _amount * _boostRate / 100;
    }

    function verifyValidationProof(bytes memory _proof, uint256 _poolId, uint256 _amount, uint256 _duration)
        public
        pure
        returns (bool)
    {
        return _verifyValidationProof(_proof, _poolId, _amount, _duration);
    }

    function _verifyValidationProof(
        bytes memory _proof,
        uint256, /*_poolId*/
        uint256, /*_amount*/
        uint256 /*_duration*/
    ) internal pure returns (bool) {
        // For testing purposes, we'll accept any non-empty proof
        // In a real implementation, this would contain actual verification logic
        // using _poolId, _amount, and _duration
        return _proof.length > 0;
    }

    function getAvailableRewardBalance(uint256 _poolId) external view returns (uint256) {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        return pool.rewardBalance > pool.lockedBalance ? pool.rewardBalance - pool.lockedBalance : 0;
    }

    function getMaxDepositLimit(uint256 _poolId) public view returns (uint256) {
        require(_poolId < poolCount, "Invalid pool ID");
        Pool storage pool = pools[_poolId];
        return pool.rewardBalance * 100 / pool.boostRate;
    }
}
