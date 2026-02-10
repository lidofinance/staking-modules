// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "../interfaces/IBaseModule.sol";
import { FORCED_TARGET_LIMIT_MODE_ID } from "../interfaces/IStakingModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

import { CuratedDepositAllocator } from "./allocator/CuratedDepositAllocator.sol";
import { ValidatorCountsReport } from "./ValidatorCountsReport.sol";
import { WithdrawnValidatorLib } from "./WithdrawnValidatorLib.sol";

/// @dev The library is used to reduce BaseModule bytecode size.
library NodeOperatorOps {
    function getNodeOperatorIds(
        uint256 nodeOperatorsCount,
        uint256 offset,
        uint256 limit
    ) external pure returns (uint256[] memory nodeOperatorIds) {
        if (offset >= nodeOperatorsCount || limit == 0) {
            return nodeOperatorIds;
        }

        unchecked {
            uint256 idsCount = nodeOperatorsCount - offset;
            if (idsCount > limit) idsCount = limit;

            nodeOperatorIds = new uint256[](idsCount);
            for (uint256 i; i < idsCount; ++i) {
                nodeOperatorIds[i] = offset++;
            }
        }
    }

    function createNodeOperator(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address referrer
    ) external {
        if (from == address(0)) {
            revert IBaseModule.ZeroSenderAddress();
        }

        NodeOperator storage no = nodeOperators[nodeOperatorId];

        address managerAddress = managementProperties.managerAddress ==
            address(0)
            ? from
            : managementProperties.managerAddress;
        address rewardAddress = managementProperties.rewardAddress == address(0)
            ? from
            : managementProperties.rewardAddress;
        no.managerAddress = managerAddress;
        no.rewardAddress = rewardAddress;
        if (managementProperties.extendedManagerPermissions) {
            no.extendedManagerPermissions = managementProperties
                .extendedManagerPermissions;
        }

        emit IBaseModule.NodeOperatorAdded(
            nodeOperatorId,
            managerAddress,
            rewardAddress,
            managementProperties.extendedManagerPermissions
        );

        if (referrer != address(0)) {
            emit IBaseModule.ReferrerSet(nodeOperatorId, referrer);
        }
    }

    function setTargetLimit(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 nodeOperatorId,
        uint256 targetLimitMode,
        uint256 targetLimit
    ) external {
        if (targetLimitMode > FORCED_TARGET_LIMIT_MODE_ID) {
            revert IBaseModule.InvalidInput();
        }
        if (targetLimit > type(uint32).max) {
            revert IBaseModule.InvalidInput();
        }

        NodeOperator storage no = nodeOperators[nodeOperatorId];

        if (no.managerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        if (targetLimitMode == 0) {
            targetLimit = 0;
        }

        if (
            no.targetLimitMode == targetLimitMode &&
            no.targetLimit == targetLimit
        ) {
            return;
        }

        // `targetLimitMode` is validated against FORCED_TARGET_LIMIT_MODE_ID (fits uint8).
        // forge-lint: disable-next-line(unsafe-typecast)
        no.targetLimitMode = uint8(targetLimitMode);
        // `targetLimit` is explicitly bounded by type(uint32).max above.
        // forge-lint: disable-next-line(unsafe-typecast)
        no.targetLimit = uint32(targetLimit);

        emit IBaseModule.TargetValidatorsCountChanged(
            nodeOperatorId,
            targetLimitMode,
            targetLimit
        );
    }

    function updateExitedValidatorsCount(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint64 totalExitedValidators,
        bytes calldata nodeOperatorIds,
        bytes calldata exitedValidatorsCounts
    ) external returns (uint64) {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(
            nodeOperatorIds,
            exitedValidatorsCounts
        );

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (
                uint256 nodeOperatorId,
                uint256 exitedValidatorsCount
            ) = ValidatorCountsReport.next(
                    nodeOperatorIds,
                    exitedValidatorsCounts,
                    i
                );

            NodeOperator storage no = nodeOperators[nodeOperatorId];
            uint32 totalExitedKeys = no.totalExitedKeys;
            unchecked {
                // @dev Invariant sum(no.totalExitedKeys for no in nos) == totalExitedValidators.
                // `totalExitedValidators` accumulates the same uint32 per-operator counts, so pushing
                // the new value through uint64 preserves the exact result.
                // forge-lint: disable-next-item(unsafe-typecast)
                totalExitedValidators =
                    (totalExitedValidators - totalExitedKeys) +
                    uint64(exitedValidatorsCount);
            }
            // Each node operator stores its exited count in a uint32 slot; `exitedValidatorsCount`
            // is validated against `totalDepositedKeys` (also uint32), so the cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalExitedKeys = uint32(exitedValidatorsCount);

            emit IBaseModule.ExitedSigningKeysCountChanged(
                nodeOperatorId,
                exitedValidatorsCount
            );
        }

        return totalExitedValidators;
    }

    function decreaseVettedSigningKeysCount(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        bytes calldata nodeOperatorIds,
        bytes calldata vettedSigningKeysCounts
    ) external {
        IBaseModule module = IBaseModule(address(this));
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(
            nodeOperatorIds,
            vettedSigningKeysCounts
        );

        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (
                uint256 nodeOperatorId,
                uint256 vettedSigningKeysCount
            ) = ValidatorCountsReport.next(
                    nodeOperatorIds,
                    vettedSigningKeysCounts,
                    i
                );

            NodeOperator storage no = nodeOperators[nodeOperatorId];

            if (no.managerAddress == address(0)) {
                revert IBaseModule.NodeOperatorDoesNotExist();
            }

            if (vettedSigningKeysCount >= no.totalVettedKeys) {
                revert IBaseModule.InvalidVetKeysPointer();
            }

            if (vettedSigningKeysCount < no.totalDepositedKeys) {
                revert IBaseModule.InvalidVetKeysPointer();
            }

            // NodeOperator.totalVettedKeys and totalDepositedKeys are uint32 slots; the checks above keep
            // `vettedSigningKeysCount` within those limits, so this cast is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            no.totalVettedKeys = uint32(vettedSigningKeysCount);
            emit IBaseModule.VettedSigningKeysCountChanged(
                nodeOperatorId,
                vettedSigningKeysCount
            );

            // @dev separate event for intentional decrease from Staking Router
            emit IBaseModule.VettedSigningKeysCountDecreased(nodeOperatorId);

            module.updateDepositableValidatorsCount(nodeOperatorId);
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
        if (no.managerAddress == address(0)) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        uint256 totalUnbondedKeys = accounting.getUnbondedKeysCountToEject(
            nodeOperatorId
        );
        uint256 totalNonDepositedKeys = no.totalAddedKeys -
            no.totalDepositedKeys;
        if (totalUnbondedKeys > totalNonDepositedKeys) {
            targetLimitMode = FORCED_TARGET_LIMIT_MODE_ID;
            unchecked {
                targetValidatorsCount =
                    no.totalAddedKeys -
                    no.totalWithdrawnKeys -
                    totalUnbondedKeys;
            }
            if (no.targetLimitMode > 0) {
                targetValidatorsCount = Math.min(
                    targetValidatorsCount,
                    no.targetLimit
                );
            }
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

    function increaseKeyAddedBalance(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        mapping(uint256 => bool) storage isValidatorWithdrawn,
        mapping(uint256 => uint256) storage keyAddedBalances,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 incrementWei
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        if (keyIndex >= no.totalDepositedKeys) {
            revert IBaseModule.SigningKeysInvalidOffset();
        }

        uint256 pointer = _keyPointer(nodeOperatorId, keyIndex);
        if (isValidatorWithdrawn[pointer]) {
            revert IBaseModule.InvalidWithdrawnValidatorInfo();
        }

        _increaseKeyAddedBalance(
            keyAddedBalances,
            nodeOperatorId,
            keyIndex,
            incrementWei
        );
    }

    function increaseKeyAddedBalancesByAllocations(
        mapping(uint256 => uint256) storage keyAddedBalances,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata allocations
    ) external {
        for (uint256 i; i < allocations.length; ++i) {
            uint256 allocationWei = allocations[i];
            if (allocationWei == 0) {
                continue;
            }
            _increaseKeyAddedBalance(
                keyAddedBalances,
                operatorIds[i],
                keyIndices[i],
                allocationWei
            );
        }
    }

    function capTopUpLimitsByKeyBalance(
        mapping(uint256 => uint256) storage keyAddedBalances,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata topUpLimits
    ) external view returns (uint256[] memory cappedTopUpLimits) {
        uint256 len = topUpLimits.length;
        cappedTopUpLimits = new uint256[](len);
        uint256 cap = _keyAddedBalanceCap();
        for (uint256 i; i < len; ++i) {
            uint256 keyAddedBalance = keyAddedBalances[
                _keyPointer(operatorIds[i], keyIndices[i])
            ];
            uint256 remaining = keyAddedBalance >= cap
                ? 0
                : cap - keyAddedBalance;
            cappedTopUpLimits[i] = Math.min(topUpLimits[i], remaining);
        }
    }

    /// @dev Distribute per-operator allocations to per-key allocations with per-key limits.
    function distributeTopUpAllocations(
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits,
        uint256[] calldata allocatedOperatorIds,
        uint256[] calldata operatorAllocations,
        uint256 operatorsCount
    )
        external
        pure
        returns (
            uint256[] memory allocations,
            uint256[] memory perOperatorIncrements
        )
    {
        // topUpLimits are per-key and aligned with operatorIds/keyIndices order.
        allocations = new uint256[](operatorIds.length);
        // NOTE: Use a full operatorsCount-sized array for O(1) lookups; operator counts are small enough
        // that a compact map would add overhead and can be worse overall.
        uint256[] memory perOperatorAllocations = new uint256[](operatorsCount);
        for (uint256 i; i < allocatedOperatorIds.length; ++i) {
            perOperatorAllocations[
                allocatedOperatorIds[i]
            ] = operatorAllocations[i];
        }

        perOperatorIncrements = new uint256[](operatorsCount);
        unchecked {
            for (uint256 i; i < operatorIds.length; ++i) {
                uint256 operatorId = operatorIds[i];
                uint256 remaining = perOperatorAllocations[operatorId] -
                    perOperatorIncrements[operatorId];
                if (remaining == 0) continue;

                uint256 limit = CuratedDepositAllocator.quantizeForTopUp(
                    topUpLimits[i]
                );
                if (limit == 0) continue;

                uint256 amount = Math.min(remaining, limit);
                allocations[i] = amount;
                perOperatorIncrements[operatorId] += amount;
            }
        }
    }

    function _increaseKeyAddedBalance(
        mapping(uint256 => uint256) storage keyAddedBalances,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 incrementWei
    ) internal {
        uint256 pointer = _keyPointer(nodeOperatorId, keyIndex);
        uint256 current = keyAddedBalances[pointer];
        uint256 cap = _keyAddedBalanceCap();
        if (current == cap) {
            return;
        }
        uint256 updatedBalance = Math.min(cap, current + incrementWei);
        keyAddedBalances[pointer] = updatedBalance;
        emit IBaseModule.KeyAddedBalanceChanged(
            nodeOperatorId,
            keyIndex,
            updatedBalance
        );
    }

    function _keyPointer(
        uint256 nodeOperatorId,
        uint256 keyIndex
    ) private pure returns (uint256) {
        return (nodeOperatorId << 128) | keyIndex;
    }

    function _keyAddedBalanceCap() private pure returns (uint256) {
        return
            WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE -
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;
    }
}
