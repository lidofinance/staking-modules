// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @dev Fee discount state of a Node Operator: zero is both "never set" and "no discount", and
///      `cooldownUntil == 0` means no pending cut. Packed into a single slot.
struct FeeDiscountState {
    uint16 currentFeeDiscount;
    uint16 pendingFeeDiscount;
    uint64 cooldownUntil;
}

/// @dev Sign-magnitude fee modifier of a Node Operator type: `value` basis points are subtracted from
///      the fee kept when `negative` is true, added otherwise. Packed into a single slot.
struct FeeModifier {
    uint248 value;
    bool negative;
}

/*
 * ── Discount scale and per-type ranges ─────────────────────────────────────────
 *
 *    All values are basis points (BP) of the operator's own rewards; the axes
 *    show the fee the operator keeps, the matching discount, and that fee as a
 *    share of the total staking rewards at a 4% module share. One character is
 *    125 BP (half a granularity unit).
 *    An operator picks a discount between zero and its current getMaxFeeDiscount(id);
 *    a negative fee modifier lowers that ceiling below defaultMaxFeeDiscount. The
 *    larger the discount, the lower the fee kept and the higher the allocation
 *    weight. A fee modifier shifts only the effective fee.
 *    ● fee kept (BASE_FEE - discount)   ○ effective (exposed for fee reporting)
 *
 *                                                                                     ┌ BASE_FEE
 * fee kept BP   0                   2500                5000      6250                8750      10000
 *               ├───────────────────┼───────────────────┼─────────┼───────────────────┼─────────┤
 * total at 4%   0%                  1%                  2%        2.5%                3.5%      4%
 * discount BP                       6250                3750      2500                0
 *                                   └ defaultMaxFeeDiscount
 *
 * type A — modifier +1250, effective = fee kept + 1250:
 *   fee kept                        ●─────────────────────────────────────────────────●
 *   effective                                 ○─────────────────────────────────────────────────○
 *
 * type B — modifier -2500, effective = fee kept - 2500; the ceiling drops to 3750:
 *   fee kept                                            ●─────────────────────────────●
 *   effective                       ○─────────────────────────────○
 *
 * A and B both pick discount = 3750: equal weights, different effective fees:
 *   fee kept A = B                                      ●
 *   effective A                                                   ○
 *   effective B                     ○
 *
 * ── Discount cut timeline and oracle frames ────────────────────────────────────
 *
 *    Z is the discount-cut cooldown. Off-chain fee-report construction is
 *    expected to snapshot getEffectiveFee at the report refSlot and use that
 *    snapshot for the corresponding frame. Under this convention, keeping
 *    Z >= frame + margin (a governance invariant, not enforced by this contract)
 *    leaves at least one report at the old fee while the allocation weight already
 *    follows the pending discount. Raising the discount applies at once and cancels
 *    any pending cut. Below, an operator cuts its discount from 3750 to 2500.
 *
 *                            requestFeeDiscount(2500)
 *                            │                       applyFeeDiscountCut()
 *                            │                       │
 * time           ────────────●━━━━━ Z >= frame ━━━━━━●────────────────────────────────────►
 * frames         ├───────────────────────┼───────────────────────┼───────────────────────┤
 *                         frame k                frame k+1               frame k+2
 * weight         ── high ────▼ low ───────────────────────────────────────────────────────
 * pending                    ├───────────────────────┤
 * oracle samples                         ▲ old                   ▲ new                   ▲ new
 * frame billed             old *                  new **                    new
 *
 *    pending: an explicit cancellation or a discount raise clears it; a new
 *    cut overwrites it and restarts the cooldown.
 *    *  under the snapshot convention, the weight is already low while frame k
 *       still uses the old fee.
 *    ** the new fee is used once it is present at the selected refSlot.
 */
/// @notice Per-operator fee discounts and the allocation weight boost derived from them: the larger
///         the discount from BASE_FEE, the higher the operator's allocation weight. The
///         effective fee (the fee kept, adjusted by the type's fee modifier) is exposed for off-chain
///         fee-report construction. In this provider, `Step.threshold` is the minimum discount and
///         `Step.value` is the weight multiplier increment above MAX_BP, so the stored discount feeds
///         the step function directly. The registry itself does not enforce report timing or
///         construction. See the diagrams above.
interface ICustomFeeRegistry is IStepwiseWeightBoost {
    event FeeDiscountSet(uint256 indexed nodeOperatorId, uint256 feeDiscount);
    event FeeDiscountCutRequested(uint256 indexed nodeOperatorId, uint256 pendingFeeDiscount, uint256 cooldownUntil);
    event FeeDiscountCutApplied(uint256 indexed nodeOperatorId, uint256 feeDiscount);
    event FeeDiscountCutCancelled(uint256 indexed nodeOperatorId);
    event DefaultMaxFeeDiscountSet(uint256 defaultMaxFeeDiscount);
    event FeeModifierSet(uint256 indexed curveId, uint256 value, bool negative);
    event FeeDiscountCutCooldownSet(uint256 feeDiscountCutCooldown);

    error InvalidFeeDiscount();
    error SameFeeDiscount();
    error NoPendingFeeDiscountCut();
    error FeeDiscountCutCooldownNotElapsed();
    error InvalidDefaultMaxFeeDiscount();
    error InvalidFeeModifier();
    error InvalidFeeDiscountCutCooldown();

    /// @notice Accounting contract holding bond curves; an operator's type is its curve id.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Fee kept by an operator with no discount, and the base every discount is subtracted from,
    ///         in basis points. A positive fee modifier can still push the effective fee above it.
    function BASE_FEE() external view returns (uint256);

    /// @notice Grid every fee discount, fee modifier, and step threshold must align to, in basis points.
    function FEE_GRANULARITY() external view returns (uint256);

    /// @notice Maximum configurable discount-cut cooldown in seconds.
    function MAX_FEE_DISCOUNT_CUT_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param defaultMaxFeeDiscount Initial discount ceiling: a non-zero multiple of FEE_GRANULARITY below
    ///        BASE_FEE, so the operator always keeps a non-zero fee.
    /// @param feeDiscountCutCooldown Stored cooldown duration in seconds, in
    ///        [1, MAX_FEE_DISCOUNT_CUT_COOLDOWN].
    /// @param steps Initial steps. Thresholds must be FEE_GRANULARITY-aligned and below BASE_FEE; values
    ///        must not exceed MAX_STEP_VALUE.
    function initialize(
        address admin,
        uint256 defaultMaxFeeDiscount,
        uint256 feeDiscountCutCooldown,
        Step[] calldata steps
    ) external;

    /// @notice Request a fee discount. Only the Node Operator owner. Raising it applies immediately and
    ///         cancels any pending cut. A request below the current discount creates or replaces a
    ///         pending cut: allocation weight immediately follows the requested target, while the
    ///         stored discount and the effective fee change only after `applyFeeDiscountCut`. Every
    ///         replacement restarts the cooldown. Requesting the current discount reverts.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param feeDiscount Discount from BASE_FEE in basis points, a multiple of FEE_GRANULARITY within
    ///        [0, getMaxFeeDiscount(nodeOperatorId)].
    function requestFeeDiscount(uint256 nodeOperatorId, uint256 feeDiscount) external;

    /// @notice Cancel a pending discount cut. Only the Node Operator owner. Restores allocation
    ///         weight to the stored discount and reverts if no cut is pending.
    /// @param nodeOperatorId ID of the Node Operator.
    function cancelFeeDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Apply a pending discount cut after its cooldown. Only the Node Operator owner.
    ///         Allocation weight already follows the pending discount. The discount is validated again
    ///         against the current ceiling because a curve or modifier may have changed during cooldown.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyFeeDiscountCut(uint256 nodeOperatorId) external;

    /// @notice Permissionlessly normalize discounts left above the current ceiling after a curve or
    ///         modifier change: each is set to the ceiling and its pending cut is cancelled. Already valid
    ///         discounts are skipped, so duplicate IDs normalize at most once.
    /// @param nodeOperatorIds IDs of the Node Operators.
    /// @return normalizedCount Number of discounts normalized.
    function normalizeFeeDiscounts(uint256[] calldata nodeOperatorIds) external returns (uint256 normalizedCount);

    /// @notice Raise the default discount ceiling. Only DEFAULT_ADMIN_ROLE; must stay below BASE_FEE.
    /// @param defaultMaxFeeDiscount New ceiling in basis points, a non-zero multiple of FEE_GRANULARITY.
    function setDefaultMaxFeeDiscount(uint256 defaultMaxFeeDiscount) external;

    /// @notice Set the fee modifier of an existing Node Operator type (bond curve). Only
    ///         DEFAULT_ADMIN_ROLE. Shifts only the effective fee, never the weight; a negative
    ///         modifier lowers the type's discount ceiling. Reverts for a nonexistent curve.
    /// @param curveId Bond curve ID of the type.
    /// @param value Magnitude in basis points, a multiple of FEE_GRANULARITY: at most
    ///        MAX_BP - BASE_FEE when positive, the default discount ceiling when negative.
    /// @param negative Whether the modifier is subtracted from the fee.
    function setFeeModifier(uint256 curveId, uint256 value, bool negative) external;

    /// @notice Set the cooldown used by future discount-cut requests. Only DEFAULT_ADMIN_ROLE;
    ///         existing pending deadlines are unchanged.
    /// @dev Governance invariant, not enforced on-chain: keep it >= one oracle frame + margin;
    ///      raise it when frames are lengthened.
    /// @param feeDiscountCutCooldown Stored duration in seconds, in [1, MAX_FEE_DISCOUNT_CUT_COOLDOWN].
    function setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) external;

    /// @notice Default discount ceiling in basis points.
    function getDefaultMaxFeeDiscount() external view returns (uint256);

    /// @notice Discount cut cooldown in seconds.
    function getFeeDiscountCutCooldown() external view returns (uint256);

    /// @notice Fee modifier of a Node Operator type.
    /// @param curveId Bond curve ID of the type.
    function getFeeModifier(uint256 curveId) external view returns (FeeModifier memory);

    /// @notice Stored discount of the Node Operator; zero if never set. A pending cut is not reflected
    ///         until applied.
    /// @param nodeOperatorId ID of the Node Operator.
    function getFeeDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Stored pending cut target. Meaningful only while a cooldown is active, since a legitimate
    ///         target may be zero.
    /// @param nodeOperatorId ID of the Node Operator.
    function getPendingFeeDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Earliest timestamp at which the pending cut passes its time check, or zero if none. It does
    ///         not clear automatically once elapsed.
    /// @param nodeOperatorId ID of the Node Operator.
    function getFeeDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Discount ceiling of the Node Operator: the default ceiling lowered by the type's
    ///         negative modifier.
    /// @param nodeOperatorId ID of the Node Operator.
    function getMaxFeeDiscount(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Effective fee in basis points, computed from the stored discount and the fee modifier.
    ///         A pending cut is excluded until applied. Negative results are clamped at zero.
    ///         Exposed for off-chain fee-report construction.
    /// @param nodeOperatorId ID of the Node Operator.
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256);
}
