// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ValtzPool} from "../src/ValtzPool.sol";
import {Valtz} from "../src/Valtz.sol";
import {IRoleAuthority} from "../src/interfaces/IRoleAuthority.sol";

import "forge-std/console2.sol";

contract ValtzDeployScript is Script {
    function setUp() public {}

    function _deployValtz(address owner) private returns (Valtz valtz) {
        address roleAuthorityAddress = vm.computeCreateAddress(msg.sender, vm.getNonce(msg.sender) + 1);
        ValtzPool impl = new ValtzPool(IRoleAuthority(roleAuthorityAddress));
        valtz = new Valtz(owner, address(impl), true);

        if (address(valtz) != roleAuthorityAddress) {
            revert("Address mismatch");
        }
    }

    function run() public returns (Valtz valtz) {
        vm.startBroadcast();
        valtz = _deployValtz(msg.sender);
        vm.stopBroadcast();
    }

    function runWithSigner(address signer) public returns (Valtz valtz) {
        vm.startBroadcast();
        valtz = _deployValtz(msg.sender);
        valtz.grantRole(valtz.VALTZ_SIGNER_ROLE(), signer);
        vm.stopBroadcast();
    }

    function addSigner(Valtz valtz, address signer) public {
        vm.startBroadcast();
        valtz.grantRole(valtz.VALTZ_SIGNER_ROLE(), signer);
        vm.stopBroadcast();
    }

    function revokeSigner(Valtz valtz, address signer) public {
        vm.startBroadcast();
        valtz.revokeRole(valtz.VALTZ_SIGNER_ROLE(), signer);
        vm.stopBroadcast();
    }
}
