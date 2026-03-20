// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator } from "../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";
import { KeyPointerLib } from "./KeyPointerLib.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";

/// @dev Centralizes tracked stake updates for operator extra balances, total extra stake, and key balance transitions.
library StakeTracker {
    using TransientUintUintMapLib for TransientUintUintMap;

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

    /// @dev Applies per-key top-up allocations, updates key allocated balances, and aggregates stake deltas per operator.
    function increaseKeyBalances(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata allocations
    ) external {
        uint256[] memory allocatedOperatorIds = new uint256[](operatorIds.length);
        uint256[] memory increments = new uint256[](operatorIds.length);
        TransientUintUintMap operatorIndexes = TransientUintUintMapLib.create();
        uint256 count;

        for (uint256 i; i < allocations.length; ++i) {
            uint256 allocationWei = allocations[i];
            if (allocationWei == 0) continue;
            _increaseKeyAllocatedBalance($.keyAllocatedBalance, operatorIds[i], keyIndices[i], allocationWei);

            uint256 operatorIndex = operatorIndexes.get(operatorIds[i]);
            if (operatorIndex == 0) {
                allocatedOperatorIds[count] = operatorIds[i];
                increments[count] = allocationWei;
                operatorIndexes.set(operatorIds[i], count + 1);
                unchecked {
                    ++count;
                }
                continue;
            }

            unchecked {
                increments[operatorIndex - 1] += allocationWei;
            }
        }

        for (uint256 i; i < count; ++i) {
            increaseOperatorBalance($, allocatedOperatorIds[i], increments[i]);
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
            return
                (uint256($.totalDepositedValidators) - $.totalWithdrawnValidators) *
                ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE +
                $.totalExtraStake;
        }
    }

    /// @dev Raises confirmed key balance and also raises allocated balance when the confirmed value overtakes it.
    ///      Returns the implied operator/module stake delta via the internal helper path.
    ///      Decreases for active validators are intentionally not applied here: the tracked extra stays at the
    ///      highest observed level until withdrawal reporting settles any loss for penalty accounting.
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

        uint256 allocatedIncrementWei = _increaseKeyConfirmedBalance({
            $: $,
            nodeOperatorId: nodeOperatorId,
            keyIndex: keyIndex,
            incrementWei: newConfirmed - oldConfirmed
        });
        increaseOperatorBalance($, nodeOperatorId, allocatedIncrementWei);
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

    function _increaseKeyConfirmedBalance(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 incrementWei
    ) private returns (uint256 allocatedIncrementWei) {
        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        uint256 updated = $.keyConfirmedBalance[pointer] + incrementWei;
        uint256 oldAllocated = $.keyAllocatedBalance[pointer];
        if (oldAllocated < updated) {
            allocatedIncrementWei = updated - oldAllocated;
        }

        $.keyConfirmedBalance[pointer] = updated;
        emit IBaseModule.KeyConfirmedBalanceChanged(nodeOperatorId, keyIndex, updated);

        if (allocatedIncrementWei != 0) {
            $.keyAllocatedBalance[pointer] = updated;
            emit IBaseModule.KeyAllocatedBalanceChanged(nodeOperatorId, keyIndex, updated);
        }
    }

    function _increaseKeyAllocatedBalance(
        mapping(uint256 => uint256) storage keyAllocatedBalance,
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 incrementWei
    ) private {
        uint256 pointer = KeyPointerLib.keyPointer(nodeOperatorId, keyIndex);
        uint256 updated = Math.min(
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            keyAllocatedBalance[pointer] + incrementWei
        );
        keyAllocatedBalance[pointer] = updated;
        emit IBaseModule.KeyAllocatedBalanceChanged(nodeOperatorId, keyIndex, updated);
    }

    function _activeValidatorsCount(NodeOperator storage no) private view returns (uint256) {
        unchecked {
            return no.totalDepositedKeys - no.totalWithdrawnKeys;
        }
    }
}
