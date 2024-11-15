// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ValtzPoolRedeemTestBase.t.sol";

contract ValtzPoolRedeemBasicTest is ValtzPoolRedeemTestBase {
    function test_redeem() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        uint256 withdrawAmount = 50 * 1e18;
        uint256 expectedAmount = _calculateExpectedAmount(withdrawAmount);

        vm.expectEmit(true, true, true, true);
        emit ValtzPoolRedeem(user1, user2, withdrawAmount, expectedAmount);

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user2, abi.encode(data), signature);
        assertEq(redeemedAmount, expectedAmount);

        assertEq(token.balanceOf(user1), INITIAL_BALANCE - 100 * 1e18);
        assertEq(pool.balanceOf(user1), 50 * 1e18);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE + expectedAmount);
        assertEq(pool.balanceOf(user2), 0);
    }

    function test_redeem_ExactValidatorRedeemable() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, VALIDATOR_REDEEMABLE * 2);

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        uint256 expectedAmount = _calculateExpectedAmount(VALIDATOR_REDEEMABLE);

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(VALIDATOR_REDEEMABLE, user2, abi.encode(data), signature);
        assertEq(redeemedAmount, expectedAmount);
    }

    function test_redeem_AfterPoolEnd() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        // Warp to after pool end
        vm.warp(pool.endTime() + 30 days);

        // Create validation data for a period during pool's active time
        uint40 validationStart = uint40(pool.endTime() - pool.validatorDuration() - 100);
        uint40 validationEnd = uint40(pool.endTime() - 50);

        // Create and sign the validation data now (after pool end)
        ValtzPool.ValidationRedemptionData memory data = _createValidationData(
            address(pool), user1, validationStart, validationEnd, bytes20(pool.subnetID()), bytes32(0)
        );

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        uint256 withdrawAmount = 50 * 1e18;
        uint256 expectedAmount = _calculateExpectedAmount(withdrawAmount);

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user2, abi.encode(data), signature);
        assertEq(redeemedAmount, expectedAmount);
    }

    function test_redeem_LargeNumbers() public {
        // Use a large but safe number that won't overflow
        uint256 maxValidatorRedeemable = 1e40;

        ValtzPool.PoolConfig memory config = IValtzPool.PoolConfig({
            owner: owner,
            name: "Large Numbers Pool",
            symbol: "LPOOL",
            subnetID: bytes32(0),
            poolTerm: 3 * 365 days,
            token: token,
            validatorDuration: 30 days,
            validatorRedeemable: maxValidatorRedeemable,
            max: maxValidatorRedeemable * 2,
            boostRate: BOOST_RATE
        });

        ValtzPool largePool = ValtzPool(Clones.clone(address(new ValtzPool(IRoleAuthority(roleAuthority)))));
        largePool.initialize(config);

        // Mint tokens for rewards to owner
        token.mint(address(this), maxValidatorRedeemable * 3);
        token.approve(address(largePool), type(uint256).max);

        // Mint tokens for user1
        token.mint(user1, maxValidatorRedeemable * 2);
        vm.prank(user1);
        token.approve(address(largePool), type(uint256).max);

        largePool.start();

        // Deposit the maximum amount
        vm.prank(user1);
        largePool.deposit(maxValidatorRedeemable * 2, user1);

        vm.warp(BASE_START + largePool.validatorDuration() + EXTRA_DURATION);

        ValtzPool.ValidationRedemptionData memory data = _createValidationData(
            address(largePool),
            user1,
            BASE_START,
            uint40(BASE_START + largePool.validatorDuration() + EXTRA_DURATION),
            bytes20(largePool.subnetID()),
            bytes32(0)
        );

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        uint256 expectedAmount = _calculateExpectedAmount(maxValidatorRedeemable);

        vm.prank(user1);
        uint256 redeemedAmount = largePool.redeem(maxValidatorRedeemable, user2, abi.encode(data), signature);
        assertEq(redeemedAmount, expectedAmount);
        assertEq(token.balanceOf(user2), INITIAL_BALANCE + expectedAmount);
    }
}
