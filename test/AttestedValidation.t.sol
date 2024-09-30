// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/lib/AttestedValidation.sol";

contract AttestedValidationTestWrapper {
    function assertValidAttestation(
        AttestedValidation.Validation memory attestation,
        bytes32 domainSeparator
    ) public view {
        AttestedValidation._assertValidAttestation(attestation, domainSeparator);
    }
}

contract AttestedValidationTest is Test {
    using AttestedValidation for AttestedValidation.Validation;

    Account signer;
    bytes32 nodeID;
    address nodeRewardOwner;
    bytes32 domainSeparator;
    AttestedValidation.Validation attestation;
    AttestedValidationTestWrapper wrapper;

    function setUp() public {
        wrapper = new AttestedValidationTestWrapper();

        signer = makeAccount("signer");
        nodeID = keccak256("mockNodeID");
        nodeRewardOwner = makeAddr("nodeRewardOwner");

        domainSeparator = keccak256("MockDomainSeparator");

        AttestedValidation.ValidationData memory data = AttestedValidation.ValidationData({
            nodeID: nodeID,
            nodeRewardOwner: nodeRewardOwner,
            interval: LibInterval.Interval({start: uint40(block.timestamp), term: uint40(1 hours)})
        });

        bytes32 messageHash = AttestedValidation._messageHash(data, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        attestation =
            AttestedValidation.Validation({data: data, signature: signature, signer: signer.addr});
    }

    function testValidAttestation() public view {
        wrapper.assertValidAttestation(attestation, domainSeparator);
    }

    function testInvalidSigner() public {
        Vm.Wallet memory invalidSigner = vm.createWallet("invalid signer");
        attestation.signer = invalidSigner.addr;

        vm.expectRevert(AttestedValidation.InvalidAttestationSignature.selector);
        wrapper.assertValidAttestation(attestation, domainSeparator);
    }

    function testInvalidSignature() public {
        attestation.signature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        vm.expectRevert(AttestedValidation.InvalidAttestationSignature.selector);
        wrapper.assertValidAttestation(attestation, domainSeparator);
    }

    function testModifiedData() public {
        attestation.data.nodeID = keccak256("differentNodeID");

        vm.expectRevert(AttestedValidation.InvalidAttestationSignature.selector);
        wrapper.assertValidAttestation(attestation, domainSeparator);
    }

    function testDifferentDomainSeparator() public {
        bytes32 differentDomainSeparator = keccak256("DifferentDomainSeparator");

        vm.expectRevert(AttestedValidation.InvalidAttestationSignature.selector);
        wrapper.assertValidAttestation(attestation, differentDomainSeparator);
    }
}
