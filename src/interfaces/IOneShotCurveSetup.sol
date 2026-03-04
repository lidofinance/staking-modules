// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { IBondCurve } from "./IBondCurve.sol";
import { IParametersRegistry } from "./IParametersRegistry.sol";

/// @title One-shot setup helper for a bond curve plus per-curve parameter overrides.
/// @notice Intended for one-shot execution with temporary permissions only.
///         Required roles:
///         - `ACCOUNTING.MANAGE_BOND_CURVES_ROLE()`
///         - `REGISTRY.MANAGE_CURVE_PARAMETERS_ROLE()`
///         After `execute()` succeeds, this contract renounces both roles.
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
        ScalarOverride maxElWithdrawalRequestFee;
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

    /// @notice Returns the stored bond curve to be deployed by `execute()`.
    function getBondCurve() external view returns (IBondCurve.BondCurveIntervalInput[] memory bondCurve);

    /// @notice Returns whether reward share override is configured and the configured interval data.
    function getRewardShareDataOverride()
        external
        view
        returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);

    /// @notice Returns whether performance leeway override is configured and the configured interval data.
    function getPerformanceLeewayDataOverride()
        external
        view
        returns (bool isSet, IParametersRegistry.KeyNumberValueInterval[] memory data);

    /// @notice Executes the stored rollout plan, adding the curve and applying the overrides.
    /// @dev Requires only:
    ///      `ACCOUNTING.MANAGE_BOND_CURVES_ROLE()` and `REGISTRY.MANAGE_CURVE_PARAMETERS_ROLE()`.
    ///      On success, both roles are renounced by this contract.
    /// @return curveId Curve ID allocated to the newly deployed bond curve.
    function execute() external returns (uint256 curveId);
}
