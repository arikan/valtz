// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

library LibInterval {
    struct Interval {
        uint40 start;
        uint40 term;
    }

    function overlap(Interval memory a, Interval memory b) internal pure returns (bool) {
        if (a.start > b.start) {
            return overlap(b, a);
        }

        // B starts before A ends
        if (b.start < a.start + a.term) {
            return true;
        }

        // A ends after B ends
        if (a.start + a.term > b.start + b.term) {
            return true;
        }

        return false;
    }
}
