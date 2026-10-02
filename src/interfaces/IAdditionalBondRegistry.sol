// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @dev A pending downgrade: the cooldown deadline and the curve multiplier increment to apply once it
///      elapses. `cooldownUntil == 0` means no active cooldown. Packed into a single slot.
struct PendingCurveMultiplierReduction {
    uint128 cooldownUntil;
    uint128 curveMultiplier;
}

/// @notice Maps an operator's curve multiplier to a weight multiplier via governance-set steps.
///         The curve multiplier itself lives in Accounting; this registry only requests changes and serves
///         the resulting weight boost. Lowering the weight applies immediately, while the curve multiplier
///         decrease is deferred until the cooldown elapses. In this provider, `Step.threshold` is a curve
///         multiplier increment and `Step.value` is a weight multiplier increment above MAX_BP.
interface IAdditionalBondRegistry is IStepwiseWeightBoost {
    event CurveMultiplierReductionRequested(
        uint256 indexed nodeOperatorId,
        uint256 curveMultiplier,
        uint256 cooldownUntil
    );
    event CurveMultiplierReductionApplied(uint256 indexed nodeOperatorId, uint256 curveMultiplier);
    event CurveMultiplierReductionCancelled(uint256 indexed nodeOperatorId);
    event CurveMultiplierReductionCooldownSet(uint256 curveMultiplierReductionCooldown);

    error InvalidCurveMultiplier();
    error InvalidCurveMultiplierReductionCooldown();
    error InsufficientBond();
    error SameCurveMultiplier();
    error NoCurveMultiplierReductionCooldown();
    error CurveMultiplierReductionCooldownNotElapsed();

    /// @notice Accounting contract holding bond curves and the operator curve multiplier.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Upper bound for a curve multiplier increment (above MAX_BP, in basis points).
    function MAX_CURVE_MULTIPLIER() external view returns (uint256);

    /// @notice Maximum configurable curve multiplier reduction cooldown in seconds.
    function MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN() external view returns (uint256);

    /// @notice Granularity of a requested curve multiplier increment (1%).
    function CURVE_MULTIPLIER_STEP() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param curveMultiplierReductionCooldown Stored cooldown duration in seconds, in
    ///        [1, MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN].
    /// @param steps Initial steps. Thresholds may start at zero, must be multiples of
    ///        CURVE_MULTIPLIER_STEP and must not exceed MAX_CURVE_MULTIPLIER; values must not exceed
    ///        MAX_STEP_VALUE.
    function initialize(address admin, uint256 curveMultiplierReductionCooldown, Step[] calldata steps) external;

    /// @notice Request a curve multiplier for the Node Operator. Only the Node Operator owner. Raising it
    ///         applies immediately (needs enough bond) and clears any pending downgrade; lowering it drops
    ///         the weight now but reduces the multiplier in Accounting only after the cooldown, via
    ///         `applyCurveMultiplierReduction`. Reverts if it equals the multiplier currently stored in
    ///         Accounting.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param curveMultiplier Curve multiplier increment (above MAX_BP), a multiple of CURVE_MULTIPLIER_STEP; 0 = no boost.
    function requestCurveMultiplier(uint256 nodeOperatorId, uint256 curveMultiplier) external;

    /// @notice Apply a pending downgrade after its cooldown elapses, lowering the curve multiplier in
    ///         Accounting to the requested value. Only the Node Operator owner.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyCurveMultiplierReduction(uint256 nodeOperatorId) external;

    /// @notice Cancel a pending downgrade. Only the Node Operator owner. Restores allocation weight to
    ///         the multiplier still held in Accounting and reverts if no downgrade is pending.
    /// @param nodeOperatorId ID of the Node Operator.
    function cancelCurveMultiplierReduction(uint256 nodeOperatorId) external;

    /// @notice Set the cooldown used by future downgrade requests. Only DEFAULT_ADMIN_ROLE; existing
    ///         pending deadlines are unchanged.
    /// @param curveMultiplierReductionCooldown Stored duration in seconds, in
    ///        [1, MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN].
    function setCurveMultiplierReductionCooldown(uint256 curveMultiplierReductionCooldown) external;

    /// @notice Curve multiplier reduction cooldown in seconds.
    function getCurveMultiplierReductionCooldown() external view returns (uint256);

    /// @notice Pending downgrade target and its deadline. The target applies only while `cooldownUntil`
    ///         is non-zero, since zero is a legitimate target.
    /// @param nodeOperatorId ID of the Node Operator.
    function getPendingCurveMultiplierReduction(
        uint256 nodeOperatorId
    ) external view returns (PendingCurveMultiplierReduction memory pending);
}
