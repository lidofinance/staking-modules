// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "../interfaces/IBaseModule.sol";
import { FORCED_TARGET_LIMIT_MODE_ID } from "../interfaces/IStakingModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { ValidatorCountsReport } from "./ValidatorCountsReport.sol";

/// @dev The library is used to reduce BaseModule bytecode size.
library NodeOperatorOps {
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
        uint64 nodeOperatorsCount,
        uint64 totalExitedValidators,
        bytes calldata nodeOperatorIds,
        bytes calldata exitedValidatorsCounts
    ) external returns (uint64 updatedTotalExitedValidators) {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(
            nodeOperatorIds,
            exitedValidatorsCounts
        );

        updatedTotalExitedValidators = totalExitedValidators;
        for (uint256 i = 0; i < operatorsInReport; ++i) {
            (
                uint256 nodeOperatorId,
                uint256 exitedValidatorsCount
            ) = ValidatorCountsReport.next(
                    nodeOperatorIds,
                    exitedValidatorsCounts,
                    i
                );
            updatedTotalExitedValidators = _updateExitedValidatorsCount({
                nodeOperators: nodeOperators,
                nodeOperatorsCount: nodeOperatorsCount,
                totalExitedValidators: updatedTotalExitedValidators,
                nodeOperatorId: nodeOperatorId,
                exitedValidatorsCount: exitedValidatorsCount,
                allowDecrease: false
            });
        }
    }

    function unsafeUpdateValidatorsCount(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint64 nodeOperatorsCount,
        uint64 totalExitedValidators,
        uint256 nodeOperatorId,
        uint256 exitedValidatorsCount
    ) external returns (uint64 updatedTotalExitedValidators) {
        updatedTotalExitedValidators = _updateExitedValidatorsCount({
            nodeOperators: nodeOperators,
            nodeOperatorsCount: nodeOperatorsCount,
            totalExitedValidators: totalExitedValidators,
            nodeOperatorId: nodeOperatorId,
            exitedValidatorsCount: exitedValidatorsCount,
            allowDecrease: true
        });
    }

    function calculateTotalWithdrawnValidators(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint64 nodeOperatorsCount
    ) external view returns (uint64 totalWithdrawnValidators) {
        for (uint256 i; i < nodeOperatorsCount; ++i) {
            totalWithdrawnValidators += nodeOperators[i].totalWithdrawnKeys;
        }
    }

    /// @dev Update exited validators count for a single Node Operator.
    function _updateExitedValidatorsCount(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint64 nodeOperatorsCount,
        uint64 totalExitedValidators,
        uint256 nodeOperatorId,
        uint256 exitedValidatorsCount,
        bool allowDecrease
    ) private returns (uint64 updatedTotalExitedValidators) {
        if (nodeOperatorId >= nodeOperatorsCount) {
            revert IBaseModule.NodeOperatorDoesNotExist();
        }

        NodeOperator storage no = nodeOperators[nodeOperatorId];
        uint32 totalExitedKeys = no.totalExitedKeys;
        if (exitedValidatorsCount == totalExitedKeys) {
            return totalExitedValidators;
        }
        if (exitedValidatorsCount > no.totalDepositedKeys) {
            revert IBaseModule.ExitedKeysHigherThanTotalDeposited();
        }
        if (!allowDecrease && exitedValidatorsCount < totalExitedKeys) {
            revert IBaseModule.ExitedKeysDecrease();
        }

        unchecked {
            // @dev Invariant sum(no.totalExitedKeys for no in nos) == totalExitedValidators.
            // `totalExitedValidators` accumulates the same uint32 per-operator counts, so pushing
            // the new value through uint64 preserves the exact result.
            // forge-lint: disable-next-item(unsafe-typecast)
            updatedTotalExitedValidators = uint64(
                uint256(totalExitedValidators) -
                    totalExitedKeys +
                    exitedValidatorsCount
            );
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
}
