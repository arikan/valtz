// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./ReceiptToken.sol";

contract ValtzPool is ERC20, ERC20Permit, Ownable2Step, ERC1155Holder {
    using SafeERC20 for IERC20;

    struct PoolConfig {
        string name;
        string symbol;
        bytes32 subnetID;
        IERC20 asset;
        uint40 term;
        uint256 assetDepositsMax;
        uint24 boostRate;
        ERC1155Burnable validationAttestation;
        uint256 maxRedeemablePerValidationAttestation;
    }

    error WithdrawAmountExceedsBalance();
    error WithdrawDisabled();
    error InvalidValidationAttestation();

    uint24 public constant PRECISION = 1e6;

    bytes32 public immutable subnetID;
    address public immutable asset;
    uint40 public immutable term;
    uint256 public immutable assetDepositsMax;
    uint24 public immutable boostRate;
    ERC1155Burnable public immutable validationAttestation;
    uint256 public immutable maxRedeemablePerValidationAttestation;

    uint40 public startTime;
    uint256 public assetDepositsTotal;

    constructor(PoolConfig memory config)
        ERC20(config.name, config.symbol)
        ERC20Permit(config.name)
        Ownable(msg.sender)
    {
        subnetID = config.subnetID;
        term = config.term;
        assetDepositsMax = config.assetDepositsMax;
        boostRate = config.boostRate;
        validationAttestation = config.validationAttestation;
        maxRedeemablePerValidationAttestation = config.maxRedeemablePerValidationAttestation;
    }

    function _calculateBoostedAmount(uint256 amount) internal view returns (uint256) {
        return amount + (amount * boostRate) / PRECISION;
    }

    function maxShares() public view returns (uint256) {
        return assetDepositsMax;
    }

    function rewardsAmount() public view returns (uint256) {
        return _calculateBoostedAmount(assetDepositsMax) - assetDepositsMax;
    }

    function start() public onlyOwner onlyBeforeActive {
        startAt(uint40(block.timestamp));
    }

    function startAt(uint40 _startTime) public onlyOwner onlyBeforeActive {
        require(startTime == 0, "Already active");
        require(_startTime >= block.timestamp, "Must either cancel or set to start in future block");
        startTime = _startTime;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), rewardsAmount());
    }

    function maxDeposit

    function deposit(uint256 assets, address receiver)
        public
        override
        onlyActive
        returns (uint256)
    {
        require(assets <= maxDeposit(receiver), "Deposit exceeds max limit");
        assetDepositsTotal += assets;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, assets);
        return assets;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 tokenId = uint256(uint160(address(this)));
        uint256 attestationBalance = validationAttestation.balanceOf(owner, tokenId);
        if (attestationBalance == 0) {
            return 0;
        }
        uint256 maxWithdrawBasedOnShares = balanceOf(owner);
        uint256 maxWithdrawBasedOnAttestations = attestationBalance * deposit;
        return Math.min(maxWithdrawBasedOnShares, maxWithdrawBasedOnAttestations) * PRECISION
            / (PRECISION + boostRate);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        onlyActive
        returns (uint256)
    {
        if (assets > maxWithdraw(owner)) {
            revert WithdrawAmountExceedsBalance();
        }

        uint256 boostedAssets = _calculateBoostedAmount(assets);
        uint256 attestationsToBurn = (boostedAssets + deposit - 1) / deposit;
        _burnValidationAttestation(owner, attestationsToBurn);

        _burn(owner, assets);
        IERC20(asset()).safeTransfer(receiver, boostedAssets);

        return assets;
    }

    function _burnValidationAttestation(address owner, uint256 amount) internal {
        uint256 tokenId = uint256(uint160(address(this)));

        if (validationAttestation.balanceOf(owner, tokenId) < amount) {
            revert InvalidValidationAttestation();
        }

        validationAttestation.safeTransferFrom(owner, address(this), tokenId, amount, "");
        validationAttestation.burn(address(this), tokenId, amount);
    }

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
