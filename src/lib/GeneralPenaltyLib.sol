// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

/// Library for General Penalty logic
/// @dev the only use of this to be a library is to save CSModule contract size via delegatecalls
interface IGeneralPenalty {
    event GeneralDelayedPenaltyReported(
        uint256 indexed nodeOperatorId,
        bytes32 indexed penaltyType,
        uint256 amount,
        uint256 additionalFine,
        string details
    );
    event GeneralDelayedPenaltyCancelled(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event GeneralDelayedPenaltyCompensated(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event GeneralDelayedPenaltySettled(uint256 indexed nodeOperatorId);

    error ZeroPenaltyType();
}

library GeneralPenalty {
    function reportGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        bytes32 penaltyType,
        uint256 amount,
        string calldata details
    ) external {
        if (penaltyType == bytes32(0)) {
            revert IGeneralPenalty.ZeroPenaltyType();
        }

        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        uint256 curveId = accounting.getBondCurveId(nodeOperatorId);
        uint256 additionalFine = module
            .PARAMETERS_REGISTRY()
            .getGeneralDelayedPenaltyAdditionalFine(curveId);

        uint256 totalAmount = amount + additionalFine;

        if (totalAmount == 0) {
            revert IBaseModule.InvalidAmount();
        }

        accounting.lockBondETH(nodeOperatorId, totalAmount);

        emit IGeneralPenalty.GeneralDelayedPenaltyReported({
            nodeOperatorId: nodeOperatorId,
            penaltyType: penaltyType,
            amount: amount,
            additionalFine: additionalFine,
            details: details
        });

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function cancelGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external {
        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        accounting.releaseLockedBondETH(nodeOperatorId, amount);

        emit IGeneralPenalty.GeneralDelayedPenaltyCancelled(
            nodeOperatorId,
            amount
        );

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function settleGeneralDelayedPenalty(
        uint256 nodeOperatorId,
        uint256 maxAmount
    ) external returns (bool) {
        IAccounting accounting = IBaseModule(address(this)).ACCOUNTING();
        uint256 locked = accounting.getActualLockedBond(nodeOperatorId);
        if (locked == 0 || locked > maxAmount) {
            return false; // skip this NO if the locked bond is greater than the max amount or there is no locked bond
        }

        accounting.settleLockedBondETH(nodeOperatorId);
        emit IGeneralPenalty.GeneralDelayedPenaltySettled(nodeOperatorId);

        return true;
    }

    function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external {
        IBaseModule module = IBaseModule(address(this));
        IAccounting accounting = module.ACCOUNTING();

        accounting.compensateLockedBondETH{ value: msg.value }(nodeOperatorId);

        emit IGeneralPenalty.GeneralDelayedPenaltyCompensated(
            nodeOperatorId,
            msg.value
        );

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }
}
