// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "../interfaces/IBaseModule.sol";
import { ExitPenaltyInfo } from "../interfaces/IExitPenalties.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { KeyPointerLib } from "./KeyPointerLib.sol";
import { SigningKeys } from "./SigningKeys.sol";

/// @dev External deployment-linked library that finalizes validators without
///      deriving penalties or fees from validator balances.
library FlatPenaltyWithdrawalProcessor {
    /// @dev Processes terminal validator reports using flat withdrawal obligations.
    /// @param validatorInfos Validator withdrawal reports to process.
    /// @param slashed Whether the batch was submitted through the slashed-withdrawal path.
    /// @param $ Base module storage.
    /// @return touchedOperatorIds Compact list of affected Node Operator IDs.
    /// @return trackedBalanceDecreases Allocated balances to remove for the affected keys.
    /// @return touchedCount Number of populated entries in both returned arrays.
    function processBatch(
        WithdrawnValidatorInfo[] calldata validatorInfos,
        bool slashed,
        ModuleLinearStorage.BaseModuleStorage storage $
    )
        external
        returns (uint256[] memory touchedOperatorIds, uint256[] memory trackedBalanceDecreases, uint256 touchedCount)
    {
        touchedOperatorIds = new uint256[](validatorInfos.length);
        trackedBalanceDecreases = new uint256[](validatorInfos.length);

        for (uint256 i; i < validatorInfos.length; ++i) {
            WithdrawnValidatorInfo calldata info = validatorInfos[i];
            if (info.nodeOperatorId >= $.nodeOperatorsCount) revert IBaseModule.NodeOperatorDoesNotExist();

            uint256 pointer = KeyPointerLib.keyPointer(info.nodeOperatorId, info.keyIndex);
            if ($.isValidatorWithdrawn[pointer]) continue;
            if (info.isSlashed != slashed) revert IBaseModule.InvalidWithdrawnValidatorInfo();
            // A reported slashing must be resolved through the dedicated slashed-withdrawal path.
            if ($.isValidatorSlashed[pointer] && !slashed) revert IBaseModule.InvalidWithdrawnValidatorInfo();
            if (!$.isValidatorSlashed[pointer] && slashed) revert IBaseModule.SlashingPenaltyIsNotApplicable();
            if (info.slashingPenalty != 0 && !slashed) revert IBaseModule.InvalidWithdrawnValidatorInfo();

            NodeOperator storage no = $.nodeOperators[info.nodeOperatorId];
            if (info.keyIndex >= no.totalDepositedKeys) revert IBaseModule.SigningKeysInvalidOffset();

            unchecked {
                ++no.totalWithdrawnKeys;
            }

            bytes memory pubkey = SigningKeys.loadKeys(info.nodeOperatorId, info.keyIndex, 1);
            _fulfillExitObligations(info, pubkey);

            $.isValidatorWithdrawn[pointer] = true;
            if (slashed) _resolveSlashing($, info.nodeOperatorId);

            touchedOperatorIds[touchedCount] = info.nodeOperatorId;
            trackedBalanceDecreases[touchedCount] = $.keyAllocatedBalance[pointer];
            unchecked {
                ++touchedCount;
            }

            emit IBaseModule.ValidatorWithdrawn({
                nodeOperatorId: info.nodeOperatorId,
                keyIndex: info.keyIndex,
                exitBalance: info.exitBalance,
                slashingPenalty: info.slashingPenalty,
                pubkey: pubkey
            });
        }
    }

    function _fulfillExitObligations(WithdrawnValidatorInfo calldata info, bytes memory pubkey) private {
        ExitPenaltyInfo memory penaltyInfo = IBaseModule(address(this)).EXIT_PENALTIES().getExitPenaltyInfo(
            info.nodeOperatorId,
            pubkey
        );

        // The reported slashing penalty is an absolute amount and is zero for regular withdrawals.
        // For slashed reports, zero is an explicit committee decision and does not trigger a balance-derived fallback.
        uint256 penaltySum = info.slashingPenalty;
        uint256 feeSum;

        // Curated strikes obligations are flat amounts and do not scale with the validator balance.
        if (penaltyInfo.strikesPenalty.isValue) {
            penaltySum += penaltyInfo.strikesPenalty.value;
        }
        // The EL withdrawal request fee is taken when the validator exited due to strikes. Otherwise, the fee has
        // already been paid by the Node Operator upon withdrawal trigger, or it is a DAO decision to withdraw the
        // validator.
        if (penaltyInfo.strikesPenalty.isValue && penaltyInfo.elWithdrawalRequestFee.value != 0) {
            feeSum += penaltyInfo.elWithdrawalRequestFee.value;
        }

        IAccounting accounting = IBaseModule(address(this)).ACCOUNTING();

        // Confiscate penalties first to prioritize compensations for the stETH holders.
        bool penaltyCovered = true;
        if (penaltySum != 0) penaltyCovered = accounting.penalize(info.nodeOperatorId, penaltySum);

        // Charge fees second to avoid charging fees if the penalty is not covered,
        // as the fees are meant to cover the costs of processing the withdrawal incurred by the protocol maintainers.
        // stETH holders should have first priority to be compensated, so the fees are charged only if the penalty is covered.
        if (feeSum != 0 && penaltyCovered) accounting.chargeFee(info.nodeOperatorId, feeSum);
    }

    function _resolveSlashing(ModuleLinearStorage.BaseModuleStorage storage $, uint256 nodeOperatorId) private {
        uint256 unresolved = $.unresolvedSlashedValidators[nodeOperatorId];
        // Keep the decrement saturating for compatibility with slashing records that were not counted.
        // NOTE: The counter is per Node Operator, so such a record can resolve another outstanding slashing.
        if (unresolved == 0) return;

        unchecked {
            --unresolved;
        }
        $.unresolvedSlashedValidators[nodeOperatorId] = unresolved;
        emit IBaseModule.UnresolvedSlashedValidatorsCountChanged(nodeOperatorId, unresolved);
    }
}
