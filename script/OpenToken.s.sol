// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "../src/OpenToken.sol";

import "forge-std/console2.sol";

contract ValtzDeployScript is Script {
    function setUp() public {}

    function run() public returns (OpenToken token) {
        vm.startBroadcast();

        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");

        if (bytes(name).length == 0 || bytes(symbol).length == 0) {
            revert("Name and symbol must be provided");
        }

        token = new OpenToken(name, symbol);

        vm.stopBroadcast();
    }

    function mint(OpenToken token, address to, uint256 amount) public {
        vm.startBroadcast();
        token.mint(to, amount);
        vm.stopBroadcast();
    }
}
