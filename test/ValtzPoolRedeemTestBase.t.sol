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

abstract contract ValtzPoolRedeemTestBase is Test {
    ValtzPool public pool;
    MockERC20 public token;
    address roleAuthority;

    address public owner;
    address public user1;
    address public user2;

    Vm.Wallet public valtzSigner;

    // Constants
    uint256 constant INITIAL_BALANCE = 1000 * 1e18;
    uint256 constant MAX_DEPOSIT = 1000000 * 1e18;
    uint24 constant BOOST_RATE = 1100000; // 110%
    uint256 constant VALIDATOR_REDEEMABLE = 100 * 1e18;
    uint40 constant BASE_START = 1000;
    uint40 constant EXTRA_DURATION = 100;

    event ValtzPoolRedeem(
        address indexed redeemer, address indexed receiver, uint256 poolTokenAmount, uint256 tokenAmountWithdrawn
    );

    function setUp() public virtual {
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

    function _createValidationData(
        address target,
        address redeemer,
        uint40 start,
        uint40 end,
        bytes20 nodeID,
        bytes32 subnetID
    ) internal view returns (ValtzPool.ValidationRedemptionData memory) {
        return ValtzPool.ValidationRedemptionData({
            chainId: block.chainid,
            target: target,
            signedAt: uint40(block.timestamp),
            nodeID: nodeID,
            subnetID: subnetID,
            redeemer: redeemer,
            duration: pool.validatorDuration(),
            start: start,
            end: end
        });
    }

    function _signValidationData(ValtzPool.ValidationRedemptionData memory data, uint256 signerKey)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory encodedData = abi.encode(data);
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(encodedData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _setupRedemption(address user, uint256 amount) internal returns (uint40 start, uint40 end) {
        vm.prank(user);
        pool.deposit(amount, user);

        start = BASE_START;
        end = uint40(start + pool.validatorDuration() + EXTRA_DURATION);
        vm.warp(end + EXTRA_DURATION);

        return (start, end);
    }

    function _calculateExpectedAmount(uint256 amount) internal view returns (uint256) {
        return amount + (amount * BOOST_RATE / pool.BOOST_RATE_PRECISION());
    }
}
