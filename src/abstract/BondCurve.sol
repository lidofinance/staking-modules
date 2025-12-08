// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { BondCurves } from "../lib/BondCurves.sol";

import { IBondCurve } from "../interfaces/IBondCurve.sol";

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
abstract contract BondCurve is IBondCurve, Initializable {
    /// @custom:storage-location erc7201:CSBondCurve
    struct BondCurveStorage {
        /// @dev DEPRECATED. DO NOT USE. Preserves storage layout. Previous structure occupied 3 slots per item.
        bytes32[] legacyBondCurves;
        /// @dev Mapping of Node Operator id to bond curve id
        mapping(uint256 nodeOperatorId => uint256 bondCurveId) operatorBondCurveId;
        BondCurveData[] bondCurves;
    }

    // keccak256(abi.encode(uint256(keccak256("CSBondCurve")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BOND_CURVE_STORAGE_LOCATION =
        0x8f22e270e477f5becb8793b61d439ab7ae990ed8eba045eb72061c0e6cfe1500;

    uint256 public constant DEFAULT_BOND_CURVE_ID = 0;

    // @inheritdoc IBondCurve
    function getCurvesCount() external view returns (uint256) {
        return _getBondCurveStorage().bondCurves.length;
    }

    /// @inheritdoc IBondCurve
    function getCurveInfo(
        uint256 curveId
    ) external view returns (BondCurveData memory) {
        return _getCurveInfo(curveId);
    }

    /// @inheritdoc IBondCurve
    function getBondCurve(
        uint256 nodeOperatorId
    ) external view returns (BondCurveData memory) {
        return _getCurveInfo(getBondCurveId(nodeOperatorId));
    }

    /// @inheritdoc IBondCurve
    function getBondCurveId(
        uint256 nodeOperatorId
    ) public view returns (uint256) {
        return _getBondCurveStorage().operatorBondCurveId[nodeOperatorId];
    }

    /// @inheritdoc IBondCurve
    function getBondAmountByKeysCount(
        uint256 keys,
        uint256 curveId
    ) public view returns (uint256) {
        return
            BondCurves.getBondAmountByKeysCount(
                _getBondCurveStorage(),
                keys,
                curveId
            );
    }

    /// @inheritdoc IBondCurve
    function getKeysCountByBondAmount(
        uint256 amount,
        uint256 curveId
    ) public view returns (uint256) {
        return
            BondCurves.getKeysCountByBondAmount(
                _getBondCurveStorage(),
                amount,
                curveId
            );
    }

    // solhint-disable-next-line func-name-mixedcase
    function __BondCurve_init(
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
        curveId = BondCurves.addBondCurve(_getBondCurveStorage(), intervals);
        emit BondCurveAdded(curveId, intervals);
    }

    /// @dev Update existing bond curve
    function _updateBondCurve(
        uint256 curveId,
        BondCurveIntervalInput[] calldata intervals
    ) internal {
        BondCurves.updateBondCurve(_getBondCurveStorage(), curveId, intervals);
        emit BondCurveUpdated(curveId, intervals);
    }

    /// @dev Sets bond curve for the given Node Operator
    ///      It will be used for the Node Operator instead of the previously set curve
    function _setBondCurve(uint256 nodeOperatorId, uint256 curveId) internal {
        BondCurveStorage storage $ = _getBondCurveStorage();
        unchecked {
            if (curveId > $.bondCurves.length - 1) {
                revert InvalidBondCurveId();
            }
        }
        $.operatorBondCurveId[nodeOperatorId] = curveId;
        emit BondCurveSet(nodeOperatorId, curveId);
    }

    function _getCurveInfo(
        uint256 curveId
    ) private view returns (BondCurveData storage) {
        BondCurveStorage storage $ = _getBondCurveStorage();
        unchecked {
            if (curveId > $.bondCurves.length - 1) {
                revert InvalidBondCurveId();
            }
        }

        return $.bondCurves[curveId];
    }

    function _getBondCurveStorage()
        private
        pure
        returns (BondCurveStorage storage $)
    {
        assembly {
            $.slot := BOND_CURVE_STORAGE_LOCATION
        }
    }
}
