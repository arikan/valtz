// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./Interval.sol";

library AttestedSubnetOwnership {
// using ECDSA for bytes32;
// using LibInterval for LibInterval.Interval;

// error InvalidAttestationSigner();
// error InvalidAttestationSignature();
// error InvalidAttestationTimeInterval();

// struct SubnetOwnershipData {
//     bytes32 subnetId;
//     address pChainOwner;
//     LibInterval.Interval timing;
// }

// struct SubnetOwnership {
//     SubnetOwnershipData data;
//     bytes signature;
//     address signer;
// }

// bytes32 internal constant _TYPEHASH = keccak256(
//     "SubnetOwnershipData(bytes32 nodeID,address nodeRewardOwner,uint40 start,uint40 term)"
// );

// function _messageHash(SubnetOwnershipData memory data, bytes32 domainSeparator)
//     internal
//     pure
//     returns (bytes32)
// {
//     bytes32 structHash = keccak256(abi.encode(_TYPEHASH, data));
//     return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
// }

// function _assertValidAttestation(Attestation memory attestation, bytes32 domainSeparator)
//     internal
//     view
// {
//     bytes32 hashed = _messageHash(attestation.data, domainSeparator);

//     if (
//         !SignatureChecker.isValidSignatureNow(attestation.signer, hashed, attestation.signature)
//     ) {
//         revert InvalidAttestationSignature();
//     }
//     if (!attestation.data.timing.contains(uint40(block.timestamp))) {
//         revert InvalidAttestationTimeInterval();
//     }
// }
}
