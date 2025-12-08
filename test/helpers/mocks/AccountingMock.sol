// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IBondLock } from "src/interfaces/IBondLock.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { ILido } from "src/interfaces/ILido.sol";
import { IFeeDistributor } from "src/interfaces/IFeeDistributor.sol";

contract AccountingMock {
    uint256 public constant DEFAULT_BOND_CURVE_ID = 0;
    uint256 public constant DEFAULT_BOND_LOCK_PERIOD = 1 days;

    error BondLockAmountTooLarge();
    error BondLockUnlockTimeTooLarge();

    ILido public immutable LIDO;

    mapping(uint256 nodeOperatorId => IBondLock.BondLockData) bondLock;
    mapping(uint256 nodeOperatorId => uint256) bond;

    mapping(uint256 nodeOperatorId => uint256 bondCurveId) operatorBondCurveId;
    uint256[] bondCurves;

    uint256 internal _nextCurveId = 1;

    IBaseModule public MODULE;
    IWstETH public wstETH;
    IFeeDistributor public FEE_DISTRIBUTOR;

    constructor(
        uint256 _bond,
        address _wstETH,
        address lido,
        address _feeDistributor
    ) {
        bondCurves.push(_bond);
        wstETH = IWstETH(_wstETH);
        LIDO = ILido(lido);
        FEE_DISTRIBUTOR = IFeeDistributor(_feeDistributor);
    }

    function setModule(IBaseModule _module) external {
        MODULE = _module;
    }

    function depositETH(
        address /* from */,
        uint256 nodeOperatorId
    ) external payable {
        bond[nodeOperatorId] += msg.value;
    }

    function depositETH(uint256 nodeOperatorId) external payable {
        bond[nodeOperatorId] += msg.value;
    }

    function depositStETH(
        address /* from */,
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        IAccounting.PermitInput calldata /* permit */
    ) external {
        bond[nodeOperatorId] += stETHAmount;
    }

    function depositStETH(
        uint256 nodeOperatorId,
        uint256 stETHAmount,
        IAccounting.PermitInput calldata /* permit */
    ) external {
        bond[nodeOperatorId] += stETHAmount;
    }

    function depositWstETH(
        address /* from */,
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        IAccounting.PermitInput calldata /* permit */
    ) external {
        bond[nodeOperatorId] += wstETH.getStETHByWstETH(wstETHAmount);
    }

    function depositWstETH(
        uint256 nodeOperatorId,
        uint256 wstETHAmount,
        IAccounting.PermitInput calldata /* permit */
    ) external {
        bond[nodeOperatorId] += wstETH.getStETHByWstETH(wstETHAmount);
    }

    function lockBondETH(uint256 nodeOperatorId, uint256 amount) external {
        // Production storage keeps bond lock amounts/timestamps in uint128,
        // and the mock only ever touches small ether values, so the cast is safe.
        if (amount > type(uint128).max) {
            revert BondLockAmountTooLarge();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        bondLock[nodeOperatorId].amount += uint128(amount);
        uint256 unlockTs = block.timestamp + DEFAULT_BOND_LOCK_PERIOD;
        if (unlockTs > type(uint128).max) {
            revert BondLockUnlockTimeTooLarge();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 unlockAt = uint128(unlockTs);
        bondLock[nodeOperatorId].until = unlockAt;
    }

    function releaseLockedBondETH(
        uint256 nodeOperatorId,
        uint256 amount
    ) external {
        // Bond lock amounts mirror production's uint128 slot, so truncation cannot happen.
        // forge-lint: disable-next-line(unsafe-typecast)
        bondLock[nodeOperatorId].amount -= uint128(amount);
    }

    function settleLockedBondETH(
        uint256 nodeOperatorId
    ) external returns (bool applied) {
        uint256 lockedBond = getActualLockedBond(nodeOperatorId);
        if (lockedBond > 0) {
            applied = true;
        }
        if (lockedBond > bond[nodeOperatorId]) {
            bond[nodeOperatorId] = 0;
        } else {
            bond[nodeOperatorId] -= lockedBond;
        }
        bondLock[nodeOperatorId].amount = 0;
        bondLock[nodeOperatorId].until = 0;
    }

    function compensateLockedBondETH(uint256 nodeOperatorId) external payable {
        // Compensation values are bounded by msg.value (<= uint128 in tests), matching storage type.
        if (msg.value > type(uint128).max) {
            revert BondLockAmountTooLarge();
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        bondLock[nodeOperatorId].amount -= uint128(msg.value);
        if (bondLock[nodeOperatorId].amount < 0) {
            bondLock[nodeOperatorId].until = 0;
        }
    }

    function setBondCurve(uint256 nodeOperatorId, uint256 curveId) external {}

    function updateBondCurve(uint256 curveId, uint256 _bond) external {
        bondCurves[curveId] = _bond;
    }

    function addBondCurve(
        IBondCurve.BondCurveIntervalInput[] calldata
    ) external returns (uint256 curveId) {
        curveId = _nextCurveId;
        _nextCurveId += 1;
    }

    function penalize(
        uint256 nodeOperatorId,
        uint256 amount
    ) external returns (bool fullyBurned) {
        if (bond[nodeOperatorId] < amount) {
            bond[nodeOperatorId] = 0;
            fullyBurned = false;
        } else {
            bond[nodeOperatorId] -= amount;
            fullyBurned = true;
        }
    }

    function chargeFee(
        uint256 nodeOperatorId,
        uint256 amount
    ) external returns (bool fullyCharged) {
        if (bond[nodeOperatorId] < amount) {
            bond[nodeOperatorId] = 0;
            fullyCharged = false;
        } else {
            bond[nodeOperatorId] -= amount;
            fullyCharged = true;
        }
    }

    function getBond(uint256 nodeOperatorId) public view returns (uint256) {
        return bond[nodeOperatorId];
    }

    function getBondSummary(
        uint256 nodeOperatorId
    ) public view returns (uint256 current, uint256 required) {
        return (
            bond[nodeOperatorId],
            getBondAmountByKeysCount(
                MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId),
                operatorBondCurveId[nodeOperatorId]
            ) + getActualLockedBond(nodeOperatorId)
        );
    }

    function getRequiredBondForNextKeys(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) public view returns (uint256) {
        uint256 current = getBond(nodeOperatorId);
        uint256 requiredForNewTotalKeys = getBondAmountByKeysCount(
            MODULE.getNodeOperatorNonWithdrawnKeys(nodeOperatorId) +
                additionalKeys,
            operatorBondCurveId[nodeOperatorId]
        );
        uint256 totalRequired = requiredForNewTotalKeys +
            getActualLockedBond(nodeOperatorId);

        unchecked {
            return totalRequired > current ? totalRequired - current : 0;
        }
    }

    function getRequiredBondForNextKeysWstETH(
        uint256 nodeOperatorId,
        uint256 additionalKeys
    ) public view returns (uint256) {
        return
            wstETH.getWstETHByStETH(
                getRequiredBondForNextKeys(nodeOperatorId, additionalKeys)
            );
    }

    function getActualLockedBond(
        uint256 nodeOperatorId
    ) public view returns (uint256) {
        if (bondLock[nodeOperatorId].until <= block.timestamp) {
            return 0;
        }
        return bondLock[nodeOperatorId].amount;
    }

    function getLockedBondInfo(
        uint256 nodeOperatorId
    ) external view returns (IBondLock.BondLockData memory) {
        return bondLock[nodeOperatorId];
    }

    function getBondLockPeriod() external pure returns (uint256) {
        return DEFAULT_BOND_LOCK_PERIOD;
    }

    function getBondAmountByKeysCount(
        uint256 keys,
        uint256 curveId
    ) public view returns (uint256) {
        return keys * bondCurves[curveId];
    }

    function getUnbondedKeysCount(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        (uint256 current, uint256 required) = getBondSummary(nodeOperatorId);
        current += 10 wei;
        if (current >= required) {
            return 0;
        }
        return
            (required - current) /
            bondCurves[operatorBondCurveId[nodeOperatorId]] +
            1;
    }

    function getUnbondedKeysCountToEject(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        (uint256 current, uint256 required) = getBondSummary(nodeOperatorId);
        current += 10 wei;
        required -= getActualLockedBond(nodeOperatorId);
        if (current >= required) {
            return 0;
        }
        return
            (required - current) /
            bondCurves[operatorBondCurveId[nodeOperatorId]] +
            1;
    }

    function getBondCurveId(
        uint256 nodeOperatorId
    ) external view returns (uint256) {
        return operatorBondCurveId[nodeOperatorId];
    }
}
