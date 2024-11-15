// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ValtzPoolRedeemTestBase.t.sol";

contract ValtzPoolRedeemErrorsTest is ValtzPoolRedeemTestBase {
    function test_revert_RedeemAmountTooHigh() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, VALIDATOR_REDEEMABLE * 2);

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.RedeemAmountTooHigh.selector, VALIDATOR_REDEEMABLE + 1));
        pool.redeem(VALIDATOR_REDEEMABLE + 1, user2, abi.encode(data), signature);
    }

    function test_revert_RedeemAmountExceedsTotalDeposited() public {
        uint256 depositAmount = 50 * 1e18;
        (uint40 start, uint40 end) = _setupRedemption(user1, depositAmount);

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.RedeemAmountExceedsTotalDeposited.selector, depositAmount + 1));
        pool.redeem(depositAmount + 1, user2, abi.encode(data), signature);
    }

    function test_revert_NullReceiver() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(ValtzPool.NullReceiver.selector);
        pool.redeem(50 * 1e18, address(0), abi.encode(data), signature);
    }

    function test_revert_InvalidSigner() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);

        // Create a different signer
        Vm.Wallet memory invalidSigner = vm.createWallet("Invalid Signer");

        // Mock the role check to return false for the invalid signer
        vm.mockCall(
            roleAuthority,
            abi.encodeWithSelector(IRoleAuthority.hasRole.selector, VALTZ_SIGNER_ROLE, invalidSigner.addr),
            abi.encode(false)
        );

        ValtzPool.ValidationRedemptionData memory data =
            _createValidationData(address(pool), user1, start, end, bytes20(pool.subnetID()), bytes32(0));

        bytes memory signature = _signValidationData(data, invalidSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.InvalidSigner.selector, invalidSigner.addr));
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }

    function test_revert_InvalidChainId() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);

        ValtzPool.ValidationRedemptionData memory data = ValtzPool.ValidationRedemptionData({
            chainId: block.chainid + 1, // Invalid chain ID
            target: address(pool),
            signedAt: uint40(block.timestamp),
            nodeID: bytes20(pool.subnetID()),
            subnetID: bytes32(0),
            redeemer: user1,
            duration: pool.validatorDuration(),
            start: start,
            end: end
        });

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.InvalidChainId.selector, block.chainid + 1));
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }

    function test_revert_InvalidSignedAt() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);
        uint40 futureTimestamp = uint40(block.timestamp + 1 hours);

        ValtzPool.ValidationRedemptionData memory data = ValtzPool.ValidationRedemptionData({
            chainId: block.chainid,
            target: address(pool),
            signedAt: futureTimestamp, // Future timestamp
            nodeID: bytes20(pool.subnetID()),
            subnetID: bytes32(0),
            redeemer: user1,
            duration: pool.validatorDuration(),
            start: start,
            end: end
        });

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.InvalidSignedAt.selector, futureTimestamp));
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }

    function test_revert_ExpiredSignedAt() public {
        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);
        uint40 oldTimestamp = uint40(block.timestamp - pool.VALTZ_SIGNATURE_TTL() - 1);

        ValtzPool.ValidationRedemptionData memory data = ValtzPool.ValidationRedemptionData({
            chainId: block.chainid,
            target: address(pool),
            signedAt: oldTimestamp,
            nodeID: bytes20(pool.subnetID()),
            subnetID: bytes32(0),
            redeemer: user1,
            duration: pool.validatorDuration(),
            start: start,
            end: end
        });

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ExpiredSignedAt.selector, oldTimestamp));
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }
}
