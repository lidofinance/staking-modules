// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule, WithdrawnValidatorInfo } from "../interfaces/IBaseModule.sol";
import { ExitPenaltyInfo } from "../interfaces/IExitPenalties.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";

import { SigningKeys } from "./SigningKeys.sol";

/// @dev A library to extract a part of the code from the the CSModule contract.
library WithdrawnValidatorLib {
    uint256 public constant MAX_EFFECTIVE_BALANCE = 2048 ether;
    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;

    uint256 public constant PENALTY_QUOTIENT = 1 ether;
    /// @dev Acts as the denominator to calculate the scaled penalty.
    uint256 public constant PENALTY_SCALE =
        MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT;

    function process(
        WithdrawnValidatorInfo calldata validatorInfo
    ) external returns (bool bondCoversPenalties) {
        bytes memory pubkey = SigningKeys.loadKeys(
            validatorInfo.nodeOperatorId,
            validatorInfo.keyIndex,
            1
        );

        ExitPenaltyInfo memory penaltyInfo = IBaseModule(address(this))
            .EXIT_PENALTIES()
            .getExitPenaltyInfo(validatorInfo.nodeOperatorId, pubkey);

        bondCoversPenalties = _fulfilExitObligations(
            validatorInfo,
            penaltyInfo
        );

        // solhint-disable-next-line func-named-parameters
        emit IBaseModule.ValidatorWithdrawn(
            validatorInfo.nodeOperatorId,
            validatorInfo.keyIndex,
            validatorInfo.exitBalance,
            validatorInfo.slashingPenalty,
            pubkey
        );
    }

    // NOTE: The function might revert if the penalty recorded in the `penaltyInfo` is large enough. As of now, it
    // should be greater than 2^245, which is about 5.6 * 10^55 ethers.
    function _fulfilExitObligations(
        WithdrawnValidatorInfo calldata validatorInfo,
        ExitPenaltyInfo memory penaltyInfo
    ) internal returns (bool bondCoversPenalties) {
        bool chargeWithdrawalRequestFee = false;

        uint256 penaltyMultiplier = _getPenaltyMultiplier(validatorInfo);
        uint256 penaltySum;
        uint256 feeSum;

        if (penaltyInfo.delayFee.isValue) {
            feeSum = _scalePenaltyByMultiplier(
                penaltyInfo.delayFee.value,
                penaltyMultiplier
            );
            chargeWithdrawalRequestFee = true;
        }

        if (penaltyInfo.strikesPenalty.isValue) {
            penaltySum = _scalePenaltyByMultiplier(
                penaltyInfo.strikesPenalty.value,
                penaltyMultiplier
            );
            chargeWithdrawalRequestFee = true;
        }

        // The withdrawal request fee is taken when either a delay was reported or the validator exited due to
        // strikes. Otherwise, the fee has already been paid by the node operator upon withdrawal trigger, or it is
        // a DAO decision to withdraw the validator before the withdrawal request becomes delayed.
        if (
            chargeWithdrawalRequestFee &&
            penaltyInfo.withdrawalRequestFee.value != 0
        ) {
            // Withdrawal request fee is not scaled because sending a withdrawal request for a validator does
            // not depend on the size of a validator.
            feeSum += penaltyInfo.withdrawalRequestFee.value;
        }

        if (validatorInfo.isSlashed) {
            // Slashing penalty doesn't scale because all the losses are already accounted.
            penaltySum += validatorInfo.slashingPenalty;
        } else if (validatorInfo.exitBalance < MIN_ACTIVATION_BALANCE) {
            penaltySum += MIN_ACTIVATION_BALANCE - validatorInfo.exitBalance;
        }

        IAccounting accounting = IBaseModule(address(this)).ACCOUNTING();

        bondCoversPenalties = true;

        if (feeSum > 0) {
            bondCoversPenalties = accounting.chargeFee(
                validatorInfo.nodeOperatorId,
                feeSum
            );
        }

        if (penaltySum > 0) {
            // We still call `penalize` even if there's no bond left, for the lock to be created.
            bondCoversPenalties = accounting.penalize(
                validatorInfo.nodeOperatorId,
                penaltySum
            );
        }
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

    function _scalePenaltyByMultiplier(
        uint256 penalty,
        uint256 multiplier
    ) internal pure returns (uint256) {
        return (penalty * multiplier) / PENALTY_SCALE;
    }
}
