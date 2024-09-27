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
        // Check if either interval starts within the other interval
        return (a.start <= b.start && b.start < a.start + a.term)
            || (b.start <= a.start && a.start < b.start + b.term);
    }

    function contains(Interval memory a, uint40 timestamp) internal pure returns (bool) {
        return a.start <= timestamp && timestamp < a.start + a.term;
    }

    function overlapsAny(Interval memory a, Interval[] memory intervals)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < intervals.length; i++) {
            if (overlap(a, intervals[i])) {
                return true;
            }
        }

        return false;
    }
}
