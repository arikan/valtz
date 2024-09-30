// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../interfaces/IRoleAuthority.sol";
import "./Interval.sol";
import {VALTZ_SIGNER_ROLE} from "../ValtzConstants.sol";

library ValtzAttestation {
    using ECDSA for bytes32;
    using LibInterval for LibInterval.Interval;

    error InvalidAttestationSigner();
    error InvalidAttestationSignature();
    error InvalidAttestationTimeInterval();
    error UnauthorizedSigner();

    struct Scope {
        uint256 chainId;
        address verifyingContract;
        bytes32 salt;
    }

    struct AttestationData {
        LibInterval.Interval timing;
        Scope scope;
        uint256 nonce;
    }

    struct Attestation {
        AttestationData data;
        bytes signature;
        address signer;
    }

    function _assertValidAttestation(Attestation memory attestation, IRoleAuthority roleAuthority)
        internal
        view
    {
        if (!roleAuthority.hasRole(VALTZ_SIGNER_ROLE, attestation.signer)) {
            revert UnauthorizedSigner();
        }
        if (!attestation.data.timing.contains(uint40(block.timestamp))) {
            revert InvalidAttestationTimeInterval();
        }

        bytes32 structHash = keccak256(abi.encode(attestation.data));
        (address recovered, ECDSA.RecoverError error,) =
            ECDSA.tryRecover(structHash, attestation.signature);

        if (error != ECDSA.RecoverError.NoError) {
            revert InvalidAttestationSignature();
        }
        if (recovered != attestation.signer) {
            revert InvalidAttestationSigner();
        }
    }
}
