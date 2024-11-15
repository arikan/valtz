// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Valtz.sol";
import "../src/ValtzPool.sol";
import "../src/interfaces/IRoleAuthority.sol";

contract ValtzTest is Test {
    Valtz public valtz;
    address public defaultAdmin;
    address public implementation;

    IValtzPool.PoolConfig public poolConfig;

    function setUp() public {
        defaultAdmin = makeAddr("defaultAdmin");
        implementation = makeAddr("implementation");

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

        valtz = new Valtz(defaultAdmin, implementation);
    }

    function testConstruction() public view {
        assertNotEq(defaultAdmin, address(0));

        assertTrue(valtz.hasRole(valtz.DEFAULT_ADMIN_ROLE(), defaultAdmin), "Default admin role should be set");
        assertTrue(valtz.poolImplementation() == implementation, "Pool implementation should be set");
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
        vm.expectEmit(true, true, true, false);
        emit CreatePool(0x104fBc016F4bb334D775a19E8A6510109AC63E00, poolConfig.subnetID, address(this));
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

    function testAdminGrantRole() public {
        address user = address(0xab);
        vm.startPrank(defaultAdmin);
        valtz.grantRole(valtz.VALTZ_SIGNER_ROLE(), user);
    }
}
