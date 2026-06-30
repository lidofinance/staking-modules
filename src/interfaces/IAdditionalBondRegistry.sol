// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @dev Bond tier. Fields hold increments above MAX_BP in storage; `getTierInfo` returns them as full
///      effective multipliers (MAX_BP + stored increment).
struct TierInfo {
    uint128 curveMultiplier;
    uint128 weightMultiplier;
}

/// @dev Operator's effective tier state, with multipliers as full basis-point values.
///      During a downgrade cooldown `curveMultiplier` keeps the pre-downgrade value until `applyCurveMultiplier`,
///      so it may exceed the current tier's value (and stay above MAX_BP while `tierId == 0`).
struct OperatorTierState {
    uint256 tierId;
    uint256 curveMultiplier;
    uint256 weightMultiplier;
    uint256 curveMultiplierCooldownUntil;
}

/// @notice Manages operator bond tiers and associated tier downgrade cooldown state.
interface IAdditionalBondRegistry is IWeightBoostProvider {
    event TierAdded(uint256 indexed tierId, uint256 curveMultiplier, uint256 weightMultiplier);
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

    /// @notice MetaRegistry called back via `notifyWeightBoostChanged` on tier changes.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice Upper bound for `curveMultiplier`.
    function MAX_CURVE_MULTIPLIER() external view returns (uint256);

    /// @notice Upper bound for `weightMultiplier`.
    function MAX_WEIGHT_MULTIPLIER() external view returns (uint256);

    /// @notice Cooldown in seconds after a downgrade before `applyCurveMultiplier` can be called.
    function CURVE_MULTIPLIER_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address admin) external;

    /// @notice Add a new bond tier. Tier IDs are assigned sequentially starting from 1.
    /// @param curveMultiplier  Curve multiplier increment above MAX_BP (must be <= MAX_CURVE_MULTIPLIER).
    /// @param weightMultiplier Weight multiplier increment above MAX_BP (must be <= MAX_WEIGHT_MULTIPLIER).
    /// @return tierId ID of the newly created tier.
    function addTier(uint256 curveMultiplier, uint256 weightMultiplier) external returns (uint256 tierId);

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

    /// @notice Effective multipliers of a tier as full basis-point values (tier 0 = MAX_BP, no scaling).
    /// @dev For an operator's CURRENT curve multiplier (which may lag during a downgrade cooldown) use `getOperatorTierState`.
    function getTierInfo(uint256 tierId) external view returns (TierInfo memory);

    /// @notice Full effective tier-related state of a Node Operator.
    function getOperatorTierState(uint256 nodeOperatorId) external view returns (OperatorTierState memory);
}
