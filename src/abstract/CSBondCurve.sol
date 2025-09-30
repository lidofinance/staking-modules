// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { BondCurves } from "../lib/BondCurves.sol";

import { ICSBondCurve } from "../interfaces/ICSBondCurve.sol";

/// @dev Bond curve mechanics abstract contract
///
/// It gives the ability to build bond curves for flexible bond math.
/// There is a default bond curve for all Node Operators, which might be 'overridden' for a particular Node Operator.
///
/// It contains:
///  - add bond curve
///  - get bond curve info
///  - set default bond curve
///  - set bond curve for the given Node Operator
///  - get bond curve for the given Node Operator
///  - get required bond amount for the given keys count
///  - get keys count for the given bond amount
///
/// It should be inherited by a module contract or a module-related contract.
/// Internal non-view methods should be used in the Module contract with additional requirements (if any).
///
/// @author vgorkavenko
abstract contract CSBondCurve is ICSBondCurve, Initializable {
    /// @custom:storage-location erc7201:CSBondCurve
    struct CSBondCurveStorage {
        /// @dev DEPRECATED. DO NOT USE. Preserves storage layout.
        bytes32[] legacyBondCurves;
        /// @dev Mapping of Node Operator id to bond curve id
        mapping(uint256 nodeOperatorId => uint256 bondCurveId) operatorBondCurveId;
        BondCurve[] bondCurves;
    }

    // keccak256(abi.encode(uint256(keccak256("CSBondCurve")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CS_BOND_CURVE_STORAGE_LOCATION =
        0x8f22e270e477f5becb8793b61d439ab7ae990ed8eba045eb72061c0e6cfe1500;

    uint256 public constant DEFAULT_BOND_CURVE_ID = 0;

    // @inheritdoc ICSBondCurve
    function getCurvesCount() external view returns (uint256) {
        return _getCSBondCurveStorage().bondCurves.length;
    }

    /// @inheritdoc ICSBondCurve
    function getCurveInfo(
        uint256 curveId
    ) external view returns (BondCurve memory) {
        return _getCurveInfo(curveId);
    }

    /// @inheritdoc ICSBondCurve
    function getBondCurve(
        uint256 nodeOperatorId
    ) external view returns (BondCurve memory) {
        return _getCurveInfo(getBondCurveId(nodeOperatorId));
    }

    /// @inheritdoc ICSBondCurve
    function getBondCurveId(
        uint256 nodeOperatorId
    ) public view returns (uint256) {
        return _getCSBondCurveStorage().operatorBondCurveId[nodeOperatorId];
    }

    /// @inheritdoc ICSBondCurve
    function getBondAmountByKeysCount(
        uint256 keys,
        uint256 curveId
    ) public view returns (uint256) {
        return
            BondCurves.getBondAmountByKeysCount(
                _getCSBondCurveStorage(),
                keys,
                curveId
            );
    }

    /// @inheritdoc ICSBondCurve
    function getKeysCountByBondAmount(
        uint256 amount,
        uint256 curveId
    ) public view returns (uint256) {
        return
            BondCurves.getKeysCountByBondAmount(
                _getCSBondCurveStorage(),
                amount,
                curveId
            );
    }

    // solhint-disable-next-line func-name-mixedcase
    function __CSBondCurve_init(
        BondCurveIntervalInput[] calldata defaultBondCurveIntervals
    ) internal onlyInitializing {
        uint256 addedId = _addBondCurve(defaultBondCurveIntervals);
        if (addedId != DEFAULT_BOND_CURVE_ID) {
            revert InvalidInitializationCurveId();
        }
    }

    /// @dev Add a new bond curve to the array
    function _addBondCurve(
        BondCurveIntervalInput[] calldata intervals
    ) internal returns (uint256 curveId) {
        curveId = BondCurves.addBondCurve(_getCSBondCurveStorage(), intervals);
        emit BondCurveAdded(curveId, intervals);
    }

    /// @dev Update existing bond curve
    function _updateBondCurve(
        uint256 curveId,
        BondCurveIntervalInput[] calldata intervals
    ) internal {
        BondCurves.updateBondCurve(
            _getCSBondCurveStorage(),
            curveId,
            intervals
        );
        emit BondCurveUpdated(curveId, intervals);
    }

    /// @dev Sets bond curve for the given Node Operator
    ///      It will be used for the Node Operator instead of the previously set curve
    function _setBondCurve(uint256 nodeOperatorId, uint256 curveId) internal {
        CSBondCurveStorage storage $ = _getCSBondCurveStorage();
        unchecked {
            if (curveId > $.bondCurves.length - 1) {
                revert InvalidBondCurveId();
            }
        }
        $.operatorBondCurveId[nodeOperatorId] = curveId;
        emit BondCurveSet(nodeOperatorId, curveId);
    }

    function _getBondAmountByKeysCount(
        uint256 keys,
        BondCurve storage curve
    ) internal view returns (uint256) {
        BondCurveInterval[] storage intervals = curve.intervals;
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
            BondCurveInterval storage interval = intervals[low];
            return
                interval.minBond +
                (keys - interval.minKeysCount) *
                interval.trend;
        }
    }

    function _getKeysCountByBondAmount(
        uint256 amount,
        BondCurve storage curve
    ) internal view returns (uint256) {
        BondCurveInterval[] storage intervals = curve.intervals;

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

            BondCurveInterval storage interval;

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

    function _addIntervalsToBondCurve(
        BondCurve storage bondCurve,
        BondCurveIntervalInput[] calldata intervals
    ) private {
        BondCurveInterval storage interval = bondCurve.intervals.push();

        interval.minKeysCount = intervals[0].minKeysCount;
        interval.trend = intervals[0].trend;
        interval.minBond = intervals[0].trend;

        for (uint256 i = 1; i < intervals.length; ++i) {
            BondCurveInterval storage prev = interval;
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

    function _getCurveInfo(
        uint256 curveId
    ) private view returns (BondCurve storage) {
        CSBondCurveStorage storage $ = _getCSBondCurveStorage();
        unchecked {
            if (curveId > $.bondCurves.length - 1) {
                revert InvalidBondCurveId();
            }
        }

        return $.bondCurves[curveId];
    }

    function _getCSBondCurveStorage()
        private
        pure
        returns (CSBondCurveStorage storage $)
    {
        assembly {
            $.slot := CS_BOND_CURVE_STORAGE_LOCATION
        }
    }
}
