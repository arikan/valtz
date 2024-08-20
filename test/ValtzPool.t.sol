// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ValtzPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

// Minimal MockERC20 contract
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ValtzPoolTest is Test {
    ValtzPool public pool;
    MockERC20 public asset;
    IERC1155 public validationAttestation;
    address public owner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_BALANCE = 1000 * 1e18;
    uint256 constant MAX_DEPOSIT = 1000000 * 1e18;
    uint24 constant BOOST_RATE = 1100000; // 110%
    uint256 constant MAX_REDEMPTION_PER_ATTESTATION = 100 * 1e18;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        asset = new MockERC20();
        validationAttestation = IERC1155(address(0x5678));

        ValtzPool.PoolConfig memory config = ValtzPool.PoolConfig({
            name: "Test Pool",
            symbol: "TPOOL",
            subnetID: bytes32(0),
            asset: asset,
            term: 30 days,
            assetDepositsMax: MAX_DEPOSIT,
            boostRate: BOOST_RATE,
            validationAttestation: ERC1155Burnable(address(validationAttestation)),
            maxRedeemablePerValidationAttestation: MAX_REDEMPTION_PER_ATTESTATION
        });

        pool = new ValtzPool(config);

        // Mint initial balances
        asset.mint(address(this), 100000000 ether);
        asset.mint(user1, INITIAL_BALANCE);
        asset.mint(user2, INITIAL_BALANCE);

        // Approve pool to spend tokens
        vm.prank(address(this));
        asset.approve(address(pool), type(uint256).max);
        vm.prank(user1);
        asset.approve(address(pool), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(pool), type(uint256).max);

        pool.start();
    }

    function testDeposit() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        assertEq(asset.balanceOf(address(pool)), depositAmount + pool.rewardsAmount());
        assertEq(asset.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(pool.balanceOf(user1), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 withdrawAmount = 50 * 1e18;
        uint256 tokenId = uint256(uint160(address(pool)));

        // Mock the validationAttestation balance
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(1)
        );

        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(
                IERC1155.safeTransferFrom.selector, user1, address(pool), tokenId, 1, ""
            ),
            abi.encode(true)
        );

        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(ERC1155Burnable.burn.selector, address(pool), tokenId, 1),
            abi.encode(true)
        );

        uint256 expectedAmount =
            withdrawAmount + (withdrawAmount * BOOST_RATE / pool.BOOST_RATE_PRECISION());

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user1);
        assertEq(redeemedAmount, expectedAmount);

        //     assertEq(asset.balanceOf(address(pool)), depositAmount - withdrawAmount);
        assertEq(asset.balanceOf(user1), INITIAL_BALANCE - depositAmount + expectedAmount);
        assertEq(pool.balanceOf(user1), depositAmount - withdrawAmount);
    }
}
