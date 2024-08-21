// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ValtzPool} from "../src/ValtzPool.sol";
import {Valtz} from "../src/Valtz.sol";
import {IRoleAuthority} from "../src/IRoleAuthority.sol";

contract ValtzDeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ValtzPool impl = new ValtzPool(IRoleAuthority(address(0)));
        new Valtz(msg.sender, address(impl));

        vm.stopBroadcast();
    }
}
