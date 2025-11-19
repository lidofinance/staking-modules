// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ICSModule, WithdrawnValidatorInfo } from "../interfaces/ICSModule.sol";
import { ExitPenaltyInfo } from "../interfaces/ICSExitPenalties.sol";
import { ICSAccounting } from "../interfaces/ICSAccounting.sol";

import { SigningKeys } from "./SigningKeys.sol";

/// @dev A library to extract a part of the code from the the CSModule contract.
library WithdrawnValidatorLib {
    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;
    uint256 public constant PENALTY_QUOTIENT = 32 ether;
    uint256 public constant MAX_PENALTY_MULTIPLIER = 64;

    function process(
        WithdrawnValidatorInfo calldata validatorInfo
    ) external returns (bool bondCoversPenalties) {
        bytes memory pubkey = SigningKeys.loadKeys(
            validatorInfo.nodeOperatorId,
            validatorInfo.keyIndex,
            1
        );

        ExitPenaltyInfo memory penaltyInfo = ICSModule(address(this))
            .EXIT_PENALTIES()
            .getExitPenaltyInfo(validatorInfo.nodeOperatorId, pubkey);

        bondCoversPenalties = _fulfilExitObligations(
            validatorInfo,
            penaltyInfo
        );

        // solhint-disable-next-line func-named-parameters
        emit ICSModule.WithdrawalSubmitted(
            validatorInfo.nodeOperatorId,
            validatorInfo.keyIndex,
            validatorInfo.exitBalance,
            validatorInfo.slashingPenalty,
            pubkey
        );
    }

    function _fulfilExitObligations(
        WithdrawnValidatorInfo calldata validatorInfo,
        ExitPenaltyInfo memory penaltyInfo
    ) private returns (bool bondCoversPenalties) {
        bool chargeWithdrawalRequestFee = false;

        uint256 penaltyMultiplier = _getPenaltyMultiplier(validatorInfo);
        uint256 penaltySum;
        uint256 feeSum;

        if (penaltyInfo.delayFee.isValue) {
            unchecked {
                feeSum = penaltyInfo.delayFee.value * penaltyMultiplier;
            }
            chargeWithdrawalRequestFee = true;
        }

        if (penaltyInfo.strikesPenalty.isValue) {
            // It is safe to use unchecked for sum here because base penalties and fees are limited to uint248 in
            // the MarkedUint248 structures used to store them, and the maximum multiplier is limited to 64, so
            // `type(uint248).max * 64 < type(uint256).max`.
            unchecked {
                penaltySum =
                    penaltyInfo.strikesPenalty.value *
                    penaltyMultiplier;
            }
            chargeWithdrawalRequestFee = true;
        }

        // The withdrawal request fee is taken when either a delay was reported or the validator exited due to
        // strikes. Otherwise, the fee has already been paid by the node operator upon withdrawal trigger, or it is
        // a DAO decision to withdraw the validator before the withdrawal request becomes delayed.
        if (
            chargeWithdrawalRequestFee &&
            penaltyInfo.withdrawalRequestFee.value != 0
        ) {
            // type(uint248).max * (64 + 1) < type(uint256).max
            unchecked {
                // Withdrawal request fee is not scaled because sending a withdrawal request for a validator does
                // not depend on the size of a validator.
                feeSum += penaltyInfo.withdrawalRequestFee.value;
            }
        }

        if (validatorInfo.isSlashed) {
            // Slashing penalty doesn't scale because all the losses are already accounted.
            penaltySum += validatorInfo.slashingPenalty;
        } else if (validatorInfo.exitBalance < MIN_ACTIVATION_BALANCE) {
            // type(uint248).max * 64 + 32 * 10**18 < type(uint256).max
            unchecked {
                penaltySum +=
                    MIN_ACTIVATION_BALANCE -
                    validatorInfo.exitBalance;
            }
        }

        ICSAccounting accounting = ICSModule(address(this)).ACCOUNTING();

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

    function _getPenaltyMultiplier(
        WithdrawnValidatorInfo memory validatorInfo
    ) private pure returns (uint256 penaltyMultiplier) {
        // penaltyMultiplier is >= 1
        penaltyMultiplier =
            Math.max(validatorInfo.exitBalance, MIN_ACTIVATION_BALANCE) /
            PENALTY_QUOTIENT;
        // It's rather unlikely that the value will exceed 64 because anything above maximum effective balance of a
        // validator will likely be withdrawn while it waits for a withdrawal. The introduced limit makes it
        // possible to use unchecked blocks above and acts as an additional limiting factor.
        penaltyMultiplier = Math.min(MAX_PENALTY_MULTIPLIER, penaltyMultiplier);
    }
}
