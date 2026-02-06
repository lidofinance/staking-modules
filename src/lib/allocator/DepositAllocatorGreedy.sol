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

    // Expected input invariants:
    // - state.capacities[i] > 0
    // - state.sharesX96[i] > 0
    // for i in [0..n).

    error LengthMismatch();
    error ZeroStep();

    function _allocate(
        AllocationState memory state,
        uint256 allocationAmount,
        uint256 step
    ) internal pure returns (uint256[] memory allocations, uint256 remainder) {
        if (step == 0) {
            revert ZeroStep();
        }
        uint256 n = state.sharesX96.length;
        if (n == 0) {
            return (new uint256[](0), allocationAmount);
        }
        if (state.currents.length != n || state.capacities.length != n) {
            revert LengthMismatch();
        }

        uint256[] memory imbalances = _computeImbalances(
            state,
            allocationAmount,
            step
        );
        allocations = new uint256[](n);

        uint256[] memory idx = _sortedIndicesByImbalanceDesc(imbalances);

        uint256 remaining = allocationAmount;
        unchecked {
            for (uint256 i; i < n && remaining > 0; ++i) {
                uint256 opIdx = idx[i];
                uint256 possible = imbalances[opIdx];
                uint256 cap = state.capacities[opIdx];
                if (possible > cap) {
                    possible = _quantize(cap, step);
                }
                if (possible == 0) continue;

                uint256 toGive = possible < remaining
                    ? possible
                    : _quantize(remaining, step);
                // NOTE: toGive can be 0 if remaining is less than step and possible is greater than remaining.
                //     In this case, there is no point in iterating further.
                if (toGive == 0) break;
                allocations[opIdx] = toGive;
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
        if (n == 0) return idx;
        idx[0] = 0;
        unchecked {
            for (uint256 i = 1; i < n; ++i) {
                uint256 key = i;
                uint256 keyImb = imbalances[key];
                uint256 j = i;
                while (j > 0) {
                    uint256 prev = idx[j - 1];
                    if (imbalances[prev] >= keyImb) break;
                    idx[j] = prev;
                    --j;
                }
                idx[j] = key;
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

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 share = state.sharesX96[i];
                // NOTE: Rounding up to avoid cases when 10 keys aren't allocated over 100 equal operators
                uint256 target = Math.mulDiv(
                    share,
                    targetTotal,
                    S_SCALE,
                    Math.Rounding.Ceil
                );
                uint256 current = state.currents[i];
                if (target <= current) continue;
                imbalances[i] = _quantize(target - current, step);
            }
        }
    }
}
