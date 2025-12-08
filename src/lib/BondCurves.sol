// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IBondCurve } from "../interfaces/IBondCurve.sol";
import { BondCurve } from "../abstract/BondCurve.sol";

interface IBondCurves {
    error InvalidBondCurveLength();
    error InvalidBondCurveValues();
    error InvalidBondCurveId();
    error InvalidInitializationCurveId();
}

/// Library for managing BondCurves
library BondCurves {
    uint256 public constant MIN_CURVE_LENGTH = 1;
    uint256 public constant MAX_CURVE_LENGTH = 100;

    /// @dev Add a new bond curve to the array
    function addBondCurve(
        BondCurve.BondCurveStorage storage bondCurvesStorage,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) external returns (uint256 curveId) {
        _check(intervals);
        curveId = bondCurvesStorage.bondCurves.length;
        IBondCurve.BondCurveData storage bondCurve = bondCurvesStorage
            .bondCurves
            .push();
        _addIntervals(bondCurve, intervals);
    }

    /// @dev Update existing bond curve
    function updateBondCurve(
        BondCurve.BondCurveStorage storage bondCurvesStorage,
        uint256 curveId,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) external {
        unchecked {
            if (curveId > bondCurvesStorage.bondCurves.length - 1) {
                revert IBondCurve.InvalidBondCurveId();
            }
        }

        _check(intervals);
        delete bondCurvesStorage.bondCurves[curveId];
        _addIntervals(bondCurvesStorage.bondCurves[curveId], intervals);
    }

    function getBondAmountByKeysCount(
        BondCurve.BondCurveStorage storage bondCurvesStorage,
        uint256 keys,
        uint256 curveId
    ) external view returns (uint256) {
        IBondCurve.BondCurveInterval[] storage intervals = bondCurvesStorage
            .bondCurves[curveId]
            .intervals;
        if (keys == 0) {
            return 0;
        }

        unchecked {
            uint256 low = 0;
            uint256 high = intervals.length - 1;
            while (low < high) {
                uint256 mid = (low + high + 1) / 2;
                if (keys < intervals[mid].minKeysCount) {
                    high = mid - 1;
                } else {
                    low = mid;
                }
            }
            IBondCurve.BondCurveInterval storage interval = intervals[low];
            return
                interval.minBond +
                (keys - interval.minKeysCount) *
                interval.trend;
        }
    }

    function getKeysCountByBondAmount(
        BondCurve.BondCurveStorage storage bondCurvesStorage,
        uint256 amount,
        uint256 curveId
    ) external view returns (uint256) {
        IBondCurve.BondCurveInterval[] storage intervals = bondCurvesStorage
            .bondCurves[curveId]
            .intervals;

        // intervals[0].minBond is essentially the amount of bond required for the very first key
        if (amount < intervals[0].minBond) {
            return 0;
        }

        unchecked {
            uint256 low = 0;
            uint256 high = intervals.length - 1;
            while (low < high) {
                uint256 mid = (low + high + 1) / 2;
                if (amount < intervals[mid].minBond) {
                    high = mid - 1;
                } else {
                    low = mid;
                }
            }

            IBondCurve.BondCurveInterval storage interval;

            //
            // Imagine we have:
            //  Interval 0: minKeysCount = 1, minBond = 2 ETH, trend = 2 ETH
            //  Interval 1: minKeysCount = 4, minBond = 9 ETH, trend = 3 ETH (more expensive than Interval 0)
            //  Amount = 8.5 ETH
            // In this case low = 0, and if we count the keys count using data from Interval 0 we will get 4 keys, which is wrong.
            // So we need a special check for bond amounts between Interval 0 maxBond and Interval 1 minBond.
            //
            if (low < intervals.length - 1) {
                interval = intervals[low + 1];
                if (amount > interval.minBond - interval.trend) {
                    return interval.minKeysCount - 1;
                }
            }
            interval = intervals[low];
            return
                interval.minKeysCount +
                (amount - interval.minBond) /
                interval.trend;
        }
    }

    function _addIntervals(
        IBondCurve.BondCurveData storage bondCurve,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) internal {
        IBondCurve.BondCurveInterval storage interval = bondCurve
            .intervals
            .push();

        interval.minKeysCount = intervals[0].minKeysCount;
        interval.trend = intervals[0].trend;
        interval.minBond = intervals[0].trend;

        for (uint256 i = 1; i < intervals.length; ++i) {
            IBondCurve.BondCurveInterval storage prev = interval;
            interval = bondCurve.intervals.push();
            interval.minKeysCount = intervals[i].minKeysCount;
            interval.trend = intervals[i].trend;
            interval.minBond =
                intervals[i].trend +
                prev.minBond +
                (intervals[i].minKeysCount - prev.minKeysCount - 1) *
                prev.trend;
        }
    }

    function _check(
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) internal pure {
        if (
            intervals.length < MIN_CURVE_LENGTH ||
            intervals.length > MAX_CURVE_LENGTH
        ) {
            revert IBondCurves.InvalidBondCurveLength();
        }

        if (intervals[0].minKeysCount != 1) {
            revert IBondCurves.InvalidBondCurveValues();
        }

        if (intervals[0].trend == 0) {
            revert IBondCurves.InvalidBondCurveValues();
        }

        for (uint256 i = 1; i < intervals.length; ++i) {
            unchecked {
                if (
                    intervals[i].minKeysCount <= intervals[i - 1].minKeysCount
                ) {
                    revert IBondCurves.InvalidBondCurveValues();
                }
                if (intervals[i].trend == 0) {
                    revert IBondCurves.InvalidBondCurveValues();
                }
            }
        }
    }
}
