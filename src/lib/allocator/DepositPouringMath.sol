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

/**
 * @title Deposit Pouring Math
 * @author KRogLA
 * @notice Provides allocation logic for the share-target allocation strategy.
 * @dev This library includes functions for calculating allocation based on 2 approaches of water-filling algorithms.
 * @dev currently unused
 */
library DepositPouringMath {
    // Fixed-point scale (2^96) for share ratios to represent fractional shares as integers.
    uint256 internal constant S_SCALE = uint256(1) << 96;

    error LengthMismatch();
    error ZeroStep();

    struct DemandFillsCache {
        int256[] imbalances; // quantized imbalances versus target shares
        uint256[] imbalancesSortMap; // sorted descending indices of imbalances
        uint256[] capacities; // quantized capacities
        uint256[] fills;
        uint256[] demands;
        uint256[] demandsMap;
        uint256 demandsCount;
    }

    /// @param state The current allocation state
    /// @param inflow The new inflow to allocate
    /// @param step The quantization step for imbalances
    function _allocate(
        AllocationState memory state,
        uint256 inflow,
        uint256 step
    ) internal pure returns (uint256[] memory fills, uint256 rest) {
        if (step == 0) {
            revert ZeroStep();
        }
        uint256 n = state.shares.length;
        if (state.amounts.length != n || state.capacities.length != n) {
            revert LengthMismatch();
        }
        if (n == 0) {
            // no baskets, return full inflow as rest
            return (new uint256[](0), inflow);
        }

        DemandFillsCache memory cache = _prepareCache(state, inflow, step);
        rest = inflow;
        if (rest > 0) {
            _calculateDemands(cache);
            rest = _fulfillDemands(cache, rest, step);
        }
        return (cache.fills, rest);
    }

    /// @notice Prepare cache for allocation
    /// @dev imbalance/capacities values are quantized to `step` multiples
    function _prepareCache(
        AllocationState memory state,
        uint256 inflow,
        uint256 step
    ) internal pure returns (DemandFillsCache memory cache) {
        uint256 n = state.shares.length;

        cache.imbalances = new int256[](n);
        cache.fills = new uint256[](n);

        uint256 totalAmount = state.totalAmount;
        uint256 targetAmount = totalAmount + inflow;
        // reuse input capacities array for quantization
        cache.capacities = state.capacities;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 target = state.shares[i];
                if (target != 0) {
                    target = Math.mulDiv(
                        target,
                        targetAmount,
                        S_SCALE,
                        Math.Rounding.Ceil
                    );
                }
                // get quantized imbalance versus target
                // forge-lint: disable-next-line(unsafe-typecast)
                cache.imbalances[i] = _quantize(
                    int256(target) - int256(state.amounts[i]),
                    step
                );
                // mutate capacities to quantized values
                //    the case here is that we can't allocate less than `step` remaining capacity
                cache.capacities[i] = _quantize(cache.capacities[i], step);
            }
        }
        // sorting imbalances descending
        cache.imbalancesSortMap = _getSortMap(cache.imbalances);
        // preallocate demands helper arrays
        cache.demands = new uint256[](n);
        cache.demandsMap = new uint256[](n);
    }

    function _calculateDemands(DemandFillsCache memory cache) internal pure {
        uint256 demandsCount = 0;

        unchecked {
            for (uint256 i; i < cache.imbalancesSortMap.length; ++i) {
                uint256 idx = cache.imbalancesSortMap[i];
                uint256 capacity = cache.capacities[idx];
                if (capacity == 0) continue;

                uint256 demand;
                // select under-filled only
                int256 imbalance = cache.imbalances[idx];
                if (imbalance > 0) {
                    // forge-lint: disable-next-line(unsafe-typecast)
                    demand = Math.min(uint256(imbalance), capacity);
                }

                // safely ignore zero demands as they won't be included in demandsMap and counted in demandsCount
                if (demand > 0) {
                    cache.demands[idx] = demand;
                    cache.demandsMap[demandsCount] = idx;
                    ++demandsCount;
                }
            }
            cache.demandsCount = demandsCount;
        }
    }

    // @nietice Distribute `amount` across demands in `cache`, modifying `cache.fills`
    // @dev Assumes `cache` is prepared:
    // - `cache.imbalances` filled via `_prepareCache`
    // - `cache.demands` and `cache.demandsMap` are filled and sorted via `_calculateDemands` (i.e. based on  `cache.imbalancesSortMap`)
    function _fulfillDemands(
        DemandFillsCache memory cache,
        uint256 amount,
        uint256 step
    ) internal pure returns (uint256) {
        uint256 demandsCount = cache.demandsCount;
        if (demandsCount == 0) return amount;

        unchecked {
            // initial demand fills count at current level, at least one
            uint256 levelFillsCount = 1;
            // initial("ground") fill level, assume  at least first element present
            int256 currentFillLevel = cache.imbalances[cache.demandsMap[0]];
            uint256 processedCount = 0;
            uint256 delta;
            while (amount > 0 && processedCount < demandsCount) {
                while (levelFillsCount < demandsCount) {
                    int256 nextFillLevel = cache.imbalances[
                        cache.demandsMap[levelFillsCount]
                    ];
                    // fillLevel values should be sorted via demandsMap
                    assert(currentFillLevel >= nextFillLevel);

                    // due to *fillLevel (imbalances) values are quantized, the delta is also quantized
                    // forge-lint: disable-next-line(unsafe-typecast)
                    delta = uint256(currentFillLevel - nextFillLevel);
                    if (delta > 0) {
                        break;
                    }
                    ++levelFillsCount;
                }

                uint256 amountQuant = _quantize(amount / levelFillsCount, step);
                // We cannot reach the next level with current amount, or all demands are at the same level.
                if (delta == 0 || delta > amountQuant) {
                    // compute how many demands can receive at least one step
                    uint256 maxOneStepDemands = amount / step;
                    if (maxOneStepDemands == 0) {
                        break;
                    }
                    // if we cannot give one step to all demands, reduce the number of receivers
                    if (maxOneStepDemands < levelFillsCount) {
                        amountQuant = _quantize(
                            amount / maxOneStepDemands,
                            step
                        );
                    }
                    if (delta > 0) {
                        // update current fill level by amountQuant only if delta was non-zero, i.e. we are below next level
                        currentFillLevel -= int256(amountQuant);
                    }
                    delta = amountQuant;
                } else {
                    // update fill level to next level
                    currentFillLevel -= int256(delta);
                }

                processedCount = 0;

                // need to fill all remaining items at same level, try spread evenly starting from first item
                for (uint256 i = 0; i < levelFillsCount && amount > 0; ++i) {
                    // get original item index
                    uint256 idx = cache.demandsMap[i];
                    // get current demand & filled amount
                    uint256 demand = cache.demands[idx];
                    uint256 filled = cache.fills[idx];
                    // if (demand == 0) continue;

                    if (filled < demand) {
                        // demand and delta are quantized, so fill is also quantized
                        uint256 fill = Math.min(demand - filled, delta);
                        if (fill > amount) {
                            break;
                        }
                        amount -= fill;
                        filled += fill;
                        cache.fills[idx] = filled;
                    }
                    // if element reached capacity and already (over) filled, skip it
                    if (filled >= demand) {
                        ++processedCount;
                    }
                }
            }
        }
        return amount;
    }

    /// HELPERS

    /// @notice quantize int value multiple of step
    function _quantize(
        int256 value,
        uint256 step
    ) internal pure returns (int256) {
        // early return for step=1, or zero value
        if (step == 1 || value == 0) {
            return value;
        }

        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            return value - (value % int256(step));
            // return (value / step) * step;
        }
    }

    /// @notice quantize uint value multiple of step
    function _quantize(
        uint256 value,
        uint256 step
    ) internal pure returns (uint256) {
        return uint256(_quantize(int256(value), step));
    }

    function _getSortMap(
        int256[] memory values
    ) internal pure returns (uint256[] memory sortMap) {
        uint256 count = values.length;
        sortMap = new uint256[](count);

        unchecked {
            uint256 lastPos;
            for (uint256 i; i < count; ++i) {
                int256 value = values[i];
                uint256 pos = lastPos;
                while (pos > 0) {
                    uint256 idx = sortMap[pos - 1];
                    if (values[idx] >= value) break;
                    sortMap[pos] = idx;
                    --pos;
                }
                sortMap[pos] = i;
                ++lastPos;
            }
        }
    }
}
