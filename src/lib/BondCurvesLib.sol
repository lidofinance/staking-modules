// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { IBondCurve } from "../interfaces/IBondCurve.sol";
import { BondCurve } from "../abstract/BondCurve.sol";
import { MAX_BP } from "../lib/Constants.sol";

/// Library for managing BondCurves
/// @dev External deployment-linked library used by Accounting.
library BondCurvesLib {
    uint256 public constant MIN_CURVE_LENGTH = 1;
    uint256 public constant MAX_CURVE_LENGTH = 100;

    /// @dev Add a new bond curve to the array
    function addBondCurve(
        BondCurve.BondCurveStorage storage bondCurveStorage,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) external returns (uint256 curveId) {
        _check(intervals);
        curveId = bondCurveStorage.bondCurves.length;
        IBondCurve.BondCurveData storage bondCurve = bondCurveStorage.bondCurves.push();
        _addIntervals(bondCurve, intervals);
    }

    /// @dev Update existing bond curve
    function updateBondCurve(
        BondCurve.BondCurveStorage storage bondCurveStorage,
        uint256 curveId,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) external {
        _ensureCurveExists(bondCurveStorage, curveId);
        _check(intervals);
        delete bondCurveStorage.bondCurves[curveId];
        _addIntervals(bondCurveStorage.bondCurves[curveId], intervals);
    }

    function getBondAmountByKeysCount(
        BondCurve.BondCurveStorage storage bondCurveStorage,
        uint256 keys,
        uint256 curveId,
        uint256 multiplier
    ) external view returns (uint256) {
        if (multiplier < MAX_BP) revert IBondCurve.InvalidMultiplier();
        _ensureCurveExists(bondCurveStorage, curveId);
        IBondCurve.BondCurveInterval[] memory intervals = _scaleCurve(
            bondCurveStorage.bondCurves[curveId].intervals,
            multiplier
        );
        if (keys == 0) return 0;

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
            return intervals[low].minBond + (keys - intervals[low].minKeysCount) * intervals[low].trend;
        }
    }

    function getKeysCountByBondAmount(
        BondCurve.BondCurveStorage storage bondCurveStorage,
        uint256 amount,
        uint256 curveId,
        uint256 multiplier
    ) external view returns (uint256) {
        if (multiplier < MAX_BP) revert IBondCurve.InvalidMultiplier();
        _ensureCurveExists(bondCurveStorage, curveId);
        IBondCurve.BondCurveInterval[] memory intervals = _scaleCurve(
            bondCurveStorage.bondCurves[curveId].intervals,
            multiplier
        );

        unchecked {
            if (amount < intervals[0].minBond) return 0;

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

            //
            // Imagine we have:
            //  Interval 0: minKeysCount = 1, minBond = 2 ETH, trend = 2 ETH
            //  Interval 1: minKeysCount = 4, minBond = 9 ETH, trend = 3 ETH (more expensive than Interval 0)
            //  Amount = 8.5 ETH
            // In this case low = 0, and if we count the keys count using data from Interval 0 we will get 4 keys, which is wrong.
            // So we need a special check for bond amounts between Interval 0 maxBond and Interval 1 minBond.
            //
            if (low < intervals.length - 1) {
                if (amount > intervals[low + 1].minBond - intervals[low + 1].trend)
                    return intervals[low + 1].minKeysCount - 1;
            }
            return intervals[low].minKeysCount + (amount - intervals[low].minBond) / intervals[low].trend;
        }
    }

    function _addIntervals(
        IBondCurve.BondCurveData storage bondCurve,
        IBondCurve.BondCurveIntervalInput[] calldata intervals
    ) internal {
        IBondCurve.BondCurveInterval storage interval = bondCurve.intervals.push();

        interval.minKeysCount = intervals[0].minKeysCount;
        interval.trend = intervals[0].trend;
        interval.minBond = intervals[0].trend;

        for (uint256 i = 1; i < intervals.length; ++i) {
            IBondCurve.BondCurveInterval storage prev = interval;
            uint256 currMinKeysCount = intervals[i].minKeysCount;
            uint256 currTrend = intervals[i].trend;

            interval = bondCurve.intervals.push();
            interval.minKeysCount = currMinKeysCount;
            interval.trend = currTrend;
            interval.minBond = prev.minBond + currTrend + (currMinKeysCount - prev.minKeysCount - 1) * prev.trend;
        }
    }

    function _scaleCurve(
        IBondCurve.BondCurveInterval[] storage src,
        uint256 multiplier
    ) private view returns (IBondCurve.BondCurveInterval[] memory scaled) {
        uint256 len = src.length;
        scaled = new IBondCurve.BondCurveInterval[](len);

        uint256 sTrend = (src[0].trend * multiplier) / MAX_BP;
        scaled[0].minKeysCount = src[0].minKeysCount;
        scaled[0].trend = sTrend;
        scaled[0].minBond = sTrend;

        for (uint256 i = 1; i < len; ++i) {
            IBondCurve.BondCurveInterval memory prev = scaled[i - 1];
            uint256 currMinKeysCount = src[i].minKeysCount;
            uint256 currTrend = (src[i].trend * multiplier) / MAX_BP;

            scaled[i].minKeysCount = currMinKeysCount;
            scaled[i].trend = currTrend;
            scaled[i].minBond = prev.minBond + currTrend + (currMinKeysCount - prev.minKeysCount - 1) * prev.trend;
        }
    }

    function _ensureCurveExists(BondCurve.BondCurveStorage storage bondCurveStorage, uint256 curveId) internal view {
        unchecked {
            if (curveId > bondCurveStorage.bondCurves.length - 1) revert IBondCurve.InvalidBondCurveId();
        }
    }

    function _check(IBondCurve.BondCurveIntervalInput[] calldata intervals) internal pure {
        if (intervals.length < MIN_CURVE_LENGTH || intervals.length > MAX_CURVE_LENGTH) {
            revert IBondCurve.InvalidBondCurveLength();
        }
        if (intervals[0].minKeysCount != 1) revert IBondCurve.InvalidBondCurveValues();
        if (intervals[0].trend == 0) revert IBondCurve.InvalidBondCurveValues();

        for (uint256 i = 1; i < intervals.length; ++i) {
            unchecked {
                if (intervals[i].minKeysCount <= intervals[i - 1].minKeysCount) {
                    revert IBondCurve.InvalidBondCurveValues();
                }
                if (intervals[i].trend == 0) revert IBondCurve.InvalidBondCurveValues();
            }
        }
    }
}
