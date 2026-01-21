// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Helper struct for input allocation state.
struct AllocationState {
    /// @dev Target share per operator scaled by S_SCALE.
    uint256[] shares;
    /// @dev Current allocated amount per operator.
    uint256[] amounts;
    /// @dev Remaining capacity per operator (max allocatable).
    uint256[] capacities;
    /// @dev Sum of current amounts across all operators.
    uint256 totalAmount;
}

/// @notice Greedy imbalance math with the same entrypoints as DepositPouringMath.
library DepositAllocatorGreedy {
    // Fixed-point scale (2^96) for share ratios to represent fractional shares as integers.
    uint256 internal constant S_SCALE = uint256(1) << 96;

    error LengthMismatch();
    error ZeroStep();

    function _allocate(
        AllocationState memory state,
        uint256 inflow,
        uint256 step
    ) internal pure returns (uint256[] memory fills, uint256 rest) {
        if (step == 0) {
            revert ZeroStep();
        }
        uint256 n = state.shares.length;
        if (n == 0) {
            return (new uint256[](0), inflow);
        }
        if (state.amounts.length != n || state.capacities.length != n) {
            revert LengthMismatch();
        }

        (
            uint256[] memory imbalances,
            uint256[] memory idx
        ) = _computeImbalances(state, inflow, step);
        fills = new uint256[](n);

        _sortByImbalanceDesc(idx, imbalances);

        uint256 remaining = inflow;
        unchecked {
            for (uint256 i; i < n && remaining > 0; ++i) {
                uint256 opIdx = idx[i];
                uint256 possible = imbalances[opIdx];
                uint256 cap = state.capacities[opIdx];
                if (cap < possible) {
                    possible = cap;
                }
                if (possible == 0) continue;

                uint256 toGive = possible <= remaining ? possible : remaining;
                fills[opIdx] = toGive;
                remaining -= toGive;
            }
        }

        rest = remaining;
    }

    function _quantize(
        uint256 value,
        uint256 step
    ) internal pure returns (uint256) {
        if (step < 2 || value == 0) return value;
        return value - (value % step);
    }

    function _sortByImbalanceDesc(
        uint256[] memory idx,
        uint256[] memory imbalances
    ) internal pure {
        unchecked {
            for (uint256 i = 1; i < idx.length; ++i) {
                uint256 key = idx[i];
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
        uint256 inflow,
        uint256 step
    )
        internal
        pure
        returns (uint256[] memory imbalances, uint256[] memory idx)
    {
        uint256 n = state.shares.length;
        imbalances = new uint256[](n);
        idx = new uint256[](n);

        uint256 targetTotal = state.totalAmount + inflow;

        unchecked {
            for (uint256 i; i < n; ++i) {
                idx[i] = i;
                uint256 capacity = state.capacities[i];
                if (capacity == 0) continue;

                uint256 share = state.shares[i];
                if (share == 0) continue;
                uint256 target = Math.mulDiv(
                    share,
                    targetTotal,
                    S_SCALE,
                    Math.Rounding.Ceil
                );
                uint256 current = state.amounts[i];
                if (target <= current) continue;
                uint256 imbalance = _quantize(target - current, step);
                imbalances[i] = imbalance;
            }
        }
    }
}
