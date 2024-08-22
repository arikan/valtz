// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Valtz.sol";
import "../src/ValtzPool.sol";
import "../src/ValtzEvents.sol";
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
            token: IERC20(makeAddr("token")),
            validatorTerm: 30 days,
            validatorRedeemable: 100 * 1e18,
            max: 100 ether,
            boostRate: 100000
        });

        valtz = new Valtz(defaultAdmin, implementation);
    }

    function testConstruction() public view {
        assertNotEq(defaultAdmin, address(0));

        assertTrue(
            valtz.hasRole(valtz.DEFAULT_ADMIN_ROLE(), defaultAdmin),
            "Default admin role should be set"
        );
        assertTrue(
            valtz.poolImplementation() == implementation, "Pool implementation should be set"
        );
    }

    function testDefaultAdminRole() public view {
        assertTrue(
            valtz.hasRole(valtz.DEFAULT_ADMIN_ROLE(), defaultAdmin),
            "Default admin role should be set"
        );
    }

    function testPoolImplementation() public view {
        address poolImpl = valtz.poolImplementation();
        assertTrue(poolImpl != address(0), "Pool implementation should be set");
    }

    function testCreatePool() public {
        vm.expectEmit(false, false, false, false);
        emit CreatePool(0x104fBc016F4bb334D775a19E8A6510109AC63E00);
        address pool = valtz.createPool(poolConfig);
        assertNotEq(pool, address(0), "Pool should be created");
    }

    function testAdminGrantRole() public {
        address user = address(0xab);
        vm.startPrank(defaultAdmin);
        valtz.grantRole(valtz.VALTZ_SIGNER_ROLE(), user);
    }
}
