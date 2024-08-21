// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract ValidationToken is AccessControl {
    error InvalidAttestationSigner();
    error InvalidAttestationSignature();
    error InvalidAuthorizationSigner();
    error InvalidAuthorizationSignature();
    error UnauthorizedRedeemer();
    error ExpiredAuthorization();

    struct ValidationPeriod {
        uint40 startDate;
        uint40 term;
    }

    struct ValidationData {
        bytes32 validatorID;
        ValidationPeriod period;
    }

    struct ValidationAttestation {
        ValidationData validation;
        bytes signature;
        address signer;
    }

    struct RedemptionAuthorizationData {
        bytes32 subnetID;
        bytes32 validatorID;
        // TODO - what does a p-chain address provide in order to prove validator control/ownership? or can the validator actually perform signatures?
        bytes nodeOwnershipProof;
        address authorizedRedeemer;
        uint40 timestamp;
    }

    struct RedemptionAuthorization {
        RedemptionAuthorizationData data;
        bytes signature;
        address pChainSigner;
    }

    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    mapping(bytes32 => ValidationPeriod[]) public attestedPeriods;

    // function addSigner(address signer) public onlyOwner {
    //     _grantRole(ATTESTOR_ROLE, signer);
    // }

    // function removeSigner(address signer) public onlyOwner {
    //     _revokeRole(ATTESTOR_ROLE, signer);
    // }

    // function setURI(string memory newuri) public onlyOwner {
    //     _setURI(newuri);
    // }

    function mint(
        ValidationAttestation memory attestation,
        RedemptionAuthorization memory authorization
    ) public {
        _checkAttestation(attestation);
        _checkAuthorization(authorization);

        ValidationPeriod[] storage periods = attestedPeriods[attestation.validation.validatorID];
        if (periods.length > 0) {
            ValidationPeriod storage lastPeriod = periods[periods.length - 1];
            if (lastPeriod.startDate + lastPeriod.term > attestation.validation.period.startDate) {
                revert("ValidationAttestation: overlapping period");
            }
        }
        periods.push(attestation.validation.period);
    }

    function _checkValidationPeriod(bytes32 validatorID, ValidationPeriod memory newPeriod)
        internal
        view
    {
        ValidationPeriod[] storage periods = attestedPeriods[validatorID];
        for (uint256 i = 0; i < periods.length; i++) {
            ValidationPeriod storage period = periods[i];
            if (
                newPeriod.startDate > period.startDate
                    && newPeriod.startDate < period.startDate + period.term
            ) {
                revert("ValidationAttestation: overlapping period");
            }
            if (
                newPeriod.startDate + newPeriod.term > period.startDate
                    && newPeriod.startDate + newPeriod.term < period.startDate + period.term
            ) {
                revert("ValidationAttestation: overlapping period");
            }
            if (
                newPeriod.startDate <= period.startDate
                    && newPeriod.startDate + newPeriod.term >= period.startDate + period.term
            ) {
                revert("ValidationAttestation: overlapping period");
            }

            if (period.startDate + period.term > newPeriod.startDate) {
                revert("ValidationAttestation: overlapping period");
            }
        }
        // if (periods.length > 0) {
        //     ValidationPeriod storage lastPeriod = periods[periods.length - 1];
        //     if (lastPeriod.startDate + lastPeriod.term > newPeriod.startDate) {
        //         revert("ValidationAttestation: overlapping period");
        //     }
        // }
    }

    function _checkAttestation(ValidationAttestation memory attestation) internal view {
        if (!hasRole(ATTESTOR_ROLE, attestation.signer)) {
            revert InvalidAttestationSigner();
        }

        bytes32 messageHash = keccak256(abi.encode(attestation.validation));
        if (
            !SignatureChecker.isValidSignatureNow(
                attestation.signer, messageHash, attestation.signature
            )
        ) {
            revert InvalidAttestationSignature();
        }
    }

    function _checkAuthorization(RedemptionAuthorization memory authorization) internal view {
        // TODO!
        // - recover the signer from the signature
        // - check that msg.sender is the authorizedRedeemer
        // - check that the timestamp is within the last X minutes
        // - validate nodeOwnershipProof
        // - check that the signer is the validator's owner (or is the validator?)

        (address recovered, ECDSA.RecoverError err,) =
            ECDSA.tryRecover(keccak256(abi.encode(authorization.data)), authorization.signature);
        if (err != ECDSA.RecoverError.NoError) {
            revert InvalidAuthorizationSignature();
        }
        if (recovered != authorization.pChainSigner) {
            revert InvalidAuthorizationSigner();
        }

        /// TODO - validate authorization.data.nodeOwnershipProof to ensure node owner is the pChain address

        if (authorization.data.authorizedRedeemer != msg.sender) {
            revert UnauthorizedRedeemer();
        }

        if (authorization.data.timestamp + 5 minutes < block.timestamp) {
            revert ExpiredAuthorization();
        }
    }
}
