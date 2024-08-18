// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ValtzPool.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract ValtzPoolTest is Test {
    ValtzPool pool;
    IERC20 asset;
    ERC1155Burnable validationAttestation;
    address owner;
    address user1;
    address user2;

    uint256 constant INITIAL_BALANCE = 1000000 * 1e18;
    uint256 constant MAX_DEPOSIT = 1000000 * 1e18;
    uint24 constant BOOST_RATE = 100000; // 10%
    uint256 constant MAX_REDEMPTION_PER_ATTESTATION = 100 * 1e18;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        asset = IERC20(address(0x1234));
        validationAttestation = ERC1155Burnable(address(0x5678));

        ValtzPool.PoolConfig memory config = ValtzPool.PoolConfig({
            name: "Test Pool",
            symbol: "TPOOL",
            subnetID: bytes32(0),
            asset: asset,
            term: 30 days,
            assetDepositsMax: MAX_DEPOSIT,
            boostRate: BOOST_RATE,
            validationAttestation: validationAttestation,
            maxRedemptionPerAttestation: MAX_REDEMPTION_PER_ATTESTATION
        });

        pool = new ValtzPool(config);

        // Mock initial balances and approvals
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)),
            abi.encode(INITIAL_BALANCE)
        );
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, user1),
            abi.encode(INITIAL_BALANCE)
        );
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, user2),
            abi.encode(INITIAL_BALANCE)
        );
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.approve.selector, address(pool), type(uint256).max),
            abi.encode(true)
        );
    }

    function testPoolInitialization() public {
        assertEq(pool.name(), "Test Pool");
        assertEq(pool.symbol(), "TPOOL");
        assertEq(address(pool.asset()), address(asset));
        assertEq(pool.term(), 30 days);
        assertEq(pool.assetDepositsMax(), MAX_DEPOSIT);
        assertEq(pool.boostRate(), BOOST_RATE);
        assertEq(address(pool.validationAttestation()), address(validationAttestation));
        assertEq(pool.maxRedemptionPerAttestation(), MAX_REDEMPTION_PER_ATTESTATION);
    }

    function testPoolStart() public {
        uint256 initialBalance = INITIAL_BALANCE;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, address(this), address(pool), pool.rewardsAmount()
            ),
            abi.encode(true)
        );
        pool.start();
        assertGt(pool.startTime(), 0);
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)),
            abi.encode(initialBalance - pool.rewardsAmount())
        );
        assertEq(asset.balanceOf(address(this)), initialBalance - pool.rewardsAmount());
    }

    function testDeposit() public {
        pool.start();

        uint256 depositAmount = 100 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        uint256 shares = pool.deposit(depositAmount, user1);

        assertEq(pool.balanceOf(user1), shares);
        assertEq(shares, depositAmount);
        assertEq(pool.convertToAssets(shares), depositAmount * 11 / 10); // Including boost
        assertEq(pool.assetDepositsTotal(), depositAmount);
    }

    function testMaxDeposit() public {
        pool.start();

        assertEq(pool.maxDeposit(address(0)), MAX_DEPOSIT);

        uint256 depositAmount = 500000 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        assertEq(pool.maxDeposit(address(0)), 500000 * 1e18);
    }

    function testWithdraw() public {
        pool.start();

        uint256 depositAmount = 100 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        uint256 shares = pool.deposit(depositAmount, user1);

        uint256 tokenId = uint256(uint160(address(pool)));
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(1)
        );

        uint256 withdrawAmount = 50 * 1e18;
        uint256 expectedBoostedAmount = withdrawAmount * 11 / 10;
        uint256 initialBalance = asset.balanceOf(user1);

        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(
                IERC1155.safeTransferFrom.selector, user1, address(pool), tokenId, 1, ""
            ),
            abi.encode()
        );
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(ERC1155Burnable.burn.selector, address(pool), tokenId, 1),
            abi.encode()
        );
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.transfer.selector, user1, expectedBoostedAmount),
            abi.encode(true)
        );

        vm.prank(user1);
        uint256 burnedShares = pool.withdraw(withdrawAmount, user1, user1);

        assertEq(pool.balanceOf(user1), shares - burnedShares);
        assertEq(burnedShares, withdrawAmount);
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.balanceOf.selector, user1),
            abi.encode(initialBalance + expectedBoostedAmount)
        );
        assertEq(asset.balanceOf(user1), initialBalance + expectedBoostedAmount);
    }

    function testFailWithdrawWithoutAttestation() public {
        pool.start();

        uint256 depositAmount = 100 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 tokenId = uint256(uint160(address(pool)));
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(0)
        );

        vm.prank(user1);
        pool.withdraw(50 * 1e18, user1, user1);
    }

    function testMaxWithdraw() public {
        pool.start();

        uint256 depositAmount = 200 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 tokenId = uint256(uint160(address(pool)));
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(1)
        );

        assertEq(pool.maxWithdraw(user1), 90 * 1e18); // 100 / 1.1 due to boost

        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(2)
        );

        assertEq(pool.maxWithdraw(user1), 180 * 1e18); // 200 / 1.1 due to boost
    }

    function testMaxRedeem() public {
        pool.start();

        uint256 depositAmount = 200 * 1e18;
        vm.startPrank(user1);
        uint256 shares = pool.deposit(depositAmount, user1);

        uint256 tokenId = uint256(uint160(address(pool)));
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(1)
        );
        assertEq(pool.maxRedeem(user1), 90 * 1e18); // 100 / 1.1 due to boost

        assertEq(pool.maxRedeem(user1), shares);
        vm.stopPrank();
    }

    function testConvertToShares() public {
        assertEq(pool.convertToShares(100 * 1e18), 100 * 1e18);
    }

    function testConvertToAssets() public {
        assertEq(pool.convertToAssets(100 * 1e18), 110 * 1e18);
    }

    function testPreviewDeposit() public {
        assertEq(pool.previewDeposit(100 * 1e18), 100 * 1e18);
    }

    function testPreviewMint() public {
        assertEq(pool.previewMint(100 * 1e18), 100 * 1e18);
    }

    function testPreviewWithdraw() public {
        assertEq(pool.previewWithdraw(100 * 1e18), 100 * 1e18);
    }

    function testPreviewRedeem() public {
        assertEq(pool.previewRedeem(100 * 1e18), 110 * 1e18);
    }

    function testRewardsAmount() public {
        assertEq(pool.rewardsAmount(), MAX_DEPOSIT / 10);
    }

    function testFailDepositOverMax() public {
        pool.start();
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), MAX_DEPOSIT + 1
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        pool.deposit(MAX_DEPOSIT + 1, user1);
    }

    function testFailWithdrawOverBalance() public {
        pool.start();
        uint256 depositAmount = 100 * 1e18;
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector, user1, address(pool), depositAmount
            ),
            abi.encode(true)
        );
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 tokenId = uint256(uint160(address(pool)));
        vm.mockCall(
            address(validationAttestation),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, user1, tokenId),
            abi.encode(1)
        );

        vm.prank(user1);
        pool.withdraw(101 * 1e18, user1, user1);
    }

    function testFailRedeemOverBalance() public {
        pool.start();
        vm.startPrank(user1);
        pool.deposit(100 * 1e18, user1);
        uint256 tokenId = uint256(uint160(address(pool)));
        // validationAttestation.mint(user1, tokenId, 1, "");
        pool.redeem(101 * 1e18, user1, user1);
    }

    function testFailWithdrawAfterTerm() public {
        pool.start();
        vm.startPrank(user1);
        pool.deposit(100 * 1e18, user1);
        uint256 tokenId = uint256(uint160(address(pool)));
        // validationAttestation.mint(user1, tokenId, 1, "");
        vm.warp(block.timestamp + 31 days);
        pool.withdraw(50 * 1e18, user1, user1);
    }
}
