// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "../src/ValtzConstants.sol";
import "../src/lib/Interval.sol";
import "../src/ValtzPool.sol";
import "../src/interfaces/IRoleAuthority.sol";

// Minimal MockERC20 contract
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 13;
    }
}

contract ValtzPoolRedeemTest is Test {
    ValtzPool public pool;
    MockERC20 public token;
    address roleAuthority;

    address public owner;
    address public user1;
    address public user2;

    Vm.Wallet public valtzSigner;

    uint256 constant INITIAL_BALANCE = 1000 * 1e18;
    uint256 constant MAX_DEPOSIT = 1000000 * 1e18;
    uint24 constant BOOST_RATE = 1100000; // 110%
    uint256 constant VALIDATOR_REDEEMABLE = 100 * 1e18;

    function setUp() public {
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

        pool.start();
    }

    event ValtzPoolRedeem(
        address indexed redeemer, address indexed receiver, uint256 poolTokenAmount, uint256 tokenAmountWithdrawn
    );

    function test_redeem() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 withdrawAmount = 50 * 1e18;

        // Ensure the interval we submit is in the past
        vm.warp(1000 + pool.validatorDuration() + 200);

        ValtzPool.ValidationRedemptionData memory data = ValtzPool.ValidationRedemptionData({
            chainId: block.chainid,
            target: address(pool),
            signedAt: uint40(block.timestamp),
            nodeID: bytes20(pool.subnetID()),
            subnetID: bytes32(0),
            redeemer: user1,
            duration: pool.validatorDuration(),
            start: 1000,
            end: 1000 + pool.validatorDuration() + 100
        });

        bytes memory encodedData = abi.encode(data);
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(encodedData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(valtzSigner.privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 expectedAmount = withdrawAmount + (withdrawAmount * BOOST_RATE / pool.BOOST_RATE_PRECISION());

        vm.expectEmit(true, true, true, true);
        emit ValtzPoolRedeem(user1, user2, withdrawAmount, expectedAmount);

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user2, encodedData, signature);
        assertEq(redeemedAmount, expectedAmount);

        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(pool.balanceOf(user1), depositAmount - withdrawAmount);

        assertEq(token.balanceOf(user2), INITIAL_BALANCE + expectedAmount);
        assertEq(pool.balanceOf(user2), 0);
    }
}
