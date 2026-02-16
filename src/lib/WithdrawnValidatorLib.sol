// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "../interfaces/IBaseModule.sol";
import { ExitPenaltyInfo } from "../interfaces/IExitPenalties.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

import { SigningKeys } from "./SigningKeys.sol";

/// @dev A library to extract a part of the code from the the CSModule contract.
library WithdrawnValidatorLib {
    uint256 public constant MAX_EFFECTIVE_BALANCE = 2048 ether;
    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;

    uint256 public constant PENALTY_QUOTIENT = 1 ether;
    /// @dev Acts as the denominator to calculate the scaled penalty.
    uint256 public constant PENALTY_SCALE = MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT;

    function process(
        NodeOperator storage no,
        WithdrawnValidatorInfo calldata validatorInfo,
        uint256 keyAddedBalance
    ) external returns (bool penaltyCovered) {
        if (validatorInfo.slashingPenalty > 0 && !validatorInfo.isSlashed) {
            revert IBaseModule.InvalidWithdrawnValidatorInfo();
        }

        // For slashed validator this value should reflect pre-slashing, hence non-zero balance.
        // For non-slashed validator it will reflect the withdrawal amount, hence it cannot be zero either.
        if (validatorInfo.exitBalance == 0) revert IBaseModule.ZeroExitBalance();
        if (validatorInfo.keyIndex >= no.totalDepositedKeys) revert IBaseModule.SigningKeysInvalidOffset();

        unchecked {
            ++no.totalWithdrawnKeys;
        }

        bytes memory pubkey = SigningKeys.loadKeys(validatorInfo.nodeOperatorId, validatorInfo.keyIndex, 1);

        ExitPenaltyInfo memory penaltyInfo = IBaseModule(address(this)).EXIT_PENALTIES().getExitPenaltyInfo(
            validatorInfo.nodeOperatorId,
            pubkey
        );

        penaltyCovered = _fulfillExitObligations(validatorInfo, penaltyInfo, keyAddedBalance);

        emit IBaseModule.ValidatorWithdrawn({
            nodeOperatorId: validatorInfo.nodeOperatorId,
            keyIndex: validatorInfo.keyIndex,
            exitBalance: validatorInfo.exitBalance,
            slashingPenalty: validatorInfo.slashingPenalty,
            pubkey: pubkey
        });
    }

    // NOTE: The function might revert if the penalty recorded in the `penaltyInfo` is large enough. As of now, it
    // should be greater than 2^245, which is about 5.6 * 10^55 ethers.
    function _fulfillExitObligations(
        WithdrawnValidatorInfo calldata validatorInfo,
        ExitPenaltyInfo memory penaltyInfo,
        uint256 keyAddedBalance
    ) internal returns (bool penaltyCovered) {
        bool chargeElWithdrawalRequestFee = false;

        uint256 penaltyMultiplier = _getPenaltyMultiplier(validatorInfo);
        uint256 penaltySum;
        uint256 feeSum;

        if (penaltyInfo.delayFee.isValue) {
            feeSum = _scalePenaltyByMultiplier(penaltyInfo.delayFee.value, penaltyMultiplier);
            chargeElWithdrawalRequestFee = true;
        }
        if (penaltyInfo.strikesPenalty.isValue) {
            penaltySum = _scalePenaltyByMultiplier(penaltyInfo.strikesPenalty.value, penaltyMultiplier);
            chargeElWithdrawalRequestFee = true;
        }

        // The EL withdrawal request fee is taken when either a delay was reported or the validator exited due to
        // strikes. Otherwise, the fee has already been paid by the node operator upon withdrawal trigger, or it is
        // a DAO decision to withdraw the validator before the withdrawal request becomes delayed.
        if (chargeElWithdrawalRequestFee && penaltyInfo.elWithdrawalRequestFee.value != 0) {
            // EL withdrawal request fee is not scaled because sending a withdrawal request for a validator does
            // not depend on the size of a validator.
            feeSum += penaltyInfo.elWithdrawalRequestFee.value;
        }

        uint256 minExpectedBalance = MIN_ACTIVATION_BALANCE + keyAddedBalance;
        if (validatorInfo.isSlashed) {
            // Slashing penalty doesn't scale because all the losses are already accounted.
            penaltySum += validatorInfo.slashingPenalty;
        } else if (validatorInfo.exitBalance < minExpectedBalance) {
            penaltySum += minExpectedBalance - validatorInfo.exitBalance;
        }

        IAccounting accounting = IBaseModule(address(this)).ACCOUNTING();

        penaltyCovered = true;

        // Confiscate penalties first to prioritize compensations for the stETH holders.
        if (penaltySum > 0) {
            penaltyCovered = accounting.penalize(validatorInfo.nodeOperatorId, penaltySum);
        }

        // Charge fees second to avoid charging fees if the penalty is not covered,
        // as the fees are meant to cover the costs of processing the withdrawal incurred by the protocol maintainers.
        // stETH holders should have first priority to be compensated, so the fees are charged only if the penalty is covered.
        if (feeSum > 0) accounting.chargeFee(validatorInfo.nodeOperatorId, feeSum);
    }

    /// @dev Acts as the numerator to calculate the scaled penalty.
    function _getPenaltyMultiplier(
        WithdrawnValidatorInfo memory validatorInfo
    ) internal pure returns (uint256 penaltyMultiplier) {
        uint256 exitBalance = validatorInfo.exitBalance;
        exitBalance = Math.max(MIN_ACTIVATION_BALANCE, exitBalance);
        exitBalance = Math.min(MAX_EFFECTIVE_BALANCE, exitBalance);
        penaltyMultiplier = exitBalance / PENALTY_QUOTIENT;
    }

    function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256) {
        return (penalty * multiplier) / PENALTY_SCALE;
    }
}
