// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
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

// Mock token that reverts on decimals()
contract RevertingMockERC20 is ERC20 {
    constructor() ERC20("Reverting Mock Token", "RMT") {}

    function decimals() public pure override returns (uint8) {
        revert("decimals() reverted");
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

    function getDefaultConfig() internal view returns (IValtzPool.PoolConfig memory) {
        return IValtzPool.PoolConfig({
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
    }

    function deployPool(IValtzPool.PoolConfig memory config) internal returns (ValtzPool) {
        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));
        newPool.initialize(config);
        return newPool;
    }

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        roleAuthority = address(0xaa);

        valtzSigner = vm.createWallet("Valtz Signer");
        pChainNodeRewardSigner = vm.createWallet("P-Chain Node Reward Signer");

        token = new MockERC20();
        pool = deployPool(getDefaultConfig());

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

    function test_initialization() public {
        ValtzPool newPool = deployPool(getDefaultConfig());

        assertEq(newPool.owner(), owner);
        assertEq(address(newPool.token()), address(token));
        assertEq(newPool.poolTerm(), 3 * 365 days);
        assertEq(newPool.validatorDuration(), 30 days);
        assertEq(newPool.validatorRedeemable(), VALIDATOR_REDEEMABLE);
        assertEq(newPool.max(), MAX_DEPOSIT);
        assertEq(newPool.boostRate(), BOOST_RATE);
    }

    function test_initializeZeroOwner() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.owner = address(0);

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ZeroOwnerAddress.selector));
        newPool.initialize(config);
    }

    function test_initializeZeroToken() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.token = IERC20Metadata(address(0));

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ZeroTokenAddress.selector));
        newPool.initialize(config);
    }

    function test_initializeZeroPoolTerm() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.poolTerm = 0;

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ZeroPoolTerm.selector));
        newPool.initialize(config);
    }

    function test_initializeZeroValidatorDuration() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.validatorDuration = 0;

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ZeroValidatorDuration.selector));
        newPool.initialize(config);
    }

    function test_initializeValidatorRedeemableExceedsMax() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.validatorRedeemable = config.max + 1;

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.ValidatorRedeemableExceedsMax.selector));
        newPool.initialize(config);
    }

    function test_initializeTokenDecimalsError() public {
        IValtzPool.PoolConfig memory config = getDefaultConfig();
        config.token = new RevertingMockERC20();

        ValtzPool implementation = new ValtzPool(IRoleAuthority(roleAuthority));
        ValtzPool newPool = ValtzPool(Clones.clone(address(implementation)));

        vm.expectRevert(abi.encodeWithSelector(ValtzPool.TokenDecimalsError.selector));
        newPool.initialize(config);
    }

    function test_poolDecimals() public view {
        assertEq(pool.decimals(), token.decimals(), "Pool decimals should match token decimals");
    }

    event ValtzPoolDeposit(address indexed depositor, address indexed receiver, uint256 amount);

    function test_deposit() public {
        uint256 depositAmount = 100 * 1e18;

        vm.expectEmit(true, true, true, true);
        emit ValtzPoolDeposit(user1, user1, depositAmount);
        vm.prank(user1);
        pool.deposit(depositAmount, user1);

        assertEq(token.balanceOf(address(pool)), depositAmount + pool.rewardPool());
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - depositAmount);
        assertEq(pool.balanceOf(user1), depositAmount);
    }

    function test_nonOwnerReverts(address payable user) public {
        vm.assume(user != pool.owner());

        bytes memory unauthorized = "Ownable: caller is not the owner";

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
    }

    function test_rescueERC20_primaryToken() public {
        uint256 rescueAmount = 100 * 1e18;

        // Try to rescue the primary token (should fail)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.CannotRescuePrimaryToken.selector));
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

        bytes memory expectedCall =
            abi.encodeCall(mockERC1155.safeTransferFrom, (address(pool), recipient, tokenId, amount, ""));

        vm.prank(owner);

        vm.mockCall(address(mockERC1155), expectedCall, "");
        vm.expectCall(address(mockERC1155), expectedCall);

        pool.rescueERC1155(mockERC1155, tokenId, recipient, amount);
    }

    function testRescueERC721() public {
        IERC721 mockERC721 = IERC721(address(0xcd));
        uint256 tokenId = 42;
        address recipient = address(0x789);

        bytes memory expectedCall =
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(pool), recipient, tokenId);

        vm.prank(owner);

        vm.mockCall(address(mockERC721), expectedCall, "");
        vm.expectCall(address(mockERC721), expectedCall);

        pool.rescueERC721(mockERC721, tokenId, recipient);
    }

    function test_setDemoMode() public {
        // Test demo mode on allowed test networks
        uint256[] memory allowedChains = new uint256[](3);
        allowedChains[0] = FUJI_CHAIN_ID;
        allowedChains[1] = HARDHAT_CHAIN_ID;
        allowedChains[2] = GANACHE_CHAIN_ID;

        for (uint256 i = 0; i < allowedChains.length; i++) {
            vm.chainId(allowedChains[i]);
            pool.setDemoMode(true);
            assertTrue(pool.demoMode());
            pool.setDemoMode(false);
            assertFalse(pool.demoMode());
        }

        // Reverts on mainnet
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(ValtzPool.DemoModeNotAllowed.selector));
        pool.setDemoMode(true);
    }
}
