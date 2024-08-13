// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ValtzValidationAttestation.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract ValtzValidationAttestationTest is Test {
    ValtzValidationAttestation private attestation;
    address private owner;
    uint256 private signerPrivateKey;
    address private signer;
    address private user;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        Vm.Wallet memory wallet = vm.createWallet("signer");
        signer = wallet.addr;
        signerPrivateKey = wallet.privateKey;

        attestation = new ValtzValidationAttestation();
        attestation.grantRole(attestation.VALIDATION_DATA_SIGNER_ROLE(), signer);
    }

    function testMint() public {
        ValtzValidationAttestation.ValidationClaim memory claim = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation =
            ValtzValidationAttestation.ValidationAttestation({claim: claim, signer: signer});

        bytes32 messageHash = keccak256(abi.encode(claim));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        attestation.mint(user, validationAttestation, signature);

        assertEq(attestation.balanceOf(user, 1), 1);
        assertEq(attestation.totalSupply(bytes32(uint256(1))), 1);
    }

    function testFailMintInvalidSigner() public {
        address invalidSigner = makeAddr("invalidSigner");

        ValtzValidationAttestation.ValidationClaim memory claim = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation =
            ValtzValidationAttestation.ValidationAttestation({claim: claim, signer: invalidSigner});

        bytes32 messageHash = keccak256(abi.encode(claim));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(invalidSigner)), messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        attestation.mint(user, validationAttestation, signature);
    }

    function testFailMintInvalidSignature() public {
        ValtzValidationAttestation.ValidationClaim memory claim = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation =
            ValtzValidationAttestation.ValidationAttestation({claim: claim, signer: signer});

        bytes memory invalidSignature = new bytes(65);

        attestation.mint(user, validationAttestation, invalidSignature);
    }

    function testFailMintOverlappingPeriod() public {
        ValtzValidationAttestation.ValidationClaim memory claim1 = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation1 =
            ValtzValidationAttestation.ValidationAttestation({claim: claim1, signer: signer});

        bytes32 messageHash1 = keccak256(abi.encode(claim1));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPrivateKey, messageHash1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        attestation.mint(user, validationAttestation1, signature1);

        ValtzValidationAttestation.ValidationClaim memory claim2 = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp + 180 days),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation2 =
            ValtzValidationAttestation.ValidationAttestation({claim: claim2, signer: signer});

        bytes32 messageHash2 = keccak256(abi.encode(claim2));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPrivateKey, messageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        attestation.mint(user, validationAttestation2, signature2);
    }

    function testSetURI() public {
        string memory newURI = "https://example.com/token/";
        vm.prank(owner);
        attestation.setURI(newURI);
        assertEq(attestation.uri(0), newURI);
    }

    function testFailSetURINotOwner() public {
        string memory newURI = "https://example.com/token/";
        vm.prank(user);
        attestation.setURI(newURI);
    }

    function testGrantRole() public {
        address newSigner = makeAddr("newSigner");
        vm.prank(owner);
        attestation.grantRole(attestation.VALIDATION_DATA_SIGNER_ROLE(), newSigner);
        assertTrue(attestation.hasRole(attestation.VALIDATION_DATA_SIGNER_ROLE(), newSigner));
    }

    function testRevokeRole() public {
        vm.prank(owner);
        attestation.revokeRole(attestation.VALIDATION_DATA_SIGNER_ROLE(), signer);
        assertFalse(attestation.hasRole(attestation.VALIDATION_DATA_SIGNER_ROLE(), signer));
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        attestation.transferOwnership(newOwner);
        vm.prank(newOwner);
        attestation.acceptOwnership();
        assertEq(attestation.owner(), newOwner);
    }

    function testMintNonOverlappingPeriods() public {
        // First attestation
        ValtzValidationAttestation.ValidationClaim memory claim1 = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation1 =
            ValtzValidationAttestation.ValidationAttestation({claim: claim1, signer: signer});

        bytes32 messageHash1 = keccak256(abi.encode(claim1));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPrivateKey, messageHash1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        attestation.mint(user, validationAttestation1, signature1);

        // Second non-overlapping attestation
        ValtzValidationAttestation.ValidationClaim memory claim2 = ValtzValidationAttestation
            .ValidationClaim({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(1)),
            period: ValtzValidationAttestation.ValidationPeriod({
                startDate: uint40(block.timestamp + 366 days),
                term: uint40(365 days)
            })
        });

        ValtzValidationAttestation.ValidationAttestation memory validationAttestation2 =
            ValtzValidationAttestation.ValidationAttestation({claim: claim2, signer: signer});

        bytes32 messageHash2 = keccak256(abi.encode(claim2));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPrivateKey, messageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        attestation.mint(user, validationAttestation2, signature2);

        assertEq(attestation.balanceOf(user, 1), 2);
        assertEq(attestation.totalSupply(bytes32(uint256(1))), 2);
    }

    function testSupportsInterface() public view {
        assertTrue(attestation.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(attestation.supportsInterface(type(IAccessControl).interfaceId));
    }
}
