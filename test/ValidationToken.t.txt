// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ValidationToken.sol";

contract ValidationTokenTest is Test {
    ValidationToken public validationToken;
    address public owner;
    address public user;

    Vm.Wallet public valtzAttestpr;

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        valtzAttestpr = vm.createWallet("attestor");

        validationToken = new ValidationToken();
        validationToken.addSigner(valtzAttestpr.addr);
    }

    function testAddSigner() public {
        address newSigner = address(0x3);
        validationToken.addSigner(newSigner);
        assertTrue(validationToken.hasRole(validationToken.ATTESTOR_ROLE(), newSigner));
    }

    function testRemoveSigner() public {
        validationToken.removeSigner(valtzAttestpr.addr);
        assertFalse(validationToken.hasRole(validationToken.ATTESTOR_ROLE(), valtzAttestpr.addr));
    }

    function testSetURI() public {
        string memory newURI = "https://example.com/token/";
        validationToken.setURI(newURI);
        assertEq(validationToken.uri(0), newURI);
    }

    function testMint() public {
        ValidationToken.ValidationData memory validationData = ValidationToken.ValidationData({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(2)),
            period: ValidationToken.ValidationPeriod({
                startDate: uint40(block.timestamp),
                term: uint40(30 days)
            })
        });

        bytes32 messageHash = keccak256(abi.encode(validationData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(valtzAttestpr.privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        ValidationToken.ValidationAttestation memory attestation = ValidationToken
            .ValidationAttestation({
            validation: validationData,
            signature: signature,
            signer: valtzAttestpr.addr
        });

        // Create a RedemptionAuthorization with dummy sig
        ValidationToken.RedemptionAuthorizationData memory authData = ValidationToken
            .RedemptionAuthorizationData({
            subnetID: bytes32(uint256(1)),
            validatorID: bytes32(uint256(2)),
            nodeOwnershipProof: bytes("proof"),
            authorizedRedeemer: user,
            timestamp: uint40(block.timestamp)
        });

        Vm.Wallet memory pChainSigner = vm.createWallet("pChainSigner");

        bytes32 authMessageHash = keccak256(abi.encode(authData));
        (uint8 authV, bytes32 authR, bytes32 authS) =
            vm.sign(pChainSigner.privateKey, authMessageHash);
        bytes memory authSignature = abi.encodePacked(authR, authS, authV);

        ValidationToken.RedemptionAuthorization memory authorization = ValidationToken
            .RedemptionAuthorization({
            data: authData,
            signature: authSignature,
            pChainSigner: pChainSigner.addr
        });

        vm.prank(user);
        validationToken.mint(user, attestation, authorization);

        assertEq(validationToken.balanceOf(user, uint256(validationData.subnetID)), 1);
        assertEq(validationToken.totalSupply(validationData.subnetID), 1);
    }

    // TODO - cover additional minting scenarios
}
