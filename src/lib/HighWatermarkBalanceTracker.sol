// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { KeyPointerLib } from "./KeyPointerLib.sol";
import { StakeTracker } from "./StakeTracker.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";

/// @dev Applies high-watermark balance reporting: only a new proven maximum advances the tracked balance.
library HighWatermarkBalanceTracker {
    /// @dev Raises confirmed key balance and also raises allocated balance when the confirmed value overtakes it.
    function updateValidatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 currentBalanceWei
    ) external {
        if (nodeOperatorId >= $.nodeOperatorsCount) revert IBaseModule.NodeOperatorDoesNotExist();
        if (keyIndex >= $.nodeOperators[nodeOperatorId].totalDepositedKeys) {
            revert IBaseModule.SigningKeysInvalidOffset();
        }

        uint256 newConfirmed = ValidatorBalanceLimits.normalizeExtraBalance(currentBalanceWei);

        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        if ($.isValidatorWithdrawn[pointer]) revert IBaseModule.UnreportableBalance();

        uint256 oldConfirmed = $.keyConfirmedBalance[pointer];
        // Balances at or below the activation balance normalize to zero and, like any other value that does not
        // advance the high watermark, are not reportable.
        if (newConfirmed <= oldConfirmed) revert IBaseModule.UnreportableBalance();

        uint256 allocatedIncrementWei;
        uint256 oldAllocated = $.keyAllocatedBalance[pointer];
        if (oldAllocated < newConfirmed) {
            allocatedIncrementWei = newConfirmed - oldAllocated;
            $.keyAllocatedBalance[pointer] = newConfirmed;
            emit IBaseModule.KeyAllocatedBalanceChanged(nodeOperatorId, keyIndex, newConfirmed);
        }

        $.keyConfirmedBalance[pointer] = newConfirmed;
        emit IBaseModule.KeyConfirmedBalanceChanged(nodeOperatorId, keyIndex, newConfirmed);

        StakeTracker.increaseOperatorBalance($, nodeOperatorId, allocatedIncrementWei);
    }
}
