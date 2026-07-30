// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { PackedSortKey } from "./PackedSortKeyLib.sol";

/// @notice In-place max-heap helpers for `PackedSortKey[]`.
/// @dev This is a memory-only priority queue primitive specialized for `PackedSortKey`.
///      `PackedSortKey` already encodes the full descending order as a single `uint256`,
///      so heap operations only need plain key comparisons to preserve both priority and tie-break rules.
///
///      A heap is represented as a flat array, but interpreted as a binary tree:
///      - node `i`
///      - left child `2 * i + 1`
///      - right child `2 * i + 2`
///      - parent `(i - 1) / 2`
///
///      Example array:
///      `[9, 5, 7, 1, 2]`
///
///      Tree view:
///      ```text
///              9(0)
///            /      \
///         5(1)      7(2)
///         /  \
///      1(3)  2(4)
///      ```
///
///      Heap property:
///      every parent is greater than or equal to its children.
///      This guarantees that the maximum key is always at index `0`.
///
///      `heapify` does not fully sort the array. It only rearranges it enough so that
///      repeated `popMax` calls return keys in descending order.
///
///      Expected complexity:
///      - `heapify`: O(n)
///      - `popMax`: O(log n)
///      - repeated extraction of `m` elements after `heapify`: O(n + m log n)
library PackedSortKeyMaxHeapLib {
    /// @notice Reorders keys in place into a max-heap.
    /// @dev This is the standard bottom-up heap construction:
    ///      start from the last internal node and repeatedly sift it down until
    ///      every subtree satisfies the heap property.
    ///
    ///      Example:
    ///      `[2, 9, 7, 1, 5]`
    ///
    ///      becomes a valid max-heap such as:
    ///      `[9, 5, 7, 1, 2]`
    ///
    ///      Note that the result is not fully sorted. The only guarantee is that
    ///      the largest key is at the root and every subtree is itself a valid heap.
    /// @param heap Array to reinterpret as a max-heap.
    function heapify(PackedSortKey[] memory heap) internal pure {
        uint256 n = heap.length;
        if (n < 2) return;

        unchecked {
            for (uint256 i = n / 2; i > 0; --i) {
                _siftDown(heap, i - 1, n);
            }
        }
    }

    /// @notice Removes and returns the maximum key from a max-heap prefix.
    /// @dev The heap is assumed to occupy `heap[0:heapSize)`.
    ///      The operation is:
    ///      1. take the root at `heap[0]`
    ///      2. move the last active element to the root
    ///      3. sift the new root down until the heap property is restored
    ///
    ///      Example:
    ///      active heap `[9, 5, 7, 1, 2]`
    ///      - returned key: `9`
    ///      - move `2` to root -> `[2, 5, 7, 1, 2]`
    ///      - sift down -> `[7, 5, 2, 1, 2]`
    ///
    ///      After the call, callers are expected to shrink the active heap by one,
    ///      e.g. by decrementing `heapSize`.
    /// @param heap Heap array.
    /// @param heapSize Current heap size.
    /// @return key Maximum key at the heap root.
    function popMax(PackedSortKey[] memory heap, uint256 heapSize) internal pure returns (PackedSortKey key) {
        key = heap[0];
        if (heapSize < 2) return key;

        unchecked {
            heap[0] = heap[heapSize - 1];
            _siftDown(heap, 0, heapSize - 1);
        }
    }

    /// @dev Restores the heap property starting at `root` and moving toward the leaves.
    ///      The active heap occupies `heap[0:heapSize)`.
    ///
    ///      At each step:
    ///      - compare the current node with its children
    ///      - swap with the larger child if needed
    ///      - continue from the child's position
    ///
    ///      Example:
    ///      if the current subtree is:
    ///      ```text
    ///          2
    ///         / \
    ///        9   7
    ///      ```
    ///      then `2` is swapped with `9`, because the parent must stay greater than
    ///      both children in a max-heap.
    function _siftDown(PackedSortKey[] memory heap, uint256 root, uint256 heapSize) private pure {
        unchecked {
            while (true) {
                uint256 left = 2 * root + 1;
                if (left >= heapSize) return;

                uint256 best = root;
                if (_gt(heap[left], heap[best])) best = left;

                uint256 right = left + 1;
                if (right < heapSize && _gt(heap[right], heap[best])) best = right;
                if (best == root) return;

                PackedSortKey tmp = heap[root];
                heap[root] = heap[best];
                heap[best] = tmp;
                root = best;
            }
        }
    }

    function _gt(PackedSortKey lhs, PackedSortKey rhs) private pure returns (bool) {
        return PackedSortKey.unwrap(lhs) > PackedSortKey.unwrap(rhs);
    }
}
