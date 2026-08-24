// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @dev Fee discount state of a Node Operator, packed into one slot.
struct FeeDiscountState {
    uint16 currentFeeDiscount;
    uint16 pendingFeeDiscount;
    uint64 cooldownUntil;
}

/// @notice Per-operator discount from the operator's base fee and the allocation weight boost derived from it.
///         The base and effective fees are intentionally calculated off-chain.
interface ICustomFeeRegistry is IStepwiseWeightBoost {
    event FeeDiscountSet(uint256 indexed nodeOperatorId, uint256 feeDiscount);
    event FeeDiscountCutRequested(uint256 indexed nodeOperatorId, uint256 pendingFeeDiscount, uint256 cooldownUntil);
    event FeeDiscountCutApplied(uint256 indexed nodeOperatorId, uint256 feeDiscount);
    event FeeDiscountCutCancelled(uint256 indexed nodeOperatorId);
    event FeeDiscountCutCooldownSet(uint256 feeDiscountCutCooldown);

    error InvalidFeeDiscount();
    error SameFeeDiscount();
    error NoPendingFeeDiscountCut();
    error FeeDiscountCutCooldownNotElapsed();
    error InvalidFeeDiscountCutCooldown();

    /// @notice Fee discount granularity: one percentage point, in basis points.
    function FEE_DISCOUNT_STEP() external view returns (uint256);

    /// @notice Maximum configurable fee-discount cut cooldown in seconds.
    function MAX_FEE_DISCOUNT_CUT_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param feeDiscountCutCooldown Duration in seconds, in [1, MAX_FEE_DISCOUNT_CUT_COOLDOWN].
    /// @param steps Initial steps. A threshold is a fee discount in basis points.
    function initialize(address admin, uint256 feeDiscountCutCooldown, Step[] calldata steps) external;

    /// @notice Request a fee discount, from zero to MAX_BP. An increase applies immediately;
    ///         a cut enters cooldown while the allocation weight follows it immediately. Only the Node
    ///         Operator owner.
    function requestFeeDiscount(uint256 nodeOperatorId, uint256 feeDiscount) external;

    /// @notice Cancel a pending fee-discount cut. Only the Node Operator owner.
    function cancelFeeDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Apply a pending fee-discount cut once its cooldown has elapsed. Only the Node Operator owner.
    function applyFeeDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Set the cooldown for future fee-discount cuts. Pending requests are unaffected.
    ///         Only DEFAULT_ADMIN_ROLE.
    function setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) external;

    /// @notice Fee-discount cut cooldown in seconds.
    function getFeeDiscountCutCooldown() external view returns (uint256);

    /// @notice Stored fee discount. Returns zero for an operator that has never set one.
    function getFeeDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Pending cut target. Meaningful only while a cooldown is active.
    function getPendingFeeDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice End of the pending cut cooldown, or zero if none.
    function getFeeDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256);
}
