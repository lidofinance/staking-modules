// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Arrays } from "@openzeppelin/contracts/utils/Arrays.sol";
import { Comparators } from "@openzeppelin/contracts/utils/Comparators.sol";

import { PackedSortKey, PackedSortKeyLib } from "src/lib/allocator/PackedSortKeyLib.sol";
import { PackedSortKeyMaxHeapLib } from "src/lib/allocator/PackedSortKeyMaxHeapLib.sol";

contract PackedSortKeyMaxHeapLibTest is Test {
    using PackedSortKeyLib for PackedSortKey;
    using PackedSortKeyMaxHeapLib for PackedSortKey[];

    function test_heapify_popMax_YieldsDescendingPackedOrder() public pure {
        PackedSortKey[] memory heap = new PackedSortKey[](5);
        heap[0] = PackedSortKeyLib.pack(3 ether, 2);
        heap[1] = PackedSortKeyLib.pack(1 ether, 1);
        heap[2] = PackedSortKeyLib.pack(4 ether, 3);
        heap[3] = PackedSortKeyLib.pack(4 ether, 1);
        heap[4] = PackedSortKeyLib.pack(2 ether, 0);

        PackedSortKey[] memory sorted = new PackedSortKey[](heap.length);
        for (uint256 i; i < heap.length; ++i) {
            sorted[i] = heap[i];
        }
        Arrays.sort(PackedSortKeyLib.asUint256Array(sorted), Comparators.gt);

        heap.heapify();

        for (uint256 i; i < sorted.length; ++i) {
            PackedSortKey key = heap.popMax(heap.length - i);
            assertEq(PackedSortKey.unwrap(key), PackedSortKey.unwrap(sorted[i]));
        }
    }

    function test_popMax_EqualImbalanceLowerIndexWins() public pure {
        PackedSortKey[] memory heap = new PackedSortKey[](3);
        heap[0] = PackedSortKeyLib.pack(7 ether, 2);
        heap[1] = PackedSortKeyLib.pack(7 ether, 0);
        heap[2] = PackedSortKeyLib.pack(7 ether, 1);

        heap.heapify();

        PackedSortKey first = heap.popMax(3);
        PackedSortKey second = heap.popMax(2);
        PackedSortKey third = heap.popMax(1);

        assertEq(first.unpackIndex(), 0);
        assertEq(second.unpackIndex(), 1);
        assertEq(third.unpackIndex(), 2);
    }

    function test_heapify_EmptyAndSingleElementAreNoOps() public pure {
        PackedSortKey[] memory empty = new PackedSortKey[](0);
        empty.heapify();
        assertEq(empty.length, 0);

        PackedSortKey[] memory one = new PackedSortKey[](1);
        one[0] = PackedSortKeyLib.pack(11 ether, 7);
        one.heapify();

        PackedSortKey key = one.popMax(1);
        assertEq(key.unpackImbalance(), 11 ether);
        assertEq(key.unpackIndex(), 7);
    }
}
