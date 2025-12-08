// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAccounting } from "./IAccounting.sol";
import { IBondCurve } from "./IBondCurve.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";

/// @title One-shot setup helper for a bond curve plus per-curve parameter overrides.
interface IOneShotCurveSetup {
    struct ScalarOverride {
        bool isSet;
        uint256 value;
    }

    struct QueueConfigOverride {
        bool isSet;
        uint256 priority;
        uint256 maxDeposits;
    }

    struct StrikesOverride {
        bool isSet;
        uint256 lifetime;
        uint256 threshold;
    }

    struct PerformanceCoefficientsOverride {
        bool isSet;
        uint256 attestationsWeight;
        uint256 blocksWeight;
        uint256 syncWeight;
    }

    struct KeyNumberValueIntervalsOverride {
        bool isSet;
        IParametersRegistry.KeyNumberValueInterval[] data;
    }

    struct ConstructorParams {
        IBondCurve.BondCurveIntervalInput[] bondCurve;
        ScalarOverride keyRemovalCharge;
        ScalarOverride generalDelayedPenaltyFine;
        ScalarOverride keysLimit;
        QueueConfigOverride queueConfig;
        KeyNumberValueIntervalsOverride rewardShareData;
        KeyNumberValueIntervalsOverride performanceLeewayData;
        StrikesOverride strikesParams;
        ScalarOverride badPerformancePenalty;
        PerformanceCoefficientsOverride performanceCoefficients;
        ScalarOverride allowedExitDelay;
        ScalarOverride exitDelayFee;
        ScalarOverride maxWithdrawalRequestFee;
    }

    /// @dev Emitted once the curve setup completes successfully.
    event BondCurveDeployed(uint256 indexed curveId);

    error AlreadyExecuted();
    error ZeroAccountingAddress();
    error ZeroRegistryAddress();
    error EmptyBondCurve();

    /// @notice Bond accounting contract that receives the new curve.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Parameters registry whose per-curve overrides are configured.
    function REGISTRY() external view returns (IParametersRegistry);

    /// @notice Whether `execute()` already ran.
    function executed() external view returns (bool);

    /// @notice Curve ID created by the successful `execute()` call.
    function deployedCurveId() external view returns (uint256);

    /// @notice Executes the stored rollout plan, adding the curve and applying the overrides.
    /// @return curveId Curve ID allocated to the newly deployed bond curve.
    function execute() external returns (uint256 curveId);
}
