// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/lib/Interval.sol";

contract IntervalTest is Test {
    function testOverlappingIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);
        LibInterval.Interval memory b = LibInterval.Interval(125, 175);

        assertTrue(LibInterval.overlap(a, b), "Intervals should overlap");
    }

    function testNonOverlappingIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);
        LibInterval.Interval memory b = LibInterval.Interval(151, 200);

        assertFalse(LibInterval.overlap(a, b), "Intervals should not overlap");
    }

    function testAdjacentIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);
        LibInterval.Interval memory b = LibInterval.Interval(150, 200);

        assertFalse(LibInterval.overlap(a, b), "Adjacent intervals should not be considered overlapping");
    }

    function testContainedInterval() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 200);
        LibInterval.Interval memory b = LibInterval.Interval(125, 175);

        assertTrue(LibInterval.overlap(a, b), "Contained interval should be considered overlapping");
    }

    function testLengthZeroInterval() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 200);
        LibInterval.Interval memory b = LibInterval.Interval(125, 125);

        assertTrue(LibInterval.overlap(a, b), "Length 0 interval still overlaps");
    }

    function testOverlapCommutative() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);
        LibInterval.Interval memory b = LibInterval.Interval(125, 175);

        bool overlapAB = LibInterval.overlap(a, b);
        bool overlapBA = LibInterval.overlap(b, a);

        assertTrue(overlapAB == overlapBA, "Overlap should be commutative");
    }

    function testContains() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);

        assertTrue(LibInterval.contains(a, 100), "Should contain start");
        assertTrue(LibInterval.contains(a, 125), "Should contain middle");
        assertTrue(LibInterval.contains(a, 149), "Should contain end");
        assertFalse(LibInterval.contains(a, 99), "Should not contain before start");
        assertFalse(LibInterval.contains(a, 150), "Should not contain at end");
        assertFalse(LibInterval.contains(a, 151), "Should not contain after end");
    }

    function testOverlapsAny() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 150);
        LibInterval.Interval[] memory intervals = new LibInterval.Interval[](3);
        intervals[0] = LibInterval.Interval(50, 75);
        intervals[1] = LibInterval.Interval(200, 225);
        intervals[2] = LibInterval.Interval(125, 175);

        assertTrue(LibInterval.overlapsAny(a, intervals), "Should overlap with at least one interval");

        LibInterval.Interval[] memory noOverlapIntervals = new LibInterval.Interval[](2);
        noOverlapIntervals[0] = LibInterval.Interval(50, 75);
        noOverlapIntervals[1] = LibInterval.Interval(200, 225);

        assertFalse(LibInterval.overlapsAny(a, noOverlapIntervals), "Should not overlap with any interval");
    }
}
