// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IBondCurve } from "../interfaces/IBondCurve.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { IParametersRegistry } from "../interfaces/IParametersRegistry.sol";
import { IOneShotCurveSetup } from "../interfaces/IOneShotCurveSetup.sol";

/// @notice Helper that atomically deploys a new bond curve together with its parameter overrides.
/// @dev The contract is intentionally single-use: once `execute` finishes successfully it
///      stores the emitted `curveId` for reference.
contract OneShotCurveSetup is IOneShotCurveSetup {
    IAccounting public immutable ACCOUNTING;
    IParametersRegistry public immutable REGISTRY;

    bool public executed;
    uint256 public deployedCurveId;

    IBondCurve.BondCurveIntervalInput[] public bondCurve;

    ScalarOverride public keyRemovalChargeOverride;
    ScalarOverride public generalDelayedPenaltyFineOverride;
    ScalarOverride public keysLimitOverride;
    QueueConfigOverride public queueConfigOverride;
    KeyNumberValueIntervalsOverride public rewardShareDataOverride;
    KeyNumberValueIntervalsOverride public performanceLeewayDataOverride;
    StrikesOverride public strikesParamsOverride;
    ScalarOverride public badPerformancePenaltyOverride;
    PerformanceCoefficientsOverride public performanceCoefficientsOverride;
    ScalarOverride public allowedExitDelayOverride;
    ScalarOverride public exitDelayFeeOverride;
    ScalarOverride public maxWithdrawalRequestFeeOverride;

    constructor(
        address accounting_,
        address registry_,
        ConstructorParams memory params
    ) {
        if (accounting_ == address(0)) {
            revert ZeroAccountingAddress();
        }
        if (registry_ == address(0)) {
            revert ZeroRegistryAddress();
        }
        if (params.bondCurve.length == 0) {
            revert EmptyBondCurve();
        }

        ACCOUNTING = IAccounting(accounting_);
        REGISTRY = IParametersRegistry(registry_);

        _storeBondCurve(params.bondCurve);
        keyRemovalChargeOverride = params.keyRemovalCharge;
        generalDelayedPenaltyFineOverride = params.generalDelayedPenaltyFine;
        keysLimitOverride = params.keysLimit;
        queueConfigOverride = params.queueConfig;

        _storeIntervals(params.rewardShareData, rewardShareDataOverride);
        _storeIntervals(
            params.performanceLeewayData,
            performanceLeewayDataOverride
        );

        strikesParamsOverride = params.strikesParams;
        badPerformancePenaltyOverride = params.badPerformancePenalty;
        performanceCoefficientsOverride = params.performanceCoefficients;
        allowedExitDelayOverride = params.allowedExitDelay;
        exitDelayFeeOverride = params.exitDelayFee;
        maxWithdrawalRequestFeeOverride = params.maxWithdrawalRequestFee;
    }

    function execute() external override returns (uint256 curveId) {
        if (executed) {
            revert AlreadyExecuted();
        }
        executed = true;

        curveId = ACCOUNTING.addBondCurve(bondCurve);
        deployedCurveId = curveId;

        _applyParameterOverrides(curveId);
        emit BondCurveDeployed(curveId);
    }

    function _applyParameterOverrides(uint256 curveId) internal {
        if (keyRemovalChargeOverride.isSet) {
            REGISTRY.setKeyRemovalCharge(
                curveId,
                keyRemovalChargeOverride.value
            );
        }
        if (generalDelayedPenaltyFineOverride.isSet) {
            REGISTRY.setGeneralDelayedPenaltyAdditionalFine(
                curveId,
                generalDelayedPenaltyFineOverride.value
            );
        }
        if (keysLimitOverride.isSet) {
            REGISTRY.setKeysLimit(curveId, keysLimitOverride.value);
        }
        if (queueConfigOverride.isSet) {
            REGISTRY.setQueueConfig(
                curveId,
                queueConfigOverride.priority,
                queueConfigOverride.maxDeposits
            );
        }
        if (rewardShareDataOverride.isSet) {
            REGISTRY.setRewardShareData(curveId, rewardShareDataOverride.data);
        }
        if (performanceLeewayDataOverride.isSet) {
            REGISTRY.setPerformanceLeewayData(
                curveId,
                performanceLeewayDataOverride.data
            );
        }
        if (strikesParamsOverride.isSet) {
            REGISTRY.setStrikesParams(
                curveId,
                strikesParamsOverride.lifetime,
                strikesParamsOverride.threshold
            );
        }
        if (badPerformancePenaltyOverride.isSet) {
            REGISTRY.setBadPerformancePenalty(
                curveId,
                badPerformancePenaltyOverride.value
            );
        }
        if (performanceCoefficientsOverride.isSet) {
            REGISTRY.setPerformanceCoefficients(
                curveId,
                performanceCoefficientsOverride.attestationsWeight,
                performanceCoefficientsOverride.blocksWeight,
                performanceCoefficientsOverride.syncWeight
            );
        }
        if (allowedExitDelayOverride.isSet) {
            REGISTRY.setAllowedExitDelay(
                curveId,
                allowedExitDelayOverride.value
            );
        }
        if (exitDelayFeeOverride.isSet) {
            REGISTRY.setExitDelayFee(curveId, exitDelayFeeOverride.value);
        }
        if (maxWithdrawalRequestFeeOverride.isSet) {
            REGISTRY.setMaxWithdrawalRequestFee(
                curveId,
                maxWithdrawalRequestFeeOverride.value
            );
        }
    }

    function _storeBondCurve(
        IBondCurve.BondCurveIntervalInput[] memory source
    ) internal {
        for (uint256 i = 0; i < source.length; ++i) {
            bondCurve.push(source[i]);
        }
    }

    function _storeIntervals(
        KeyNumberValueIntervalsOverride memory source,
        KeyNumberValueIntervalsOverride storage target
    ) internal {
        target.isSet = source.isSet;
        for (uint256 i = 0; i < source.data.length; ++i) {
            target.data.push(source.data[i]);
        }
    }
}
