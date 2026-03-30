// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "../interfaces/IBaseModule.sol";
import { FORCED_TARGET_LIMIT_MODE_ID } from "../interfaces/IStakingModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { IParametersRegistry } from "../interfaces/IParametersRegistry.sol";

import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";
import { ValidatorCountsReport } from "./ValidatorCountsReport.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";
import { KeyPointerLib } from "./KeyPointerLib.sol";
import { StakeTracker } from "./StakeTracker.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";
import { SigningKeys } from "./SigningKeys.sol";

/// @dev The library is used to reduce BaseModule bytecode size.
library NodeOperatorOps {
    using TransientUintUintMapLib for TransientUintUintMap;

    function createNodeOperator(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address stETH
    ) external {
        if (from == address(0)) revert IBaseModule.ZeroSenderAddress();
        if (managementProperties.managerAddress == stETH) revert IBaseModule.InvalidManagerAddress();
        if (managementProperties.rewardAddress == stETH) revert IBaseModule.InvalidRewardAddress();

        NodeOperator storage no = nodeOperators[nodeOperatorId];

        address managerAddress = managementProperties.managerAddress == address(0)
            ? from
            : managementProperties.managerAddress;
        address rewardAddress = managementProperties.rewardAddress == address(0)
            ? from
            : managementProperties.rewardAddress;
        no.managerAddress = managerAddress;
        no.rewardAddress = rewardAddress;
        if (managementProperties.extendedManagerPermissions) {
            no.extendedManagerPermissions = managementProperties.extendedManagerPermissions;
        }

        emit IBaseModule.NodeOperatorAdded(
            nodeOperatorId,
            managerAddress,
            rewardAddress,
            managementProperties.extendedManagerPermissions
        );
    }

    function setTargetLimit(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) external {
        if (targetLimitMode > FORCED_TARGET_LIMIT_MODE_ID) revert IBaseModule.InvalidInput();
        if (targetLimit > type(uint32).max) revert IBaseModule.InvalidInput();

        NodeOperator storage no = nodeOperators[nodeOperatorId];

        if (no.managerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();
        if (targetLimitMode == 0) targetLimit = 0;
        if (no.targetLimitMode == targetLimitMode && no.targetLimit == targetLimit) return;

        // `targetLimitMode` is validated against FORCED_TARGET_LIMIT_MODE_ID (fits uint8).
        // forge-lint: disable-next-line(unsafe-typecast)
        no.targetLimitMode = uint8(targetLimitMode);
        // `targetLimit` is explicitly bounded by type(uint32).max above.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.targetLimit = uint32(targetLimit);

        emit IBaseModule.TargetValidatorsCountChanged(nodeOperatorId, targetLimitMode, targetLimit);
    }

    function updateExitedValidatorsCount(
        ModuleLinearStorage.BaseModuleStorage storage $,
        bytes calldata nodeOperatorIds,
        bytes calldata exitedValidatorsCounts
    ) external {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(nodeOperatorIds, exitedValidatorsCounts);

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (uint256 nodeOperatorId, uint256 exitedValidatorsCount) = ValidatorCountsReport.next(
                nodeOperatorIds,
                exitedValidatorsCounts,
                i
            );
            _updateExitedValidatorsCount($, nodeOperatorId, exitedValidatorsCount, false);
        }
    }

    function unsafeUpdateValidatorsCount(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 exitedValidatorsCount
    ) external {
        _updateExitedValidatorsCount($, nodeOperatorId, exitedValidatorsCount, true);
    }

    function decreaseVettedSigningKeysCount(
        ModuleLinearStorage.BaseModuleStorage storage $,
        bytes calldata nodeOperatorIds,
        bytes calldata vettedSigningKeysCounts
    ) external {
        IBaseModule module = IBaseModule(address(this));
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(nodeOperatorIds, vettedSigningKeysCounts);

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (uint256 nodeOperatorId, uint256 vettedSigningKeysCount) = ValidatorCountsReport.next(
                nodeOperatorIds,
                vettedSigningKeysCounts,
                i
            );
            _onlyExistingNodeOperator(nodeOperatorId, $.nodeOperatorsCount);

            NodeOperator storage no = $.nodeOperators[nodeOperatorId];

            if (vettedSigningKeysCount == no.totalVettedKeys) continue;

            if (vettedSigningKeysCount > no.totalVettedKeys) revert IBaseModule.InvalidVetKeysPointer();
            if (vettedSigningKeysCount < no.totalDepositedKeys) revert IBaseModule.InvalidVetKeysPointer();

            // NodeOperator.totalVettedKeys and totalDepositedKeys are uint32 slots; the checks above keep
            // `vettedSigningKeysCount` within those limits, so this cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalVettedKeys = uint32(vettedSigningKeysCount);
            emit IBaseModule.VettedSigningKeysCountChanged(nodeOperatorId, vettedSigningKeysCount);

            // @dev separate event for intentional decrease from Staking Router
            emit IBaseModule.VettedSigningKeysCountDecreased(nodeOperatorId);

            module.updateDepositableValidatorsCount(nodeOperatorId);
        }
    }

    function reportValidatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 currentBalanceWei
    ) external {
        _onlyExistingNodeOperator(nodeOperatorId, $.nodeOperatorsCount);
        if (keyIndex >= $.nodeOperators[nodeOperatorId].totalDepositedKeys) {
            revert IBaseModule.SigningKeysInvalidOffset();
        }

        if (currentBalanceWei < ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE) revert IBaseModule.UnreportableBalance();
        if (currentBalanceWei > ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE) {
            currentBalanceWei = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE;
        }

        uint256 newConfirmed;
        unchecked {
            newConfirmed = currentBalanceWei - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        }

        StakeTracker.reportValidatorBalance($, nodeOperatorId, keyIndex, newConfirmed);
    }

    function removeKeys(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount,
        bool useKeyRemovalCharge
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];

        if (startIndex < no.totalDepositedKeys) revert IBaseModule.SigningKeysInvalidOffset();

        uint256 newTotalSigningKeys = SigningKeys.removeKeysSigs({
            nodeOperatorId: nodeOperatorId,
            startIndex: startIndex,
            keysCount: keysCount,
            totalKeysCount: no.totalAddedKeys
        });

        if (useKeyRemovalCharge) {
            IBaseModule module = IBaseModule(address(this));
            IParametersRegistry parametersRegistry = module.PARAMETERS_REGISTRY();
            IAccounting accounting = module.ACCOUNTING();

            // The Node Operator is charged for the every removed key. It's motivated by the fact that the DAO should cleanup
            // the queue from the empty batches related to the Node Operator. It's possible to have multiple batches with only one
            // key in it, so it means the DAO should be able to cover removal costs for as much batches as keys removed in this case.
            uint256 amountToCharge = parametersRegistry.getKeyRemovalCharge(accounting.getBondCurveId(nodeOperatorId)) *
                keysCount;

            if (amountToCharge != 0 && accounting.chargeFee(nodeOperatorId, amountToCharge)) {
                emit IBaseModule.KeyRemovalChargeApplied(nodeOperatorId);
            }
        }

        // Added/vetted signing key counters are uint32 fields; newTotalSigningKeys is strictly
        // less than no.totalAddedKeys, so it always fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalAddedKeys = uint32(newTotalSigningKeys);
        emit IBaseModule.TotalSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);

        // Reset vetted keys pointer since we can not know if the removed keys were previously unvetted due to being invalid, or not.
        // If invalid keys are still present after deletion and vetted keys pointer reset, they will be unvetted again.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalVettedKeys = uint32(newTotalSigningKeys);
        emit IBaseModule.VettedSigningKeysCountChanged(nodeOperatorId, newTotalSigningKeys);
    }

    function addKeys(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        uint256 totalAddedKeys = no.totalAddedKeys;

        IBaseModule module = IBaseModule(address(this));
        uint256 keysLimit = module.PARAMETERS_REGISTRY().getKeysLimit(
            module.ACCOUNTING().getBondCurveId(nodeOperatorId)
        );

        unchecked {
            if (totalAddedKeys + keysCount - no.totalWithdrawnKeys > keysLimit) revert IBaseModule.KeysLimitExceeded();

            uint256 newTotalAddedKeys = SigningKeys.saveKeysSigs({
                nodeOperatorId: nodeOperatorId,
                startIndex: totalAddedKeys,
                keysCount: keysCount,
                pubkeys: publicKeys,
                signatures: signatures
            });

            uint32 totalVettedKeys = no.totalVettedKeys;
            // Optimistic vetting takes place.
            if (totalAddedKeys == totalVettedKeys) {
                // Sum stays <= totalAddedKeys (< 2^32 by design), so the result fits uint32.
                // forge-lint: disable-next-line(unsafe-typecast)
                totalVettedKeys = totalVettedKeys + uint32(keysCount);
                no.totalVettedKeys = totalVettedKeys;
                emit IBaseModule.VettedSigningKeysCountChanged(nodeOperatorId, totalVettedKeys);
            }

            // Added key counters are uint32 slots; hitting 2^32 keys would require unreachable bond
            // capital and calldata, so newTotalAddedKeys stays within the slot bounds.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalAddedKeys = uint32(newTotalAddedKeys);

            emit IBaseModule.TotalSigningKeysCountChanged(nodeOperatorId, newTotalAddedKeys);
        }
    }

    function calculateDepositableValidatorsCount(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId
    ) external view returns (uint256 newCount) {
        NodeOperator storage no = nodeOperators[nodeOperatorId];

        uint256 totalDepositedKeys = no.totalDepositedKeys;
        newCount = no.totalVettedKeys - totalDepositedKeys;
        IBaseModule module = IBaseModule(address(this));
        uint256 unbondedKeys = module.ACCOUNTING().getUnbondedKeysCount(nodeOperatorId);

        uint256 nonDeposited = no.totalAddedKeys - totalDepositedKeys;
        if (unbondedKeys >= nonDeposited) {
            newCount = 0;
        } else if (unbondedKeys > no.totalAddedKeys - no.totalVettedKeys) {
            newCount = nonDeposited - unbondedKeys;
        }

        if (no.targetLimitMode > 0 && newCount > 0) {
            unchecked {
                uint256 nonWithdrawnValidators = totalDepositedKeys - no.totalWithdrawnKeys;

                uint256 targetLimit = no.targetLimit;
                uint256 leftToLimit = 0;

                if (targetLimit > nonWithdrawnValidators) leftToLimit = targetLimit - nonWithdrawnValidators;
                if (newCount > leftToLimit) newCount = leftToLimit;
            }
        }
    }

    function getNodeOperatorSummary(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        IAccounting accounting
    )
        external
        view
        returns (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        if (no.managerAddress == address(0)) revert IBaseModule.NodeOperatorDoesNotExist();

        uint256 totalUnbondedKeys = accounting.getUnbondedKeysCountToEject(nodeOperatorId);
        uint256 totalNonDepositedKeys = no.totalAddedKeys - no.totalDepositedKeys;
        if (totalUnbondedKeys > totalNonDepositedKeys) {
            targetLimitMode = FORCED_TARGET_LIMIT_MODE_ID;
            unchecked {
                targetValidatorsCount = no.totalAddedKeys - no.totalWithdrawnKeys - totalUnbondedKeys;
            }
            // NOTE: If a targetLimit is manually set for the Node Operator and the Node Operator has unbonded keys
            //       we take the lowest value and set the target limit mode to FORCED_TARGET_LIMIT_MODE_ID.
            //       This can potentially speed up withdrawal requests for this Node Operator if the target limit set manually was set with targetLimitMode = 1
            //       and the target limit value was higher than the number of validators left after ejecting unbonded keys,
            //       but it ensures that Node Operators cannot game the limit by obtaining a few unbonded keys and effectively reducing the target limit value.
            if (no.targetLimitMode > 0) targetValidatorsCount = Math.min(targetValidatorsCount, no.targetLimit);
        } else {
            targetLimitMode = no.targetLimitMode;
            targetValidatorsCount = no.targetLimit;
        }
        stuckValidatorsCount = 0;
        refundedValidatorsCount = 0;
        stuckPenaltyEndTimestamp = 0;
        totalExitedValidators = no.totalExitedKeys;
        totalDepositedValidators = no.totalDepositedKeys;
        depositableValidatorsCount = no.depositableValidatorsCount;
    }

    function capTopUpLimitsByKeyBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory cappedTopUpLimits) {
        uint256 len = topUpLimits.length;
        cappedTopUpLimits = new uint256[](len);
        uint256 cap = _keyBalanceCap();
        TransientUintUintMap reservedByKey = TransientUintUintMapLib.create();
        for (uint256 i; i < len; ++i) {
            uint256 pointer = KeyPointerLib.keyPointer(operatorIds[i], keyIndices[i]);
            // Withdrawn keys must not receive new top-ups, but returning zero keeps CSM queue cleanup
            // working for stale or rewound head items.
            if ($.isValidatorWithdrawn[pointer]) continue;

            // Share the remaining headroom across duplicate keys in the same batch so later entries
            // cannot reserve the same per-key capacity twice.
            uint256 balance = $.keyAllocatedBalance[pointer] + reservedByKey.get(pointer);
            uint256 remaining = balance > cap ? 0 : cap - balance;
            uint256 capped = Math.min(topUpLimits[i], remaining);
            cappedTopUpLimits[i] = capped;
            reservedByKey.add(pointer, capped);
        }
    }

    function getKeyAllocatedBalances(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](keysCount);
        for (uint256 i; i < keysCount; ++i) {
            balances[i] = $.keyAllocatedBalance[KeyPointerLib.keyPointer(nodeOperatorId, startIndex + i)];
        }
    }

    function getKeyConfirmedBalances(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](keysCount);
        for (uint256 i; i < keysCount; ++i) {
            balances[i] = $.keyConfirmedBalance[KeyPointerLib.keyPointer(nodeOperatorId, startIndex + i)];
        }
    }

    function getNodeOperatorIds(
        uint256 nodeOperatorsCount,
        uint256 offset,
        uint256 limit
    ) external pure returns (uint256[] memory nodeOperatorIds) {
        if (offset >= nodeOperatorsCount || limit == 0) return nodeOperatorIds;

        unchecked {
            uint256 idsCount = nodeOperatorsCount - offset;
            if (idsCount > limit) idsCount = limit;

            nodeOperatorIds = new uint256[](idsCount);
            for (uint256 i; i < idsCount; ++i) {
                nodeOperatorIds[i] = offset++;
            }
        }
    }

    function _updateExitedValidatorsCount(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 exitedValidatorsCount,
        bool allowDecrease
    ) internal {
        _onlyExistingNodeOperator(nodeOperatorId, $.nodeOperatorsCount);
        NodeOperator storage no = $.nodeOperators[nodeOperatorId];
        if (exitedValidatorsCount > no.totalDepositedKeys) revert IBaseModule.InvalidInput();
        if (!allowDecrease && exitedValidatorsCount < no.totalExitedKeys) revert IBaseModule.InvalidInput();

        unchecked {
            // @dev Invariant sum(no.totalExitedKeys for no in nos) == totalExitedValidators.
            // `totalExitedValidators` accumulates the same uint32 per-operator counts, so pushing
            // the new value through uint64 preserves the exact result.
            // forge-lint: disable-next-item(unsafe-typecast)
            $.totalExitedValidators = ($.totalExitedValidators - no.totalExitedKeys) + uint64(exitedValidatorsCount);
        }
        // Each node operator stores its exited count in a uint32 slot; `exitedValidatorsCount`
        // is validated against `totalDepositedKeys` (also uint32), so the cast is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.totalExitedKeys = uint32(exitedValidatorsCount);

        emit IBaseModule.ExitedSigningKeysCountChanged(nodeOperatorId, exitedValidatorsCount);
    }

    function _onlyExistingNodeOperator(uint256 nodeOperatorId, uint256 nodeOperatorsCount) internal pure {
        if (nodeOperatorId < nodeOperatorsCount) return;

        revert IBaseModule.NodeOperatorDoesNotExist();
    }

    function _keyBalanceCap() private pure returns (uint256) {
        return ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
    }
}
