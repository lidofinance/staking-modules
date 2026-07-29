// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

/// Library for General Penalty logic
/// @dev External deployment-linked library used by BaseModule-compatible modules
///      to save contract size via delegatecalls.
library GeneralPenalty {
    function reportGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        bytes32 penaltyType,
        uint256 amount,
        string calldata details
    ) external {
        if (penaltyType == bytes32(0)) revert IBaseModule.ZeroPenaltyType();

        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        uint256 curveId = accounting.getBondCurveId(nodeOperatorId);
        uint256 additionalFine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(curveId);

        uint256 totalAmount = amount + additionalFine;

        if (totalAmount == 0) revert IBaseModule.InvalidAmount();

        accounting.lockBond(nodeOperatorId, totalAmount);

        emit IBaseModule.GeneralDelayedPenaltyReported({
            nodeOperatorId: nodeOperatorId,
            penaltyType: penaltyType,
            amount: amount,
            additionalFine: additionalFine,
            details: details
        });

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount) external {
        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        if (!accounting.releaseLockedBond(nodeOperatorId, amount)) return;

        emit IBaseModule.GeneralDelayedPenaltyCancelled(nodeOperatorId, amount);

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function settleGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 bondLockNonce) external returns (bool) {
        IAccounting accounting = IBaseModule(address(this)).ACCOUNTING();

        uint256 settledAmount = accounting.settleLockedBond(nodeOperatorId, bondLockNonce);
        if (settledAmount == 0) return false;

        emit IBaseModule.GeneralDelayedPenaltySettled(nodeOperatorId, settledAmount);

        return true;
    }

    function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external {
        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        uint256 compensatedAmount = accounting.compensateLockedBond(nodeOperatorId);

        if (compensatedAmount == 0) return;

        emit IBaseModule.GeneralDelayedPenaltyCompensated(nodeOperatorId, compensatedAmount);

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }
}
