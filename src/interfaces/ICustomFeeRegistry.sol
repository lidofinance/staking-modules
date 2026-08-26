// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @dev Fee share discount state of a Node Operator, packed into one slot.
struct FeeShareDiscountState {
    uint16 currentFeeShareDiscount;
    uint16 pendingFeeShareDiscount;
    uint64 cooldownUntil;
}

/// @notice Per-operator discount from the operator's fee share and the allocation weight boost derived from it.
///         The base and effective fees are intentionally calculated off-chain.
interface ICustomFeeRegistry is IStepwiseWeightBoost {
    event FeeShareDiscountSet(uint256 indexed nodeOperatorId, uint256 feeShareDiscount);
    event FeeShareDiscountCutRequested(
        uint256 indexed nodeOperatorId,
        uint256 pendingFeeShareDiscount,
        uint256 cooldownUntil
    );
    event FeeShareDiscountCutApplied(uint256 indexed nodeOperatorId, uint256 feeShareDiscount);
    event FeeShareDiscountCutCancelled(uint256 indexed nodeOperatorId);
    event FeeShareDiscountCutCooldownSet(uint256 feeShareDiscountCutCooldown);

    error InvalidFeeShareDiscount();
    error SameFeeShareDiscount();
    error NoPendingFeeShareDiscountCut();
    error FeeShareDiscountCutCooldownNotElapsed();
    error InvalidFeeShareDiscountCutCooldown();

    /// @notice Fee share discount granularity: one percentage point, in basis points.
    function FEE_SHARE_DISCOUNT_STEP() external view returns (uint256);

    /// @notice Maximum configurable fee-share discount cut cooldown in seconds.
    function MAX_FEE_SHARE_DISCOUNT_CUT_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param feeShareDiscountCutCooldown Duration in seconds, in [1, MAX_FEE_SHARE_DISCOUNT_CUT_COOLDOWN].
    /// @param steps Initial steps. A threshold is a fee share discount in basis points.
    function initialize(address admin, uint256 feeShareDiscountCutCooldown, Step[] calldata steps) external;

    /// @notice Request a fee share discount, from zero to MAX_BP. An increase applies immediately;
    ///         a cut enters cooldown while the allocation weight follows it immediately. Only the Node
    ///         Operator owner.
    function requestFeeShareDiscount(uint256 nodeOperatorId, uint256 feeShareDiscount) external;

    /// @notice Cancel a pending fee-share discount cut. Only the Node Operator owner.
    function cancelFeeShareDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Apply a pending fee-share discount cut once its cooldown has elapsed. Only the Node Operator owner.
    function applyFeeShareDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Set the cooldown for future fee-share discount cuts. Pending requests are unaffected.
    ///         Only DEFAULT_ADMIN_ROLE.
    function setFeeShareDiscountCutCooldown(uint256 feeShareDiscountCutCooldown) external;

    /// @notice Fee-share discount cut cooldown in seconds.
    function getFeeShareDiscountCutCooldown() external view returns (uint256);

    /// @notice Stored fee share discount. Returns zero for an operator that has never set one.
    function getFeeShareDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Pending cut target. Meaningful only while a cooldown is active.
    function getPendingFeeShareDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice End of the pending cut cooldown, or zero if none.
    function getFeeShareDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256);
}
