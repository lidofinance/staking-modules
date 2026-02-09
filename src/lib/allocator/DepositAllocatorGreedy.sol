// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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
    // Fixed-point scale (2^96) for share ratios to represent fractional shares as integers.
    uint256 internal constant S_SCALE = uint256(1) << 96;

    error LengthMismatch();
    error ZeroStep();

    /// @dev Expected input invariants:
    ///      - state.capacities[i] > 0
    ///      - state.sharesX96[i] > 0
    ///      - step > 0
    ///      - state.sharesX96.length > 0
    ///      - all arrays in state have the same length n, and entries correspond to the same operators across arrays.
    ///      for i in [0..n).
    function _allocate(
        AllocationState memory state,
        uint256 allocationAmount,
        uint256 step
    ) internal pure returns (uint256[] memory allocations, uint256 remainder) {
        uint256 n = state.sharesX96.length;
        uint256[] memory imbalances = _computeImbalances(
            state,
            allocationAmount,
            step
        );
        allocations = new uint256[](n);

        uint256[] memory idx = _sortedIndicesByImbalanceDesc(imbalances);

        uint256 remaining = allocationAmount;
        for (uint256 i; i < n && remaining > 0; ++i) {
            uint256 opIdx = idx[i];
            uint256 possible = Math.min(
                imbalances[opIdx],
                _quantize(state.capacities[opIdx], step)
            );
            if (possible == 0) continue;

            uint256 toGive = Math.min(possible, _quantize(remaining, step));
            // NOTE: toGive can be 0 if remaining is less than step and possible is greater than remaining.
            //       In this case, there is no point in iterating further.
            if (toGive == 0) break;

            allocations[opIdx] = toGive;
            unchecked {
                remaining -= toGive;
            }
        }

        remainder = remaining;
    }

    function _quantize(
        uint256 value,
        uint256 step
    ) internal pure returns (uint256) {
        if (step < 2 || value == 0) return value;
        unchecked {
            return value - (value % step);
        }
    }

    function _sortedIndicesByImbalanceDesc(
        uint256[] memory imbalances
    ) internal pure returns (uint256[] memory idx) {
        uint256 n = imbalances.length;
        idx = new uint256[](n);
        unchecked {
            for (uint256 i = 1; i < n; ++i) {
                uint256 keyImb = imbalances[i];
                uint256 j = i;
                while (j > 0) {
                    uint256 prev = idx[j - 1];
                    if (imbalances[prev] >= keyImb) break;
                    idx[j] = prev;
                    --j;
                }
                idx[j] = i;
            }
        }
    }

    function _computeImbalances(
        AllocationState memory state,
        uint256 allocationAmount,
        uint256 step
    ) internal pure returns (uint256[] memory imbalances) {
        uint256 n = state.sharesX96.length;
        imbalances = new uint256[](n);
        uint256 targetTotal = state.totalCurrent + allocationAmount;
        for (uint256 i; i < n; ++i) {
            // NOTE: Rounding up to avoid cases when 10 keys aren't allocated over 100 equal operators
            uint256 target = Math.mulDiv(
                state.sharesX96[i],
                targetTotal,
                S_SCALE,
                Math.Rounding.Ceil
            );
            uint256 current = state.currents[i];
            if (target <= current) continue;
            unchecked {
                imbalances[i] = _quantize(target - current, step);
            }
        }
    }
}
