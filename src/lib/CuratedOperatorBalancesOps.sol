// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ICuratedModule } from "../interfaces/ICuratedModule.sol";

/// @dev The library is used to reduce CuratedModule bytecode size and keep balance ops centralized.
library CuratedOperatorBalancesOps {
    function applyReportedBalances(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256 nodeOperatorsCount,
        uint256[] calldata operatorIds,
        uint256[] calldata totalBalancesGwei
    ) external {
        uint256 operatorsCount = operatorIds.length;
        if (operatorsCount != totalBalancesGwei.length) {
            revert IBaseModule.InvalidInput();
        }

        for (uint256 i; i < operatorsCount; ++i) {
            uint256 operatorId = operatorIds[i];
            if (operatorId >= nodeOperatorsCount) revert IBaseModule.NodeOperatorDoesNotExist();
            _setBalance(operatorBalances, operatorId, totalBalancesGwei[i] * 1 gwei);
        }
    }

    function increaseByAllocations(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256[] calldata uniqueOperatorIds,
        uint256[] calldata perOperatorIncrements
    ) external {
        for (uint256 i; i < uniqueOperatorIds.length; ++i) {
            uint256 operatorId = uniqueOperatorIds[i];
            uint256 increment = perOperatorIncrements[operatorId];
            if (increment == 0) continue;
            _setBalance(operatorBalances, operatorId, operatorBalances[operatorId] + increment);
        }
    }

    function increaseBalance(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256 operatorId,
        uint256 incrementWei
    ) external {
        _setBalance(operatorBalances, operatorId, operatorBalances[operatorId] + incrementWei);
    }

    function _setBalance(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256 operatorId,
        uint256 balanceWei
    ) private {
        operatorBalances[operatorId] = balanceWei;
        emit ICuratedModule.NodeOperatorBalanceUpdated(operatorId, balanceWei);
    }
}
