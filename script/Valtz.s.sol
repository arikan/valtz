// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ValtzPool} from "../src/ValtzPool.sol";
import {Valtz} from "../src/Valtz.sol";
import {IRoleAuthority} from "../src/interfaces/IRoleAuthority.sol";

import "forge-std/console2.sol";

contract ValtzDeployScript is Script {
    function setUp() public {}

    function run() public returns (Valtz valtz) {
        vm.startBroadcast();

        address roleAuthorityAddress = vm.computeCreateAddress(msg.sender, vm.getNonce(msg.sender) + 1);

        ValtzPool impl = new ValtzPool(IRoleAuthority(roleAuthorityAddress));

        valtz = new Valtz(msg.sender, address(impl));

        if (address(valtz) != roleAuthorityAddress) {
            revert("Address mismatch");
        }

        vm.stopBroadcast();
    }
}
