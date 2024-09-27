// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/lib/DelegatedAuth.sol";

contract DelegatedAuthTestWrapper {
    function assertAuth(
        DelegatedAuth.SignedAuth memory signedAuth,
        address requiredSigner,
        address requiredSubject,
        address requiredScope,
        bytes32 domainSeparator
    ) public view {
        DelegatedAuth._assertAuth(
            signedAuth, requiredSigner, requiredSubject, requiredScope, domainSeparator
        );
    }
}

contract DelegatedAuthTest is Test {
    using DelegatedAuth for DelegatedAuth.SignedAuth;

    Account pChainSigner;
    address cChainAddress;
    bytes32 domainSeparator;
    DelegatedAuth.SignedAuth signedAuth;
    DelegatedAuthTestWrapper wrapper;

    function setUp() public {
        wrapper = new DelegatedAuthTestWrapper();

        pChainSigner = makeAccount("pChainSigner");
        cChainAddress = makeAddr("cChainAddress");

        domainSeparator = keccak256("MockDomainSeparator");

        /// warp ahead so we can go back later
        vm.warp(1 hours);

        DelegatedAuth.AuthData memory authData = DelegatedAuth.AuthData({
            subject: cChainAddress,
            scope: address(this),
            start: uint40(block.timestamp),
            term: uint40(1 hours)
        });
        bytes32 structHash = keccak256(abi.encode(DelegatedAuth._TYPEHASH, authData));
        bytes32 messageHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pChainSigner.key, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        signedAuth = DelegatedAuth.SignedAuth({data: authData, signature: signature});
    }

    function testValidAuth() public view {
        wrapper.assertAuth(
            signedAuth, pChainSigner.addr, cChainAddress, address(this), domainSeparator
        );
    }

    function testInvalidSigner() public {
        Vm.Wallet memory invalidSigner = vm.createWallet("invalid signer");
        vm.expectRevert(DelegatedAuth.InvalidSigner.selector);
        wrapper.assertAuth(
            signedAuth, invalidSigner.addr, cChainAddress, address(this), domainSeparator
        );
    }

    function testInactiveAuth() public {
        vm.warp(block.timestamp - 10);
        vm.expectRevert(DelegatedAuth.InactiveAuth.selector);
        wrapper.assertAuth(
            signedAuth, pChainSigner.addr, cChainAddress, address(this), domainSeparator
        );
    }

    function testExpiredAuth() public {
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(DelegatedAuth.ExpiredAuth.selector);
        wrapper.assertAuth(
            signedAuth, pChainSigner.addr, cChainAddress, address(this), domainSeparator
        );
    }

    function testInvalidAuthScope() public {
        address requiredScope = makeAddr("different required scope");

        vm.expectRevert(DelegatedAuth.InvalidAuthScope.selector);
        wrapper.assertAuth(
            signedAuth, pChainSigner.addr, cChainAddress, requiredScope, domainSeparator
        );
    }

    function testUnauthorizedSender() public {
        address requiredSubject = makeAddr("different required subject");

        vm.expectRevert(DelegatedAuth.UnauthorizedSender.selector);
        wrapper.assertAuth(
            signedAuth, pChainSigner.addr, requiredSubject, address(this), domainSeparator
        );
    }
}
