// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator } from "../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";
import { KeyPointerLib } from "./KeyPointerLib.sol";

/// @dev Internal primitives for key balances, operator extra balances, and total module stake accounting.
library StakeTracker {
    /// @dev Increases tracked operator extra balance and total extra stake by the given delta.
    function increaseOperatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId,
        uint256 incrementWei
    ) internal {
        if (incrementWei == 0) return;

        _setOperatorBalance($, operatorId, $.operatorBalances[operatorId] + incrementWei);
        $.totalExtraStake += incrementWei;
    }

    /// @dev Decreases tracked operator extra balance and total extra stake by the given delta.
    function decreaseOperatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId,
        uint256 decrementWei
    ) internal {
        if (decrementWei == 0) return;

        _setOperatorBalance($, operatorId, $.operatorBalances[operatorId] - decrementWei);
        $.totalExtraStake -= decrementWei;
    }

    /// @dev Replaces a key's allocated balance and applies the same delta to operator and module aggregates.
    function setKeyAllocatedBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId,
        uint256 keyIndex,
        uint256 balanceWei
    ) internal {
        if (balanceWei > ValidatorBalanceLimits.MAX_EXTRA_BALANCE) revert IBaseModule.InvalidInput();

        uint256 pointer = KeyPointerLib.keyPointer(operatorId, keyIndex);
        uint256 oldBalance = $.keyAllocatedBalance[pointer];
        if (oldBalance == balanceWei) return;

        $.keyAllocatedBalance[pointer] = balanceWei;
        emit IBaseModule.KeyAllocatedBalanceChanged(operatorId, keyIndex, balanceWei);

        if (oldBalance < balanceWei) {
            increaseOperatorBalance($, operatorId, balanceWei - oldBalance);
        } else {
            decreaseOperatorBalance($, operatorId, oldBalance - balanceWei);
        }
    }

    /// @dev Applies a top-up to per-key allocated balance and returns the increment that fits under the key cap.
    ///      Does not update operator or module aggregates; the caller must apply the returned increment separately.
    function applyKeyTopUp(
        mapping(uint256 => uint256) storage keyAllocatedBalance,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 incrementWei
    ) internal returns (uint256 appliedIncrementWei) {
        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        uint256 oldAllocated = keyAllocatedBalance[pointer];
        uint256 updated = Math.min(ValidatorBalanceLimits.MAX_EXTRA_BALANCE, oldAllocated + incrementWei);
        unchecked {
            appliedIncrementWei = updated - oldAllocated;
        }
        if (appliedIncrementWei > 0) {
            keyAllocatedBalance[pointer] = updated;
            emit IBaseModule.KeyAllocatedBalanceChanged(nodeOperatorId, keyIndex, updated);
        }
    }

    /// @dev Returns the total tracked stake for the given operator: base 32 ETH per active validator plus stored extra.
    function getOperatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId
    ) internal view returns (uint256) {
        return
            _activeValidatorsCount($.nodeOperators[operatorId]) *
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE +
            $.operatorBalances[operatorId];
    }

    /// @dev Returns the total tracked module stake: base 32 ETH per active validator plus stored extra.
    function getTotalModuleStake(ModuleLinearStorage.BaseModuleStorage storage $) internal view returns (uint256) {
        unchecked {
            return _activeModuleValidatorsCount($) * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + $.totalExtraStake;
        }
    }

    function _setOperatorBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId,
        uint256 balanceWei
    ) private {
        if ($.operatorBalances[operatorId] == balanceWei) return;
        $.operatorBalances[operatorId] = balanceWei;
        emit IBaseModule.NodeOperatorBalanceUpdated(operatorId, getOperatorBalance($, operatorId));
    }

    function _activeValidatorsCount(NodeOperator storage no) private view returns (uint256) {
        unchecked {
            return no.totalDepositedKeys - no.totalWithdrawnKeys;
        }
    }

    function _activeModuleValidatorsCount(
        ModuleLinearStorage.BaseModuleStorage storage $
    ) private view returns (uint256) {
        unchecked {
            return uint256($.totalDepositedValidators) - $.totalWithdrawnValidators;
        }
    }
}
