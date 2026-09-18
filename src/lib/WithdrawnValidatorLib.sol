// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "../interfaces/IBaseModule.sol";
import { ExitPenaltyInfo } from "../interfaces/IExitPenalties.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { KeyPointerLib } from "./KeyPointerLib.sol";
import { SigningKeys } from "./SigningKeys.sol";
import { ValidatorBalanceLimits } from "./ValidatorBalanceLimits.sol";

/// @dev External deployment-linked library that processes withdrawn validators.
library WithdrawnValidatorLib {
    /// @dev Balance-derived inputs for penalty calculation. Scaling applies to penalties expressed at the base
    ///      validator balance; explicitly supplied loss amounts are already calculated and are added without scaling.
    struct PenaltyBasis {
        uint256 strikesMultiplier;
        uint256 balanceLoss;
    }

    uint256 public constant PENALTY_QUOTIENT = 1 ether;
    /// @dev Acts as the denominator to calculate the scaled penalty.
    uint256 public constant PENALTY_SCALE = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT;

    /// @dev Processes terminal validator reports.
    /// @param validatorInfos Validator withdrawal reports to process.
    /// @param slashed Whether the batch was submitted through the slashed-withdrawal path.
    /// @param useConfirmedBalance Whether to use confirmed balance and charge balance deficits (CSM).
    ///        Otherwise, use allocated balance for penalty scaling without charging deficits (Curated).
    /// @param $ Base module storage.
    /// @return touchedOperatorIds Compact list of affected Node Operator IDs.
    /// @return trackedBalanceDecreases Allocated balances to remove for the affected keys.
    /// @return touchedCount Number of populated entries in both returned arrays.
    function processBatch(
        WithdrawnValidatorInfo[] calldata validatorInfos,
        bool slashed,
        bool useConfirmedBalance,
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

            uint256 extraBalance = useConfirmedBalance
                ? $.keyConfirmedBalance[pointer]
                : $.keyAllocatedBalance[pointer];
            PenaltyBasis memory penaltyBasis = _getPenaltyBasis(info, extraBalance, useConfirmedBalance);
            _processValidator($.nodeOperators[info.nodeOperatorId], info, penaltyBasis);

            $.isValidatorWithdrawn[pointer] = true;
            if (slashed) _resolveSlashing($, info.nodeOperatorId);
            touchedOperatorIds[touchedCount] = info.nodeOperatorId;
            trackedBalanceDecreases[touchedCount] = $.keyAllocatedBalance[pointer];
            unchecked {
                ++touchedCount;
            }
        }
    }

    /// @dev Acts as the numerator to calculate the scaled penalty.
    /// @dev Expects the `balance` value between MIN_ACTIVATION_BALANCE and MAX_EFFECTIVE_BALANCE.
    function _getPenaltyMultiplier(uint256 balance) internal pure returns (uint256 penaltyMultiplier) {
        penaltyMultiplier = balance / PENALTY_QUOTIENT;
    }

    function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256) {
        return (penalty * multiplier) / PENALTY_SCALE;
    }

    function _processValidator(
        NodeOperator storage no,
        WithdrawnValidatorInfo calldata info,
        PenaltyBasis memory penaltyBasis
    ) private {
        if (info.keyIndex >= no.totalDepositedKeys) revert IBaseModule.SigningKeysInvalidOffset();

        unchecked {
            ++no.totalWithdrawnKeys;
        }

        bytes memory pubkey = SigningKeys.loadKeys(info.nodeOperatorId, info.keyIndex, 1);
        ExitPenaltyInfo memory penaltyInfo = IBaseModule(address(this)).EXIT_PENALTIES().getExitPenaltyInfo(
            info.nodeOperatorId,
            pubkey
        );
        uint256 penaltySum;

        if (penaltyInfo.strikesPenalty.isValue) {
            // NOTE: This might overflow for a recorded penalty greater than about 2^245.
            penaltySum = _scalePenaltyByMultiplier(penaltyInfo.strikesPenalty.value, penaltyBasis.strikesMultiplier);
        }

        if (info.isSlashed && info.slashingPenalty > 0) {
            // The explicitly supplied slashing penalty already accounts for the losses and is not scaled again.
            penaltySum += info.slashingPenalty;
        } else {
            // If an exact slashing penalty is absent, the balance loss is a best-effort permissionless fallback.
            // Curated processing leaves the balance loss at zero, making zero an explicit committee decision.
            penaltySum += penaltyBasis.balanceLoss;
        }

        if (penaltySum != 0) IBaseModule(address(this)).ACCOUNTING().penalize(info.nodeOperatorId, penaltySum);

        // Keep the event before withdrawal finalization and slashing resolution to preserve the deployed ordering.
        emit IBaseModule.ValidatorWithdrawn({
            nodeOperatorId: info.nodeOperatorId,
            keyIndex: info.keyIndex,
            exitBalance: info.exitBalance,
            slashingPenalty: info.slashingPenalty,
            pubkey: pubkey
        });
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

    function _getPenaltyBasis(
        WithdrawnValidatorInfo calldata info,
        uint256 extraBalance,
        bool useConfirmedBalance
    ) private pure returns (PenaltyBasis memory penaltyBasis) {
        uint256 balance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + extraBalance;
        if (useConfirmedBalance) {
            // For slashed validator this value should reflect pre-slashing, hence non-zero balance.
            // For non-slashed validator it will reflect the withdrawal amount, hence it cannot be zero either.
            if (info.exitBalance == 0) revert IBaseModule.ZeroExitBalance();

            if (info.exitBalance < balance) penaltyBasis.balanceLoss = balance - info.exitBalance;
            balance = Math.max(info.exitBalance, balance);
        }

        // Curated uses the allocation estimate before finalization, irrespective of the withdrawal amount.
        // Proof ordering can affect this estimate and the final penalty, but scaling is capped at 2048 ETH.
        penaltyBasis.strikesMultiplier = _getPenaltyMultiplier(
            Math.min(balance, ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE)
        );
    }
}
