// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";

/// @dev Bond tier. Multipliers are stored as increments above MAX_BP (effective = MAX_BP + increment).
struct TierInfo {
    uint128 curveMultiplierInc;
    uint128 weightMultiplierInc;
}

/// @dev Operator's effective tier state, with multipliers as full basis-point values (not `TierInfo` increments).
///      During a downgrade cooldown `curveMultiplier` keeps the pre-downgrade value until `applyCurveMultiplier`,
///      so it may exceed the current tier's value (and stay above MAX_BP while `tierId == 0`).
struct OperatorTierState {
    uint256 tierId;
    uint256 curveMultiplier;
    uint256 weightMultiplier;
    uint256 curveMultiplierCooldownUntil;
}

/// @notice Manages operator bond tiers and associated tier downgrade cooldown state.
interface IAdditionalBondRegistry {
    event TierAdded(uint256 indexed tierId, uint256 curveMultiplierInc, uint256 weightMultiplierInc);
    event TierSelected(uint256 indexed nodeOperatorId, uint256 tierId);
    event CurveMultiplierCooldownSet(uint256 indexed nodeOperatorId, uint256 cooldownUntil);
    event CurveMultiplierCooldownRemoved(uint256 indexed nodeOperatorId);

    error ZeroAdminAddress();
    error InvalidCurveMultiplier();
    error InvalidWeightMultiplier();
    error InvalidTierId();
    error SameTier();
    error InsufficientBondForTier();
    error SenderIsNotOperatorOwner();
    error NoCurveMultiplierCooldown();
    error CurveMultiplierCooldownNotElapsed();
    error CurveMultiplierCooldownActive();

    /// @notice Curated module address.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract holding bond curves and the operator curve multiplier.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice MetaRegistry called back via `refreshOperatorWeight` on tier changes.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice Upper bound for `curveMultiplierInc`.
    function MAX_CURVE_MULTIPLIER_INC() external view returns (uint256);

    /// @notice Upper bound for `weightMultiplierInc`.
    function MAX_WEIGHT_MULTIPLIER_INC() external view returns (uint256);

    /// @notice Cooldown in seconds after a downgrade before `applyCurveMultiplier` can be called.
    function CURVE_MULTIPLIER_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address admin) external;

    /// @notice Add a new bond tier. Tier IDs are assigned sequentially starting from 1.
    /// @param curveMultiplierInc  Curve multiplier increment above MAX_BP (must be <= MAX_CURVE_MULTIPLIER_INC).
    /// @param weightMultiplierInc Weight multiplier increment above MAX_BP (must be <= MAX_WEIGHT_MULTIPLIER_INC).
    /// @return tierId ID of the newly created tier.
    function addTier(uint256 curveMultiplierInc, uint256 weightMultiplierInc) external returns (uint256 tierId);

    /// @notice Select a bond tier for the Node Operator. An upgrade (target effective curve multiplier above the
    ///         operator's current one) applies both multipliers at once and requires the bond to cover the new
    ///         requirement; a downgrade applies the new weight now but keeps the higher curve multiplier until
    ///         `applyCurveMultiplier`. Either clears an active cooldown (upgrade) or reverts on it (downgrade).
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param tierId         Target tier ID (0 = default tier).
    function selectTier(uint256 nodeOperatorId, uint256 tierId) external;

    /// @notice Apply a pending downgrade after its cooldown elapses, lowering the curve multiplier to the current
    ///         tier. Callable only by the Node Operator owner.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyCurveMultiplier(uint256 nodeOperatorId) external;

    /// @notice Number of stored tiers (not counting the implicit default tier 0).
    function getTiersCount() external view returns (uint256);

    /// @notice Static parameters of a tier definition, as increments above MAX_BP.
    /// @dev Do not use this to read an operator's effective bond multiplier — use `getOperatorTierState`.
    function getTierInfo(uint256 tierId) external view returns (TierInfo memory);

    /// @notice Full effective tier-related state of a Node Operator.
    function getOperatorTierState(uint256 nodeOperatorId) external view returns (OperatorTierState memory);
}
