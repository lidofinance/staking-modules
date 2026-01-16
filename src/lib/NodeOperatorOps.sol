// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "../interfaces/IBaseModule.sol";
import { FORCED_TARGET_LIMIT_MODE_ID } from "../interfaces/IStakingModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

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
