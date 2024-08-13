// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./ReceiptToken.sol";

/**
 * A ValtzPool is an ERC4626 vault protocol allowing staking of
 * an asset to receive a pool token. At a later time, a proof of validation
 * can be submitted along with the pool token in order to withdraw the
 * original asset at a boosted rate.
 *
 * The original asset is only withdrawable with the proof of validation.
 *
 * The pool will be started by the current owner, and starting the pool requires
 * deposit of the rewards pool that is used for the boosted withdrawals.
 */
contract ValtzPool is Ownable2Step, ERC4626 {
    using SafeERC20 for IERC20;

    struct PoolConfig {
        string name;
        string symbol;
        bytes32 subnetId;
        IERC20 asset;
        uint40 term;
        uint256 assetDepositsMax;
        uint24 boostRate;
    }

    error WithdrawAmountExceedsBalance();
    error WithdrawDisabled();

    uint24 public constant PRECISION = 1e6;

    bytes32 public immutable subnetId;
    uint40 public immutable term;
    uint256 public immutable assetDepositsMax;
    uint24 public immutable boostRate;

    uint40 public startTime;
    uint256 public assetDepositsTotal;

    enum RedemptionPassState {
        None,
        Available,
        Burned
    }

    mapping(address => mapping(bytes32 => RedemptionPassState)) public redemptionPasses;

    constructor(PoolConfig memory config)
        Ownable(msg.sender)
        ERC20(config.name, config.symbol)
        ERC4626(config.asset)
    {
        subnetId = config.subnetId;
        term = config.term;
        assetDepositsMax = config.assetDepositsMax;
        boostRate = config.boostRate;
    }

    /**
     * @dev Converts an asset value to shares.
     * @param _assetsValue The amount of assets.
     * @return The equivalent amount of shares.
     */
    function _assetsToShares(uint256 _assetsValue) internal view returns (uint256) {
        return (_assetsValue * (PRECISION + boostRate)) / PRECISION;
    }

    /**
     * @dev Converts a share value to assets.
     * @param _sharesValue The amount of shares.
     * @return The equivalent amount of assets.
     */
    function _sharesToAssets(uint256 _sharesValue) internal view returns (uint256) {
        return (PRECISION * _sharesValue) / (PRECISION + boostRate);
    }

    /**
     * @dev Returns the maximum shares based on the assetDepositsMax.
     * @return The maximum shares.
     */
    function maxShares() public view returns (uint256) {
        return _assetsToShares(assetDepositsMax);
    }

    /**
     * @dev Returns the amount of rewards.
     * @return The rewards amount.
     */
    function rewardsAmount() public view returns (uint256) {
        return _assetsToShares(assetDepositsMax) - assetDepositsMax;
    }

    /**
     * @dev Starts the pool.
     */
    function start() public onlyOwner onlyBeforeActive {
        startAt(uint40(block.timestamp));
    }

    /**
     * @dev Starts the pool at a specific time.
     * @param _startTime The start time.
     */
    function startAt(uint40 _startTime) public onlyOwner onlyBeforeActive {
        require(startTime == 0, "Already active");
        require(_startTime >= block.timestamp, "Must either cancel or set to start in future block");
        startTime = _startTime;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), rewardsAmount());
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _assetsToShares(assets);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _sharesToAssets(shares);
    }

    /**
     * @dev Returns the maximum amount of assets that can be deposited.
     * @return The maximum deposit amount.
     */
    function maxDeposit(address) public view override returns (uint256) {
        return assetDepositsMax - assetDepositsTotal;
    }

    /**
     * @dev Previews the amount of shares that would be received for a given deposit of assets.
     * @param assets The amount of assets.
     * @return The amount of shares.
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @dev Deposits assets and mints shares.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        onlyActive
        returns (uint256)
    {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit exceeds max limit");
        assetDepositsTotal += assets;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        uint256 shares = convertToShares(assets);
        _mint(receiver, shares);
        return shares;
    }

    /**
     * @dev Returns the maximum amount of shares that can be minted.
     * @return The maximum mint amount.
     */
    function maxMint(address) public view override returns (uint256) {
        return maxShares() - totalSupply();
    }

    /**
     * @dev Previews the amount of assets that would be required to mint a given amount of shares.
     * @param shares The amount of shares.
     * @return The amount of assets required.
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @dev Mints shares by depositing assets.
     * @param shares The amount of shares to mint.
     * @param receiver The address of the receiver.
     * @return The amount of assets deposited.
     */
    function mint(uint256 shares, address receiver) public override onlyActive returns (uint256) {
        uint256 assets = previewMint(shares);
        require(assets <= maxDeposit(receiver), "ERC4626: mint exceeds max limit");
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // TODO - check if there's a redemption pass for the owner
        // If not, return 0
        return convertToAssets(balanceOf(owner));
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        returns (uint256)
    {
        //
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // TODO - check if there's a redemption pass for the owner
        // If not, return 0
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    /**
     * @dev Redeems shares for assets.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return The amount of assets redeemed.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyActive
        returns (uint256)
    {
        require(shares <= maxRedeem(owner), "ERC4626: redeem exceeds balance");
        _burn(owner, shares);
        uint256 assets = previewRedeem(shares);
        IERC20(asset()).safeTransfer(receiver, assets);
        return assets;
    }

    function addRedemptionPass(address redeemer, bytes memory data, address signer)
        public
        onlyOwner
    {}

    /* Modifiers */

    modifier onlyBeforeActive() {
        require(startTime == 0, "Already activated");
        _;
    }

    modifier onlyActive() {
        require(startTime > 0, "Not activated");
        require(block.timestamp < startTime + term, "Not activated");
        _;
    }
}
