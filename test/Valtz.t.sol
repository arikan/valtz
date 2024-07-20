// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Valtz.sol";
import "../src/ReceiptToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ValtzTest is Test {
    Valtz public valtz;
    MockERC20 public token;
    address public owner;
    address public creator;
    address public user;
    bytes32 public subnetID;

    function setUp() public {
        owner = address(this);
        creator = address(0x1);
        user = address(0x2);
        subnetID = keccak256("testSubnet");

        valtz = new Valtz();
        token = new MockERC20();

        valtz.allowCreator(creator, subnetID);
        token.mint(creator, 10000 * 10 ** 18);
        token.mint(user, 1000 * 10 ** 18);
    }

    function testCreatePool() public {
        vm.startPrank(creator);
        token.approve(address(valtz), 1000 * 10 ** 18);
        valtz.createPool(IERC20(address(token)), 1000 * 10 ** 18, 20, 7 days, subnetID);
        vm.stopPrank();

        assertEq(valtz.poolCount(), 1);
    }

    function testDepositToPool() public {
        testCreatePool();

        vm.startPrank(user);
        token.approve(address(valtz), 100 * 10 ** 18);
        valtz.depositToPool(0, 100 * 10 ** 18);
        vm.stopPrank();

        (,, uint256 lockedBalance,,,,) = valtz.pools(0);
        assertEq(lockedBalance, 100 * 10 ** 18);

        ReceiptToken receiptToken = valtz.receiptTokens(0);
        assertEq(receiptToken.balanceOf(user), 100 * 10 ** 18);
    }

    function testExternalVerifyValidationProof() public view {
        bytes memory validProof = abi.encodePacked("validProof");
        bytes memory invalidProof = "";

        assertTrue(valtz.verifyValidationProof(validProof, 0, 100 * 10 ** 18, 7 days));
        assertFalse(valtz.verifyValidationProof(invalidProof, 0, 100 * 10 ** 18, 7 days));
    }

    function testClaimReward() public {
        testDepositToPool();

        // Simulate passage of time
        vm.warp(block.timestamp + 7 days);

        uint256 initialBalance = token.balanceOf(user);

        vm.startPrank(user);
        ReceiptToken(valtz.receiptTokens(0)).approve(address(valtz), 100 * 10 ** 18);
        valtz.claimReward(0, 100 * 10 ** 18, abi.encodePacked("validProof"));
        vm.stopPrank();

        uint256 finalBalance = token.balanceOf(user);
        assertEq(finalBalance - initialBalance, 120 * 10 ** 18); // 100 deposit + 20 reward (20% of 100)
    }

    function testWithdrawReward() public {
        testCreatePool();

        uint256 initialBalance = token.balanceOf(creator);

        vm.startPrank(creator);
        valtz.withdrawReward(0, 500 * 10 ** 18);
        vm.stopPrank();

        uint256 finalBalance = token.balanceOf(creator);
        assertEq(finalBalance - initialBalance, 500 * 10 ** 18);
    }

    function testIncreasePoolReward() public {
        testCreatePool();

        vm.startPrank(creator);
        token.approve(address(valtz), 500 * 10 ** 18);
        valtz.increasePoolReward(0, 500 * 10 ** 18);
        vm.stopPrank();

        (, uint256 rewardBalance,,,,,) = valtz.pools(0);
        assertEq(rewardBalance, 1500 * 10 ** 18);
    }

    function testRemoveCreator() public {
        valtz.removeCreator(creator);
        assertEq(valtz.allowedCreators(creator), bytes32(0));
    }

    function testFailCreatePoolUnauthorized() public {
        vm.prank(user);
        valtz.createPool(IERC20(address(token)), 1000 * 10 ** 18, 20, 7 days, subnetID);
    }

    function testFailWithdrawRewardUnauthorized() public {
        testCreatePool();

        vm.prank(user);
        valtz.withdrawReward(0, 500 * 10 ** 18);
    }

    function testFailExceedMaxDepositLimit() public {
        testCreatePool();

        vm.startPrank(user);
        token.approve(address(valtz), 6000 * 10 ** 18);
        valtz.depositToPool(0, 6000 * 10 ** 18); // Should fail as it exceeds the max deposit limit
        vm.stopPrank();
    }
}
