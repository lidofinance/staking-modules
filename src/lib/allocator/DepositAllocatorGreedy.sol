// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { PackedSortKey, PackedSortKeyLib } from "./PackedSortKeyLib.sol";
import { PackedSortKeyMaxHeapLib } from "./PackedSortKeyMaxHeapLib.sol";

/// @dev Helper struct for input allocation state.
struct AllocationState {
    /// @dev Target share per operator scaled by S_SCALE (X96).
    uint256[] sharesX96;
    /// @dev Current allocated amount per operator.
    uint256[] currents;
    /// @dev Remaining capacity per operator (max allocatable).
    uint256[] capacities;
    /// @dev Sum of current amounts across all operators.
    uint256 totalCurrent;
}

/// @notice Greedy imbalance math with the same entrypoints as DepositPouringMath.
library DepositAllocatorGreedy {
    using PackedSortKeyLib for PackedSortKey;
    using PackedSortKeyMaxHeapLib for PackedSortKey[];

    // Fixed-point scale (2^96) for share ratios to represent fractional shares as integers.
    uint256 internal constant S_SCALE = uint256(1) << 96;

    /// @dev Expected input invariants:
    ///      - state.capacities[i] > 0
    ///      - state.sharesX96[i] > 0
    ///      - step > 0
    ///      - all arrays in state have the same length n, and entries correspond to the same operators across arrays.
    ///      for i in [0..n).
    function _allocate(
        AllocationState memory state,
        uint256 allocationAmount,
        uint256 step
    ) internal pure returns (uint256 allocated, uint256[] memory allocations) {
        uint256 n = state.sharesX96.length;
        allocations = new uint256[](n);

        PackedSortKey[] memory heap = _maxHeapKeysByImbalanceDesc(state, allocationAmount, step);
        uint256 heapSize = heap.length;

        allocationAmount = _quantize(allocationAmount, step);
        uint256 remainder = allocationAmount;

        while (heapSize > 0 && remainder > 0) {
            PackedSortKey key = heap.popMax(heapSize);
            unchecked {
                --heapSize;
            }
            uint256 opIdx = key.unpackIndex();
            uint256 possible = Math.min(key.unpackImbalance(), _quantize(state.capacities[opIdx], step));
            if (possible == 0) continue;

            uint256 toGive = Math.min(possible, remainder);
            allocations[opIdx] = toGive;
            unchecked {
                remainder -= toGive;
            }
        }

        unchecked {
            allocated = allocationAmount - remainder;
        }
    }

    function _quantize(uint256 value, uint256 step) internal pure returns (uint256) {
        if (step < 2 || value == 0) return value;
        unchecked {
            return value - (value % step);
        }
    }

    function _maxHeapKeysByImbalanceDesc(
        AllocationState memory state,
        uint256 allocationAmount,
        uint256 step
    ) internal pure returns (PackedSortKey[] memory heap) {
        uint256 n = state.sharesX96.length;
        heap = new PackedSortKey[](n);
        uint256 targetTotal = state.totalCurrent + allocationAmount;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 imbalance;
                uint256 target = Math.mulDiv(state.sharesX96[i], targetTotal, S_SCALE, Math.Rounding.Ceil);
                uint256 current = state.currents[i];
                if (target > current) {
                    imbalance = _quantize(target - current, step);
                }
                heap[i] = PackedSortKeyLib.pack(imbalance, i);
            }
        }

        heap.heapify();
    }
}
