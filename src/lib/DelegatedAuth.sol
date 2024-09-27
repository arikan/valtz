// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "forge-std/console2.sol";

library DelegatedAuth {
    using ECDSA for bytes32;

    error InvalidSigner();
    error InactiveAuth();
    error ExpiredAuth();
    error InvalidAuthScope();
    error UnauthorizedSender();

    struct AuthData {
        address subject;
        address scope;
        uint40 start;
        uint40 term;
    }

    struct SignedAuth {
        AuthData data;
        bytes signature;
    }

    bytes32 internal constant _TYPEHASH =
        keccak256("AuthData(address subject,address scope,uint40 start,uint40 term)");

    function _messageHash(AuthData memory data, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(_TYPEHASH, data));
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    function _assertAuth(
        SignedAuth memory signedAuth,
        address requiredSigner,
        address requiredSubject,
        address requiredScope,
        bytes32 domainSeparator
    ) internal view {
        bytes32 messageHash = _messageHash(signedAuth.data, domainSeparator);

        if (
            !SignatureChecker.isValidSignatureNow(requiredSigner, messageHash, signedAuth.signature)
        ) {
            revert InvalidSigner();
        }
        if (block.timestamp < signedAuth.data.start) {
            revert InactiveAuth();
        }
        if (block.timestamp >= signedAuth.data.start + signedAuth.data.term) {
            revert ExpiredAuth();
        }
        if (signedAuth.data.scope != requiredScope) {
            revert InvalidAuthScope();
        }
        if (signedAuth.data.subject != requiredSubject) {
            revert UnauthorizedSender();
        }
    }
}
