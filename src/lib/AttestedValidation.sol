// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./Interval.sol";

library AttestedValidation {
    using ECDSA for bytes32;

    error InvalidAttestationSigner();
    error InvalidAttestationSignature();
    error InactiveAttestation();
    error ExpiredAttestation();
    error InvalidAttestationTimeInterval();

    struct ValidationData {
        bytes32 nodeID;
        address nodeRewardOwner;
        LibInterval.Interval interval;
    }

    struct Validation {
        ValidationData data;
        bytes signature;
        address signer;
    }

    bytes32 internal constant _TYPEHASH =
        keccak256("ValidationData(bytes32 nodeID,address nodeRewardOwner,uint40 start,uint40 term)");

    function _messageHash(ValidationData memory data, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(_TYPEHASH, data));
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    function _assertValidAttestation(Validation memory attestation, bytes32 domainSeparator)
        internal
        view
    {
        bytes32 hashed = _messageHash(attestation.data, domainSeparator);

        if (
            !SignatureChecker.isValidSignatureNow(attestation.signer, hashed, attestation.signature)
        ) {
            revert InvalidAttestationSignature();
        }
        if (attestation.data.interval.start > block.timestamp) {
            revert InvalidAttestationTimeInterval();
        }
    }
}
