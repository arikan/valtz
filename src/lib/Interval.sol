// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library LibInterval {
    struct Interval {
        uint40 start;
        uint40 end;
    }

    function contains(Interval memory a, uint40 timestamp) internal pure returns (bool) {
        return a.start <= timestamp && timestamp < a.end;
    }

    function overlap(Interval memory a, Interval memory b) internal pure returns (bool) {
        return (a.start <= b.start && b.start < a.end) || (b.start <= a.start && a.start < b.end);
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
