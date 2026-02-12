// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ICuratedModule } from "../interfaces/ICuratedModule.sol";
import { ValidatorCountsReport } from "./ValidatorCountsReport.sol";

/// @dev The library is used to reduce CuratedModule bytecode size and keep balance ops centralized.
library CuratedOperatorBalancesOps {
    function applyReportedBalances(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256 nodeOperatorsCount,
        bytes calldata operatorIds,
        bytes calldata totalBalancesGwei
    ) external {
        uint256 operatorsInReport = ValidatorCountsReport.safeCountOperators(operatorIds, totalBalancesGwei);

        for (uint256 i; i < operatorsInReport; ++i) {
            (uint256 operatorId, uint256 balanceGwei) = ValidatorCountsReport.next(operatorIds, totalBalancesGwei, i);
            if (operatorId >= nodeOperatorsCount) revert IBaseModule.NodeOperatorDoesNotExist();
            _setBalance(operatorBalances, operatorId, balanceGwei * 1 gwei);
        }
    }

    function increaseByAllocations(
        mapping(uint256 => uint256) storage operatorBalances,
        uint256[] calldata uniqueOperatorIds,
        uint256[] calldata perOperatorIncrements
    ) external {
        for (uint256 i; i < uniqueOperatorIds.length; ++i) {
            uint256 operatorId = uniqueOperatorIds[i];
            uint256 incrementWei = perOperatorIncrements[operatorId];
            if (incrementWei == 0) continue;
            _setBalance(operatorBalances, operatorId, operatorBalances[operatorId] + incrementWei);
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
