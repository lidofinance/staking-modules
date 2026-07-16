// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @dev A boost step: curve multiplier increments at or above `minCurveMultiplier` map to
///      `weightMultiplier`. Both are increments above MAX_BP in basis points (0 = no scaling).
struct BoostStep {
    uint128 minCurveMultiplier;
    uint128 weightMultiplier;
}

/// @dev A pending downgrade: the cooldown deadline and the curve multiplier increment to apply once it
///      elapses. `cooldownUntil == 0` means no active cooldown. Packed into a single slot.
struct PendingCurveMultiplierReduction {
    uint128 cooldownUntil;
    uint128 curveMultiplier;
}

/// @notice Maps an operator's curve multiplier to a weight multiplier via governance-set boost steps.
///         The curve multiplier itself lives in Accounting; this registry only requests changes and serves
///         the resulting weight boost. Lowering the weight applies immediately, while the curve multiplier
///         decrease is deferred until the cooldown elapses.
interface IAdditionalBondRegistry is IWeightBoostProvider {
    event BoostStepsSet(BoostStep[] boostSteps);
    event CurveMultiplierReductionRequested(uint256 indexed nodeOperatorId, uint256 curveMultiplier);
    event CurveMultiplierReductionCooldownSet(uint256 indexed nodeOperatorId, uint256 cooldownUntil);
    event CurveMultiplierReductionCooldownRemoved(uint256 indexed nodeOperatorId);

    error ZeroAdminAddress();
    error EmptyBoostSteps();
    error InvalidCurveMultiplier();
    error InvalidWeightMultiplier();
    error InsufficientBond();
    error SameCurveMultiplier();
    error SenderIsNotOperatorOwner();
    error NoCurveMultiplierReductionCooldown();
    error CurveMultiplierReductionCooldownNotElapsed();

    function MODULE() external view returns (ICuratedModule);

    /// @dev Holding bond curves and the operator curve multiplier.
    function ACCOUNTING() external view returns (IAccounting);

    /// @dev Notified via `notifyWeightBoostChanged` on weight changes.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @dev Upper bound for a boost step's curve multiplier increment (above MAX_BP, in basis points).
    function MAX_CURVE_MULTIPLIER() external view returns (uint256);

    /// @dev Upper bound for a boost step's weight multiplier increment (above MAX_BP, in basis points).
    function MAX_WEIGHT_MULTIPLIER() external view returns (uint256);

    /// @dev Cooldown in seconds after a downgrade request before `applyCurveMultiplier` can be called.
    function CURVE_MULTIPLIER_REDUCTION_COOLDOWN() external view returns (uint256);

    /// @dev Requested curve multiplier must be a multiple of this (1%).
    function CURVE_MULTIPLIER_STEP() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param boostSteps Initial boost steps; must be non-empty (same rules as `setBoostSteps`).
    function initialize(address admin, BoostStep[] calldata boostSteps) external;

    /// @notice Replace the boost steps. The list must be non-empty and strictly ascending by both fields,
    ///         each an increment above MAX_BP in [0, MAX_CURVE_MULTIPLIER] / [0, MAX_WEIGHT_MULTIPLIER].
    /// @param boostSteps New boost steps.
    function setBoostSteps(BoostStep[] calldata boostSteps) external;

    /// @notice Request a curve multiplier for the Node Operator. Raising it applies immediately (needs enough
    ///         bond) and clears any pending downgrade; lowering it drops the weight now but reduces the
    ///         multiplier in Accounting only after the cooldown, via `applyCurveMultiplier`. Reverts if unchanged.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param curveMultiplier Curve multiplier increment (above MAX_BP), a multiple of CURVE_MULTIPLIER_STEP; 0 = no boost.
    function requestCurveMultiplier(uint256 nodeOperatorId, uint256 curveMultiplier) external;

    /// @notice Apply a pending downgrade after its cooldown elapses, lowering the curve multiplier in
    ///         Accounting to the requested value. Callable only by the Node Operator owner.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyCurveMultiplier(uint256 nodeOperatorId) external;

    /// @notice The current boost steps.
    function getBoostSteps() external view returns (BoostStep[] memory);
}
