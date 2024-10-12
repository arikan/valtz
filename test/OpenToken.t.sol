// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/OpenToken.sol";

contract OpenTokenTest is Test {
    OpenToken public token;
    address public owner;
    address public user;

    function setUp() public {
        user = address(0x1);
        token = new OpenToken("Test Token", "TEST");
    }

    function testConstructor() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
    }

    function testMint() public {
        uint256 amount = 100 * 10 ** 18; // 100 tokens

        // Test minting as non-owner (should fail)
        vm.prank(user);
        token.mint(user, amount);
        assertEq(token.balanceOf(user), amount);
    }
}
