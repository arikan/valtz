// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract ValtzValidationAttestation is Ownable2Step, ERC1155Burnable, AccessControl {
    error InvalidSigner();
    error InvalidSignature();

    struct ValidationPeriod {
        uint40 startDate;
        uint40 term;
    }

    struct Validation {
        bytes32 subnetID;
        bytes32 validatorID;
        ValidationPeriod period;
    }

    struct ValidationAttestation {
        Validation claim;
        address signer;
    }

    bytes32 public constant VALIDATION_DATA_SIGNER_ROLE = keccak256("VALIDATION_DATA_SIGNER_ROLE");

    mapping(bytes32 => uint256) public totalSupply;

    mapping(bytes32 => mapping(bytes32 => ValidationPeriod[])) public attestedPeriods;

    constructor() ERC1155("") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(address to, ValidationAttestation memory attestation, bytes memory signature)
        public
    {
        if (!hasRole(VALIDATION_DATA_SIGNER_ROLE, attestation.signer)) {
            revert InvalidSigner();
        }

        bytes32 messageHash = keccak256(abi.encode(attestation.claim));
        if (!SignatureChecker.isValidSignatureNow(attestation.signer, messageHash, signature)) {
            revert InvalidSignature();
        }

        ValidationPeriod[] storage periods =
            attestedPeriods[attestation.claim.subnetID][attestation.claim.validatorID];
        if (periods.length > 0) {
            ValidationPeriod storage lastPeriod = periods[periods.length - 1];
            if (lastPeriod.startDate + lastPeriod.term > attestation.claim.period.startDate) {
                revert("ValidationAttestation: overlapping period");
            }
        }
        periods.push(attestation.claim.period);

        _mint(to, uint256(attestation.claim.subnetID), 1, "");
        totalSupply[attestation.claim.subnetID]++;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
