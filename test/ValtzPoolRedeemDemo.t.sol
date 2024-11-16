// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ValtzPoolRedeemTestBase.t.sol";

contract ValtzPoolRedeemDemoTest is ValtzPoolRedeemTestBase {
    function setUp() public override {
        super.setUp();
        pool.setDemoMode(true);
    }

    function test_DemoMode_AllowsAllWrongValues() public {
        // Double the deposit to allow for two redemptions
        (uint40 start, uint40 end) = _setupRedemption(user1, VALIDATOR_REDEEMABLE * 2);
        bytes20 nodeID = bytes20(uint160(1));

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, nodeID, bytes32(0));

        // Modify all values that should be allowed to be wrong in demo mode
        data.chainId = block.chainid + 1; // Wrong chain ID
        data.target = address(0xdead); // Wrong target address
        data.subnetID = bytes32(uint256(1)); // Wrong subnet ID
        data.duration = pool.validatorDuration() + 1; // Wrong duration
        data.signedAt = uint40(block.timestamp + 1); // Future timestamp
        data.end = uint40(block.timestamp + 1 days); // Future interval end

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        // First redemption should work with all wrong values
        vm.prank(user1);
        uint256 withdrawAmount = pool.redeem(VALIDATOR_REDEEMABLE, user1, abi.encode(data), signature);
        assertEq(withdrawAmount, _calculateExpectedAmount(VALIDATOR_REDEEMABLE));

        // Second redemption with overlapping interval should also work
        vm.prank(user1);
        withdrawAmount = pool.redeem(VALIDATOR_REDEEMABLE, user1, abi.encode(data), signature);
        assertEq(withdrawAmount, _calculateExpectedAmount(VALIDATOR_REDEEMABLE));
    }
}
