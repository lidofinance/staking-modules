// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule, NodeOperator } from "../interfaces/IBaseModule.sol";
import { ICuratedModule } from "../interfaces/ICuratedModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { KeyPointerLib } from "./KeyPointerLib.sol";
import { StakeTracker } from "./StakeTracker.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";

/// @dev Applies slot-ordered balance checkpoints with an explicit balance-decrease policy.
library CheckpointBalanceTracker {
    function updateValidatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 actualBalanceWei,
        uint64 balanceSlot,
        bool allowDecrease
    ) external {
        if (nodeOperatorId >= $.nodeOperatorsCount) revert IBaseModule.NodeOperatorDoesNotExist();

        NodeOperator storage no = $.nodeOperators[nodeOperatorId];
        if (keyIndex >= no.totalDepositedKeys) revert IBaseModule.SigningKeysInvalidOffset();

        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        if ($.isValidatorWithdrawn[pointer] || $.isValidatorSlashed[pointer]) {
            revert IBaseModule.UnreportableBalance();
        }
        if (balanceSlot <= $.lastBalanceUpdateSlot[pointer]) revert ICuratedModule.StaleBalanceUpdate();

        uint256 normalizedBalance = ValidatorBalanceLimits.normalizeExtraBalance(actualBalanceWei);
        if (!allowDecrease && normalizedBalance < $.keyAllocatedBalance[pointer]) {
            revert ICuratedModule.BalanceDecreaseNotAllowed();
        }

        if (normalizedBalance == $.keyAllocatedBalance[pointer]) revert IBaseModule.UnreportableBalance();

        $.lastBalanceUpdateSlot[pointer] = balanceSlot;
        StakeTracker.setKeyAllocatedBalance($, nodeOperatorId, keyIndex, normalizedBalance);

        emit ICuratedModule.ValidatorBalanceSynced(nodeOperatorId, keyIndex, balanceSlot, normalizedBalance);
    }
}
