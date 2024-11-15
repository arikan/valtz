// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ValtzPoolRedeemTestBase.t.sol";

contract ValtzPoolRedeemIntervalsTest is ValtzPoolRedeemTestBase {
    function setUp() public override {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        roleAuthority = address(0xaa);

        valtzSigner = vm.createWallet("Valtz Signer");

        token = new MockERC20();

        ValtzPool.PoolConfig memory config = IValtzPool.PoolConfig({
            owner: owner,
            name: "Test Pool",
            symbol: "TPOOL",
            subnetID: bytes32(0),
            poolTerm: 3 * 365 days,
            token: token,
            validatorDuration: 30 days,
            validatorRedeemable: VALIDATOR_REDEEMABLE,
            max: MAX_DEPOSIT,
            boostRate: BOOST_RATE
        });
        pool = ValtzPool(Clones.clone(address(new ValtzPool(IRoleAuthority(roleAuthority)))));
        pool.initialize(config);

        vm.mockCall(
            roleAuthority,
            abi.encodeWithSelector(IRoleAuthority.hasRole.selector, VALTZ_SIGNER_ROLE, valtzSigner.addr),
            abi.encode(true)
        );

        // Mint initial balances
        token.mint(address(this), 100000000 ether);
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);

        // Approve pool to spend tokens
        vm.prank(address(this));
        token.approve(address(pool), type(uint256).max);
        vm.prank(user1);
        token.approve(address(pool), type(uint256).max);
        vm.prank(user2);
        token.approve(address(pool), type(uint256).max);

        // Don't start the pool here - we'll do it in each test
    }

    function test_revert_IntervalContainsPoolStart() public {
        // Set up initial state
        vm.warp(1000);

        // Start the pool at timestamp 1000
        pool.startAt(1000);

        // Set up redemption
        vm.prank(user1);
        pool.deposit(100 * 1e18, user1);

        // Create validation data with interval containing pool start
        ValtzPool.ValidationRedemptionData memory data = _createValidationData(
            address(pool),
            user1,
            950, // Start before pool start (1000)
            1050, // End after pool start (1000)
            bytes20(pool.subnetID()),
            bytes32(0)
        );

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(ValtzPool.IntervalContainsPoolStart.selector);
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }

    function test_revert_IntervalEndsInFuture() public {
        // Start the pool before setting up redemption
        pool.start();

        (uint40 start,) = _setupRedemption(user1, 100 * 1e18);

        ValtzPool.ValidationRedemptionData memory data = _createValidationData(
            address(pool),
            user1,
            start,
            uint40(block.timestamp) + 100, // End in future
            bytes20(pool.subnetID()),
            bytes32(0)
        );

        bytes memory signature = _signValidationData(data, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(ValtzPool.IntervalEndsInFuture.selector);
        pool.redeem(50 * 1e18, user2, abi.encode(data), signature);
    }

    function test_revert_IntervalOverlap() public {
        // Start the pool before setting up redemption
        pool.start();

        (uint40 start, uint40 end) = _setupRedemption(user1, 100 * 1e18);

        bytes20 nodeID = bytes20(pool.subnetID());

        // First redemption
        ValtzPool.ValidationRedemptionData memory data1 =
            _createValidationData(address(pool), user1, start, end, nodeID, bytes32(0));

        bytes memory signature1 = _signValidationData(data1, valtzSigner.privateKey);

        vm.prank(user1);
        pool.redeem(25 * 1e18, user2, abi.encode(data1), signature1);

        // Second redemption with overlapping interval
        ValtzPool.ValidationRedemptionData memory data2 = _createValidationData(
            address(pool),
            user1,
            start + 50, // Overlaps with first interval
            end + 50,
            nodeID,
            bytes32(0)
        );

        bytes memory signature2 = _signValidationData(data2, valtzSigner.privateKey);

        vm.prank(user1);
        vm.expectRevert(ValtzPool.IntervalOverlap.selector);
        pool.redeem(25 * 1e18, user2, abi.encode(data2), signature2);
    }

    function test_redeem_MultipleValidRedemptions() public {
        // Start the pool before setting up redemption
        pool.start();

        (uint40 start, uint40 end) = _setupRedemption(user1, VALIDATOR_REDEEMABLE * 2);

        bytes20 nodeID = bytes20(pool.subnetID());

        // First redemption
        ValtzPool.ValidationRedemptionData memory data1 =
            _createValidationData(address(pool), user1, start, end, nodeID, bytes32(0));

        bytes memory signature1 = _signValidationData(data1, valtzSigner.privateKey);

        vm.prank(user1);
        pool.redeem(VALIDATOR_REDEEMABLE / 2, user2, abi.encode(data1), signature1);

        // Second redemption with non-overlapping interval
        uint40 start2 = end + 1;
        uint40 end2 = uint40(start2 + pool.validatorDuration() + EXTRA_DURATION);
        vm.warp(end2 + EXTRA_DURATION);

        ValtzPool.ValidationRedemptionData memory data2 =
            _createValidationData(address(pool), user1, start2, end2, nodeID, bytes32(0));

        bytes memory signature2 = _signValidationData(data2, valtzSigner.privateKey);

        vm.prank(user1);
        pool.redeem(VALIDATOR_REDEEMABLE / 2, user2, abi.encode(data2), signature2);

        // Verify intervals are stored correctly
        LibInterval.Interval[] memory intervals = pool.validatorIntervals(nodeID);
        assertEq(intervals.length, 2);
        assertEq(intervals[0].start, start);
        assertEq(intervals[0].end, end);
        assertEq(intervals[1].start, start2);
        assertEq(intervals[1].end, end2);
    }
}
