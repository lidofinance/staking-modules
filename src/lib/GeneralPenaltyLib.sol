// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ICSModule } from "../interfaces/ICSModule.sol";
import { ICSAccounting } from "../interfaces/ICSAccounting.sol";

/// Library for General Penalty logic
/// @dev the only use of this to be a library is to save CSModule contract size via delegatecalls
interface IGeneralPenalty {
    event ELRewardsStealingPenaltyReported(
        uint256 indexed nodeOperatorId,
        bytes32 proposedBlockHash,
        uint256 stolenAmount
    );
    event ELRewardsStealingPenaltyCancelled(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event ELRewardsStealingPenaltyCompensated(
        uint256 indexed nodeOperatorId,
        uint256 amount
    );
    event ELRewardsStealingPenaltySettled(uint256 indexed nodeOperatorId);
}

library GeneralPenalty {
    function reportELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        bytes32 blockHash,
        uint256 amount
    ) external {
        if (amount == 0) {
            revert ICSModule.InvalidAmount();
        }

        ICSModule module = ICSModule(address(this));
        ICSAccounting accounting = module.ACCOUNTING();

        uint256 curveId = accounting.getBondCurveId(nodeOperatorId);
        uint256 additionalFine = module
            .PARAMETERS_REGISTRY()
            .getElRewardsStealingAdditionalFine(curveId);

        accounting.lockBondETH(nodeOperatorId, amount + additionalFine);

        emit IGeneralPenalty.ELRewardsStealingPenaltyReported(
            nodeOperatorId,
            blockHash,
            amount
        );

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function cancelELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        uint256 amount
    ) external {
        ICSModule module = ICSModule(address(this));
        ICSAccounting accounting = module.ACCOUNTING();

        accounting.releaseLockedBondETH(nodeOperatorId, amount);

        emit IGeneralPenalty.ELRewardsStealingPenaltyCancelled(
            nodeOperatorId,
            amount
        );

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }

    function settleELRewardsStealingPenalty(
        uint256 nodeOperatorId,
        uint256 maxAmount
    ) external returns (bool) {
        ICSAccounting accounting = ICSModule(address(this)).ACCOUNTING();
        uint256 locked = accounting.getActualLockedBond(nodeOperatorId);
        if (locked == 0 || locked > maxAmount) {
            return false; // skip this NO if the locked bond is greater than the max amount or there is no locked bond
        }

        accounting.settleLockedBondETH(nodeOperatorId);
        emit IGeneralPenalty.ELRewardsStealingPenaltySettled(nodeOperatorId);

        return true;
    }

    function compensateELRewardsStealingPenalty(
        uint256 nodeOperatorId
    ) external {
        ICSModule module = ICSModule(address(this));
        ICSAccounting accounting = module.ACCOUNTING();

        accounting.compensateLockedBondETH{ value: msg.value }(nodeOperatorId);

        emit IGeneralPenalty.ELRewardsStealingPenaltyCompensated(
            nodeOperatorId,
            msg.value
        );

        module.updateDepositableValidatorsCount(nodeOperatorId);
    }
}
