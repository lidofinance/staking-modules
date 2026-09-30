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

/// @dev External deployment-linked library used by BaseModule-compatible modules
///      to extract withdrawn validator processing from module bytecode.
library WithdrawnValidatorLib {
    uint256 public constant PENALTY_QUOTIENT = 1 ether;
    /// @dev Acts as the denominator to calculate the scaled penalty.
    uint256 public constant PENALTY_SCALE = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE / PENALTY_QUOTIENT;

    function processBatch(
        WithdrawnValidatorInfo[] calldata validatorInfos,
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
            // Only `reportValidatorSlashing` may charge a penalty, and it marks the key as slashed first.
            if (info.slashingPenalty != 0 && !$.isValidatorSlashed[pointer]) {
                revert IBaseModule.SlashingPenaltyIsNotApplicable();
            }

            _process($.nodeOperators[info.nodeOperatorId], info, $.keyConfirmedBalance[pointer]);

            $.isValidatorWithdrawn[pointer] = true;
            touchedOperatorIds[touchedCount] = info.nodeOperatorId;
            trackedBalanceDecreases[touchedCount] = $.keyAllocatedBalance[pointer];
            unchecked {
                ++touchedCount;
            }
        }
    }

    function _process(
        NodeOperator storage no,
        WithdrawnValidatorInfo calldata validatorInfo,
        uint256 keyConfirmedBalance
    ) private {
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

        _fulfillExitObligations(validatorInfo, penaltyInfo, keyConfirmedBalance);

        emit IBaseModule.ValidatorWithdrawn({
            nodeOperatorId: validatorInfo.nodeOperatorId,
            keyIndex: validatorInfo.keyIndex,
            pubkey: pubkey
        });
    }

    // NOTE: The function might revert if the penalty recorded in the `penaltyInfo` is large enough. As of now, it
    // should be greater than 2^245, which is about 5.6 * 10^55 ethers.
    function _fulfillExitObligations(
        WithdrawnValidatorInfo calldata validatorInfo,
        ExitPenaltyInfo memory penaltyInfo,
        uint256 keyConfirmedBalance
    ) private {
        uint256 minExpectedBalance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + keyConfirmedBalance;
        uint256 penaltyScale = Math.max(validatorInfo.exitBalance, minExpectedBalance);
        uint256 penaltySum;

        if (penaltyInfo.strikesPenalty.isValue) {
            penaltySum = scalePenalty(penaltyInfo.strikesPenalty.value, penaltyScale);
        }

        // The slashing penalty accounts for all the losses, so the balance shortage is not charged on top of it.
        if (validatorInfo.slashingPenalty > 0) {
            penaltySum += scalePenalty(validatorInfo.slashingPenalty, penaltyScale);
        } else {
            penaltySum += Math.saturatingSub(minExpectedBalance, validatorInfo.exitBalance);
        }

        if (penaltySum > 0) {
            IBaseModule(address(this)).ACCOUNTING().penalize(validatorInfo.nodeOperatorId, penaltySum);
        }
    }

    function scalePenalty(uint256 penalty, uint256 balance) internal pure returns (uint256) {
        balance = _clamp(
            balance,
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE
        );
        uint256 multiplier = _getPenaltyMultiplier(balance);
        return _scalePenaltyByMultiplier(penalty, multiplier);
    }

    /// @dev Acts as the numerator to calculate the scaled penalty.
    /// @dev Expects the `balance` value between MIN_ACTIVATION_BALANCE and MAX_EFFECTIVE_BALANCE.
    function _getPenaltyMultiplier(uint256 balance) internal pure returns (uint256 penaltyMultiplier) {
        penaltyMultiplier = balance / PENALTY_QUOTIENT;
    }

    function _scalePenaltyByMultiplier(uint256 penalty, uint256 multiplier) internal pure returns (uint256) {
        return (penalty * multiplier) / PENALTY_SCALE;
    }

    function _clamp(uint256 v, uint256 min, uint256 max) internal pure returns (uint256) {
        return Math.min(Math.max(v, min), max);
    }
}
