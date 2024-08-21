// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/lib/Interval.sol";

contract IntervalTest is Test {
    function testOverlappingIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 50);
        LibInterval.Interval memory b = LibInterval.Interval(125, 50);

        assertTrue(LibInterval.overlap(a, b), "Intervals should overlap");
    }

    function testNonOverlappingIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 50);
        LibInterval.Interval memory b = LibInterval.Interval(151, 50);

        assertFalse(LibInterval.overlap(a, b), "Intervals should not overlap");
    }

    function testAdjacentIntervals() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 50);
        LibInterval.Interval memory b = LibInterval.Interval(150, 50);

        assertFalse(
            LibInterval.overlap(a, b), "Adjacent intervals should not be considered overlapping"
        );
    }

    function testContainedInterval() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 100);
        LibInterval.Interval memory b = LibInterval.Interval(125, 50);

        assertTrue(LibInterval.overlap(a, b), "Contained interval should be considered overlapping");
    }

    function testLengthZeroInterval() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 100);
        LibInterval.Interval memory b = LibInterval.Interval(125, 0);

        assertTrue(LibInterval.overlap(a, b), "Length 0 interval still overlaps");
    }

    function testOverlapCommutative() public pure {
        LibInterval.Interval memory a = LibInterval.Interval(100, 50);
        LibInterval.Interval memory b = LibInterval.Interval(125, 50);

        bool overlapAB = LibInterval.overlap(a, b);
        bool overlapBA = LibInterval.overlap(b, a);

        assertTrue(overlapAB == overlapBA, "Overlap should be commutative");
    }
}
