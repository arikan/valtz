// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Valtz.sol";
import "../src/ValtzPool.sol";
import "../src/interfaces/IRoleAuthority.sol";
import "../src/lib/DemoMode.sol";

// Minimal pool implementation for testing
contract TestPool is IValtzPool, DemoMode {
    function initialize(PoolConfig memory) external pure {
        revert("Not implemented");
    }

    function initialize(PoolConfig memory, bool _demoMode) external {
        _setDemoMode(_demoMode);
    }
}

contract ValtzTest is Test {
    Valtz public valtz;
    address public defaultAdmin;
    TestPool public implementation;

    IValtzPool.PoolConfig public poolConfig;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        implementation = new TestPool();

        poolConfig = IValtzPool.PoolConfig({
            owner: address(this),
            name: "Test Pool",
            symbol: "TPOOL",
            subnetID: bytes32(0),
            poolTerm: 3 * 365 days,
            token: IERC20Metadata(makeAddr("token")),
            validatorDuration: 30 days,
            validatorRedeemable: 100 * 1e18,
            max: 100 ether,
            boostRate: 100000
        });

        valtz = new Valtz(defaultAdmin, address(implementation), false);
    }

    function testConstruction() public view {
        assertNotEq(defaultAdmin, address(0));

        assertTrue(valtz.hasRole(valtz.DEFAULT_ADMIN_ROLE(), defaultAdmin), "Default admin role should be set");
        assertTrue(valtz.poolImplementation() == address(implementation), "Pool implementation should be set");
    }

    function testDefaultAdminRole() public view {
        assertTrue(valtz.hasRole(valtz.DEFAULT_ADMIN_ROLE(), defaultAdmin), "Default admin role should be set");
    }

    function testPoolImplementation() public view {
        address poolImpl = valtz.poolImplementation();
        assertTrue(poolImpl != address(0), "Pool implementation should be set");
    }

    event CreatePool(address indexed pool, bytes32 indexed subnetId, address indexed creator);

    function testCreatePool() public {
        vm.expectEmit(false, true, true, false);
        emit CreatePool(address(0), poolConfig.subnetID, address(this));
        address pool = valtz.createPool(poolConfig);
        assertNotEq(pool, address(0), "Pool should be created");
    }

    function testPoolRegistry() public {
        // Create pools with different subnet IDs
        bytes32 subnet1 = bytes32(uint256(1));
        bytes32 subnet2 = bytes32(uint256(2));

        poolConfig.subnetID = subnet1;
        address pool1 = valtz.createPool(poolConfig);

        poolConfig.subnetID = subnet1;
        address pool2 = valtz.createPool(poolConfig);

        poolConfig.subnetID = subnet2;
        address pool3 = valtz.createPool(poolConfig);

        // Check pools are registered correctly for subnet1
        assertEq(valtz.poolsBySubnet(subnet1, 0), pool1, "First pool in subnet1 should match");
        assertEq(valtz.poolsBySubnet(subnet1, 1), pool2, "Second pool in subnet1 should match");
        vm.expectRevert(); // Should revert when accessing index 2
        valtz.poolsBySubnet(subnet1, 2);

        // Check pools are registered correctly for subnet2
        assertEq(valtz.poolsBySubnet(subnet2, 0), pool3, "Pool in subnet2 should match");
        vm.expectRevert(); // Should revert when accessing index 1
        valtz.poolsBySubnet(subnet2, 1);

        // Check empty subnet reverts on any access
        vm.expectRevert();
        valtz.poolsBySubnet(bytes32(uint256(999)), 0);
    }

    function testPoolsArray() public {
        // Initially empty array should revert on any access
        vm.expectRevert();
        valtz.pools(0);

        // Create some pools
        address pool1 = valtz.createPool(poolConfig);
        address pool2 = valtz.createPool(poolConfig);

        // Check pools array is updated correctly
        assertEq(valtz.pools(0), pool1, "First pool should match");
        assertEq(valtz.pools(1), pool2, "Second pool should match");
        vm.expectRevert(); // Should revert when accessing index 2
        valtz.pools(2);
    }

    function testPoolCount() public {
        // Initially no pools
        assertEq(valtz.poolCount(), 0, "Initial pool count should be zero");

        // Create some pools
        valtz.createPool(poolConfig);
        assertEq(valtz.poolCount(), 1, "Pool count should be 1 after first creation");

        valtz.createPool(poolConfig);
        assertEq(valtz.poolCount(), 2, "Pool count should be 2 after second creation");

        valtz.createPool(poolConfig);
        assertEq(valtz.poolCount(), 3, "Pool count should be 3 after third creation");
    }

    function testAllPools() public {
        // Initially empty array
        address[] memory initialPools = valtz.allPools();
        assertEq(initialPools.length, 0, "Initial pools array should be empty");

        // Create some pools
        address pool1 = valtz.createPool(poolConfig);
        address pool2 = valtz.createPool(poolConfig);
        address pool3 = valtz.createPool(poolConfig);

        // Get all pools
        address[] memory allPools = valtz.allPools();

        // Check array length
        assertEq(allPools.length, 3, "Should have 3 pools");

        // Check pool addresses match
        assertEq(allPools[0], pool1, "First pool should match");
        assertEq(allPools[1], pool2, "Second pool should match");
        assertEq(allPools[2], pool3, "Third pool should match");
    }

    function testAdminGrantRole() public {
        address user = address(0xab);
        vm.startPrank(defaultAdmin);
        valtz.grantRole(valtz.VALTZ_SIGNER_ROLE(), user);
    }

    function testDemoModeAdmin() public {
        // Only admin should be able to set demo mode
        vm.prank(defaultAdmin);
        valtz.setDemoMode(true);
        assertTrue(valtz.demoMode(), "Demo mode should be enabled");

        // Non-admin should not be able to set demo mode
        address nonAdmin = makeAddr("nonAdmin");
        vm.prank(nonAdmin);
        vm.expectRevert();
        valtz.setDemoMode(false);
    }

    function testPoolInheritsDemoMode() public {
        // Set demo mode on Valtz
        vm.prank(defaultAdmin);
        valtz.setDemoMode(true);

        // Create a pool and verify it inherits demo mode
        address pool = valtz.createPool(poolConfig);
        assertTrue(TestPool(pool).demoMode(), "Pool should inherit demo mode from Valtz");
    }
}
