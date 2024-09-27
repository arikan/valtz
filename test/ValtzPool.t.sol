// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../src/ValtzConstants.sol";
import "../src/lib/Interval.sol";
import "../src/lib/DelegatedAuth.sol";
import "../src/lib/AttestedValidation.sol";
import "../src/ValtzPool.sol";
import "../src/interfaces/IRoleAuthority.sol";

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
    Vm.Wallet public pChainNodeRewardSigner;

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
        pChainNodeRewardSigner = vm.createWallet("P-Chain Node Reward Signer");

        token = new MockERC20();

        ValtzPool.PoolConfig memory config = IValtzPool.PoolConfig({
            owner: owner,
            name: "Test Pool",
            symbol: "TPOOL",
            subnetID: bytes32(0),
            poolTerm: 3 * 365 days,
            token: token,
            validatorTerm: 30 days,
            validatorRedeemable: VALIDATOR_REDEEMABLE,
            max: MAX_DEPOSIT,
            boostRate: BOOST_RATE
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

    /// Deposits and withdraws with signed attestations

    function test_deposit() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        assertEq(token.balanceOf(address(pool)), depositAmount + pool.rewardPool());
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(pool.balanceOf(user1), depositAmount);
    }

    function test_redeem() public {
        uint256 depositAmount = 100 * 1e18;
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        uint256 withdrawAmount = 50 * 1e18;

        AttestedValidation.Validation memory validation = _signedValidationAttestation(
            pool,
            bytes32(uint256(123)),
            pChainNodeRewardSigner.addr,
            uint40(block.timestamp),
            uint40(30 days)
        );

        DelegatedAuth.SignedAuth memory auth = _signedAddressAuthorization(
            pool, user1, address(pool), uint40(block.timestamp), uint40(30 days)
        );

        uint256 expectedAmount =
            withdrawAmount + (withdrawAmount * BOOST_RATE / pool.BOOST_RATE_PRECISION());

        vm.prank(user1);
        uint256 redeemedAmount = pool.redeem(withdrawAmount, user1, validation, auth);
        assertEq(redeemedAmount, expectedAmount);

        //     assertEq(token.balanceOf(address(pool)), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount + expectedAmount);
        assertEq(pool.balanceOf(user1), depositAmount - withdrawAmount);
    }

    // TODO - more deposit and withdraw cases

    function _signedValidationAttestation(
        ValtzPool valtzPool,
        bytes32 nodeID,
        address rewardOwner,
        uint40 start,
        uint40 term
    ) internal view returns (AttestedValidation.Validation memory) {
        AttestedValidation.Data memory data = AttestedValidation.Data({
            nodeID: nodeID,
            nodeRewardOwner: rewardOwner,
            interval: LibInterval.Interval({start: start, term: term})
        });

        bytes32 structHash = keccak256(abi.encode(AttestedValidation._TYPEHASH, data));

        bytes32 messageHash =
            MessageHashUtils.toTypedDataHash(valtzPool.DOMAIN_SEPARATOR(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(valtzSigner.privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return AttestedValidation.Validation({
            data: data,
            signature: signature,
            signer: valtzSigner.addr
        });
    }

    function _signedAddressAuthorization(
        ValtzPool valtzPool,
        address authorized,
        address scope,
        uint40 start,
        uint40 term
    ) internal view returns (DelegatedAuth.SignedAuth memory signedAuth) {
        DelegatedAuth.AuthData memory authData =
            DelegatedAuth.AuthData({subject: authorized, scope: scope, start: start, term: term});
        bytes32 structHash = keccak256(abi.encode(DelegatedAuth._TYPEHASH, authData));
        bytes32 messageHash =
            MessageHashUtils.toTypedDataHash(valtzPool.DOMAIN_SEPARATOR(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pChainNodeRewardSigner.privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        signedAuth = DelegatedAuth.SignedAuth({data: authData, signature: signature});
    }

    /// Owner-only

    function test_nonOwnerReverts(address payable user) public {
        vm.assume(user != pool.owner());

        bytes memory unauthorized =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user);

        vm.startPrank(user);
        vm.expectRevert(unauthorized);
        pool.start();

        vm.expectRevert(unauthorized);
        pool.rescueERC20(IERC20(address(0xaa)), user, 1);

        vm.expectRevert(unauthorized);
        pool.rescueNative(user, 1);

        vm.expectRevert(unauthorized);
        pool.rescueERC1155(IERC1155(address(0xaa)), 1, user, 1);

        vm.expectRevert(unauthorized);
        pool.rescueERC721(IERC721(address(0xaa)), 1, user);

        vm.expectRevert(unauthorized);
        pool.rescueERC1155(IERC1155(address(0xaa)), 1, user, 100);

        vm.expectRevert(unauthorized);
        pool.rescueERC721(IERC721(address(0xaa)), 1, user);

        vm.expectRevert(unauthorized);
        pool.rescueNative(user, 1 ether);
    }

    /// Rescue functions

    function test_rescueERC20_primaryToken() public {
        uint256 rescueAmount = 100 * 1e18;

        // Try to rescue the primary token (should fail)
        vm.prank(owner);
        vm.expectRevert("Cannot rescue primary token unless pool is closed");
        pool.rescueERC20(IERC20(address(token)), owner, rescueAmount);

        // Close the pool by advancing time
        vm.warp(pool.startTime() + pool.poolTerm());

        // Store the owner's initial balance
        uint256 ownerInitialBalance = token.balanceOf(owner);

        // Now we should be able to rescue the primary token
        uint256 primaryTokenBalance = token.balanceOf(address(pool));
        vm.prank(owner);
        pool.rescueERC20(IERC20(address(token)), owner, primaryTokenBalance);

        // Check that the primary tokens were transferred to the owner
        assertEq(token.balanceOf(owner), ownerInitialBalance + primaryTokenBalance);
        assertEq(token.balanceOf(address(pool)), 0);
    }

    function test_rescueERC20() public {
        // Deploy a new ERC20 token to rescue
        MockERC20 rescueToken = new MockERC20();

        // Mint some tokens to the pool
        uint256 rescueAmount = 100 * 1e18;
        rescueToken.mint(address(pool), rescueAmount);

        // Rescue the token
        vm.prank(owner);
        pool.rescueERC20(IERC20(address(rescueToken)), owner, rescueAmount);

        // Check that the tokens were transferred to the owner
        assertEq(rescueToken.balanceOf(owner), rescueAmount);
        assertEq(rescueToken.balanceOf(address(pool)), 0);
    }

    function testRescueNative(uint256 amount) public {
        vm.deal(address(pool), amount);

        address payable recipient = payable(address(0x123));
        uint256 recipientInitialBalance = recipient.balance;

        vm.prank(owner);
        pool.rescueNative(recipient, amount);

        assertEq(address(pool).balance, 0);
        assertEq(recipient.balance, recipientInitialBalance + amount);
    }

    function testRescueERC1155() public {
        IERC1155 mockERC1155 = IERC1155(address(0xab));
        uint256 tokenId = 1;
        uint256 amount = 100;
        address recipient = address(0x456);

        bytes memory expectedCall = abi.encodeCall(
            mockERC1155.safeTransferFrom, (address(pool), recipient, tokenId, amount, "")
        );

        vm.prank(owner);

        vm.mockCall(address(mockERC1155), expectedCall, "");
        vm.expectCall(address(mockERC1155), expectedCall);

        pool.rescueERC1155(mockERC1155, tokenId, recipient, amount);
    }

    function testRescueERC721() public {
        IERC721 mockERC721 = IERC721(address(0xcd));
        uint256 tokenId = 42;
        address recipient = address(0x789);

        bytes memory expectedCall = abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256)", address(pool), recipient, tokenId
        );

        vm.prank(owner);

        vm.mockCall(address(mockERC721), expectedCall, "");
        vm.expectCall(address(mockERC721), expectedCall);

        pool.rescueERC721(mockERC721, tokenId, recipient);
    }
}
