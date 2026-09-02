// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { KeyPointerLib } from "./KeyPointerLib.sol";
import { StakeTracker } from "./StakeTracker.sol";

/// @dev Applies the confirmed-balance reporting policy used by the current module implementations.
///      Confirmed balances are monotonic. Active balance decreases remain unaccounted until withdrawal processing.
library ConfirmedBalanceTracker {
    /// @dev Raises confirmed key balance and also raises allocated balance when the confirmed value overtakes it.
    function reportValidatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 newConfirmed
    ) internal {
        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        if ($.isValidatorWithdrawn[pointer]) revert IBaseModule.UnreportableBalance();

        uint256 oldConfirmed = $.keyConfirmedBalance[pointer];
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
