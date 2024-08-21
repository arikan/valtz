// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

import {VALTZ_SIGNER_ROLE} from "../src/Constants.sol";
import "../src/lib/Interval.sol";
import "../src/ValtzPool.sol";
import "../src/IRoleAuthority.sol";

// Minimal MockERC20 contract
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract ValtzPoolTest is Test {
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
    uint256 constant MAX_REDEMPTION_PER_ATTESTATION = 100 * 1e18;

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
            token: token,
            term: 30 days,
            tokenDepositsMax: MAX_DEPOSIT,
            boostRate: BOOST_RATE,
            maxRedeemablePerValidationAttestation: MAX_REDEMPTION_PER_ATTESTATION
        });
        pool = ValtzPool(Clones.clone(address(new ValtzPool(IRoleAuthority(roleAuthority)))));
        pool.initialize(config);

        vm.mockCall(
            roleAuthority,
            abi.encodeWithSelector(
                IRoleAuthority.hasRole.selector, VALTZ_SIGNER_ROLE, valtzSigner.addr
            ),
            abi.encode(true)
        );

        // pool.grantRole(pool.ATTESTOR_ROLE(), valtzSigner.addr);

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

    function testDeposit() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        assertEq(token.balanceOf(address(pool)), depositAmount + pool.rewardsAmount());
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(pool.balanceOf(user1), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 withdrawAmount = 50 * 1e18;

        IValtzPool.ValidationAttestation memory attestation = _signedValidationAttestation(
            bytes32(uint256(123)), uint40(block.timestamp), uint40(30 days)
        );

        uint256 expectedAmount =
            withdrawAmount + (withdrawAmount * BOOST_RATE / pool.BOOST_RATE_PRECISION());

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user1, attestation);
        assertEq(redeemedAmount, expectedAmount);

        //     assertEq(token.balanceOf(address(pool)), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount + expectedAmount);
        assertEq(pool.balanceOf(user1), depositAmount - withdrawAmount);
    }

    function _signedValidationAttestation(bytes32 validatorID, uint40 start, uint40 term)
        internal
        view
        returns (IValtzPool.ValidationAttestation memory)
    {
        IValtzPool.ValidationData memory validationData = IValtzPool.ValidationData({
            validatorID: validatorID,
            interval: LibInterval.Interval({start: start, term: term})
        });

        bytes32 messageHash = keccak256(abi.encode(validationData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(valtzSigner.privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return IValtzPool.ValidationAttestation({
            validation: validationData,
            signature: signature,
            signer: valtzSigner.addr
        });
    }
}
