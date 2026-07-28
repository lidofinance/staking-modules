// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IMetaRegistry } from "./IMetaRegistry.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @dev Custom fee state of a Node Operator. `currentFee == 0` means "never set" and reads as
///      `DEFAULT_MAX_FEE`. `cooldownUntil == 0` means no pending increase. Packed into a single slot.
struct OperatorFee {
    uint16 currentFee;
    uint16 pendingFeeIncrease;
    uint64 cooldownUntil;
}

/// @dev Sign-magnitude fee bonus of a Node Operator type: `value` basis points are subtracted from
///      the custom fee when `negative` is true, added otherwise. Packed into a single slot.
struct TypeBonus {
    uint248 value;
    bool negative;
}

/*
 * ── Fee scale and per-type ranges ──────────────────────────────────────────────
 *
 *    All fees are basis points (BP) of the operator's own rewards; the lower
 *    axis shows the same fee as a share of the total staking rewards at a 4%
 *    module share. One character is 125 BP (half a fee step).
 *    An operator picks a custom fee between its current getMinFee(id) and
 *    DEFAULT_MAX_FEE; a negative type bonus raises that lower bound above
 *    defaultMinFee. The lower the custom fee, the higher the allocation weight.
 *    A type bonus shifts only the effective fee.
 *    ● custom (set by the operator)   ○ effective (exposed for fee reporting)
 *
 * portion BP    0                   2500                5000      6250                8750      10000
 *               ├───────────────────┼───────────────────┼─────────┼───────────────────┼─────────┤
 * total at 4%   0%                  1%                  2%        2.5%                3.5%      4%
 *                                   └ defaultMinFee                                   └ DEFAULT_MAX_FEE
 *
 * type A — bonus +1250, effective = custom + 1250:
 *   custom                          ●─────────────────────────────────────────────────●
 *   effective                                 ○─────────────────────────────────────────────────○
 *
 * type B — bonus -2500, effective = custom - 2500; the minimum rises to 5000:
 *   custom                                              ●─────────────────────────────●
 *   effective                       ○─────────────────────────────○
 *
 * A and B both pick custom = 5000: equal weights, different effective fees:
 *   custom A = B                                        ●
 *   effective A                                                   ○
 *   effective B                     ○
 *
 * ── Custom fee to allocation weight ────────────────────────────────────────────
 *
 *    The weight multiplier depends on the fee only, never on a type bonus — on
 *    the custom fee, or the pending target while an increase is pending (see the
 *    timeline below). Two things are fixed: 1x at DEFAULT_MAX_FEE and a straight
 *    slope of WEIGHT_BOOST_PER_STEP (400 BP) per FEE_STEP (250 BP) of discount.
 *    The minimum is a parameter. For the illustrated defaultMinFee of 2500, the
 *    multiplier at the minimum is 2x. Governance may lower the minimum along the
 *    same line. Since it must remain a non-zero multiple of FEE_STEP, the lowest
 *    reachable fee is 250 and the highest reachable multiplier is 2.36x.
 *
 * multiplier
 *   2.4x ┤╲                                            custom 0: unreachable
 *   2.2x ┤      ╲                                      below 2500 — only if DAO lowers the minimum
 *   2.0x ┤            ●                                2500 (illustrated defaultMinFee): 2x
 *   1.8x ┤                  ╲
 *   1.6x ┤                        ╲
 *   1.4x ┤                              ╲
 *   1.2x ┤                                    ╲
 *   1.0x ┤                                          ●  8750 (DEFAULT_MAX_FEE, unset): 1x
 *        └┬           ┬                             ┬─► custom fee, portion BP
 *         0           2500                          8750
 *                     ├────reachable when defaultMinFee = 2500────┤
 *
 * ── Fee increase timeline and oracle frames ────────────────────────────────────
 *
 *    Z is the fee-increase cooldown. Off-chain fee-report construction is expected
 *    to snapshot getEffectiveFee at the report refSlot and use that snapshot for
 *    the corresponding frame. Under this convention, keeping Z >= frame + margin
 *    (a governance invariant, not enforced by this contract) leaves at least one
 *    report at the old fee while the allocation weight already follows the pending
 *    increase. A decrease applies at once and cancels any pending increase.
 *
 *                            requestFee(6000)
 *                            │                       applyFeeIncrease()
 *                            │                       │
 * time           ────────────●━━━━━ Z >= frame ━━━━━━●────────────────────────────────────►
 * frames         ├───────────────────────┼───────────────────────┼───────────────────────┤
 *                         frame k                frame k+1               frame k+2
 * weight         ── high ────▼ low ───────────────────────────────────────────────────────
 * pending                    ├───────────────────────┤
 * oracle samples                         ▲ old                   ▲ new                   ▲ new
 * frame billed             old *                  new **                    new
 *
 *    pending: a decrease cancels it; a new increase overwrites it and restarts
 *    the cooldown.
 *    *  under the snapshot convention, the weight is already low while frame k
 *       still uses the old fee.
 *    ** the new fee is used once it is present at the selected refSlot.
 */
/// @notice Per-operator custom fees and the allocation weight boost derived from them: the lower
///         the custom fee, the higher the operator's allocation weight. The effective fee
///         (custom + type bonus) is exposed for off-chain fee-report construction. The registry
///         itself does not enforce report timing or construction. See the diagrams above.
interface ICustomFeeRegistry is IWeightBoostProvider {
    /// @notice Emitted when a decrease or normalization sets the current fee immediately.
    event FeeSet(uint256 indexed nodeOperatorId, uint256 fee);
    /// @notice Emitted when a pending increase is created or replaced.
    event FeeIncreaseRequested(uint256 indexed nodeOperatorId, uint256 pendingFeeIncrease, uint256 cooldownUntil);
    /// @notice Emitted when a pending increase becomes the current fee and pending state is cleared.
    event FeeIncreaseApplied(uint256 indexed nodeOperatorId, uint256 fee);
    /// @notice Emitted when a pending increase is cancelled by a fee request or normalization.
    event FeeIncreaseCancelled(uint256 indexed nodeOperatorId);
    /// @notice Emitted during initialization and whenever the default minimum is lowered.
    event DefaultMinFeeSet(uint256 defaultMinFee);
    /// @notice Emitted when the sign and magnitude of an existing curve's type bonus are stored.
    event TypeBonusSet(uint256 indexed curveId, uint256 value, bool negative);
    /// @notice Emitted when the cooldown for future requests is set; existing deadlines are unchanged.
    event FeeIncreaseCooldownSet(uint256 feeIncreaseCooldown);

    /// @notice The initializer admin is the zero address.
    error ZeroAdminAddress();
    /// @notice The caller is not the Node Operator owner.
    error SenderIsNotOperatorOwner();
    /// @notice A requested or pending fee is outside its current valid range or is not step-aligned.
    error InvalidFee();
    /// @notice The requested fee equals the current fee and there is no pending increase to cancel.
    error SameFee();
    /// @notice Strict normalization was requested while the current fee was already valid.
    error FeeNotBelowMinFee();
    /// @notice The Node Operator has no pending fee increase.
    error NoFeeIncreaseCooldown();
    /// @notice The pending increase cannot be applied before its stored deadline.
    error FeeIncreaseCooldownNotElapsed();
    /// @notice The default minimum is zero, not step-aligned, or not below its required upper bound.
    error InvalidDefaultMinFee();
    /// @notice The type bonus exceeds its sign-dependent bound or is not step-aligned.
    error InvalidTypeBonus();
    /// @notice The duration or resulting absolute deadline cannot be represented by uint64.
    error InvalidFeeIncreaseCooldown();

    /// @notice Curated module address.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract holding bond curves; an operator's type is its curve id.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice MetaRegistry notified when fee operations may require an allocation-weight refresh.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice Fee returned for an operator whose fee has never been set, and the inclusive upper
    ///         bound for custom fees, in basis points.
    function DEFAULT_MAX_FEE() external view returns (uint256);

    /// @notice Slope of the weight line: multiplier basis points per FEE_STEP below DEFAULT_MAX_FEE.
    function WEIGHT_BOOST_PER_STEP() external view returns (uint256);

    /// @notice Custom fee granularity in basis points.
    function FEE_STEP() external view returns (uint256);

    /// @notice Initialize the registry.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param defaultMinFee Initial minimum custom fee: a non-zero multiple of FEE_STEP below
    ///        DEFAULT_MAX_FEE.
    /// @param feeIncreaseCooldown Stored cooldown duration in seconds, in [1, type(uint64).max].
    ///        A later increase request also requires its absolute deadline to fit uint64.
    function initialize(address admin, uint256 defaultMinFee, uint256 feeIncreaseCooldown) external;

    /// @notice Request a custom fee. Only the Node Operator owner. A decrease applies immediately
    ///         and cancels any pending increase. A request above the current fee creates or replaces
    ///         a pending increase: allocation weight immediately follows the requested target, while
    ///         the current and effective fees change only after `applyFeeIncrease`. Every replacement
    ///         restarts the cooldown. Requesting the current fee cancels a pending increase; without
    ///         a pending increase it reverts.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param fee Fee in basis points. To set or schedule it, the value must be a multiple of
    ///        FEE_STEP within [getMinFee(nodeOperatorId), DEFAULT_MAX_FEE]. As an exception,
    ///        requesting the current fee cancels a pending increase even if the current fee has
    ///        fallen below the minimum. A new deadline must fit uint64.
    function requestFee(uint256 nodeOperatorId, uint256 fee) external;

    /// @notice Apply a pending fee increase after its cooldown. Only the Node Operator owner.
    ///         Allocation weight already follows the pending fee. The fee is validated again
    ///         against the current range because a curve or bonus may have changed during cooldown.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyFeeIncrease(uint256 nodeOperatorId) external;

    /// @notice Permissionlessly normalize a custom fee left below the current minimum after a
    ///         curve or bonus change. Sets it to the minimum and cancels any pending increase.
    /// @param nodeOperatorId ID of the Node Operator.
    function normalizeFee(uint256 nodeOperatorId) external;

    /// @notice Permissionlessly normalize multiple custom fees. Operators whose fees are already
    ///         valid are skipped. Duplicate IDs are allowed and normalized at most once.
    /// @param nodeOperatorIds IDs of the Node Operators.
    /// @return normalizedCount Number of fees normalized.
    function normalizeFees(uint256[] calldata nodeOperatorIds) external returns (uint256 normalizedCount);

    /// @notice Lower the default minimum custom fee. Only DEFAULT_ADMIN_ROLE; only downwards and
    ///         never zero.
    /// @param defaultMinFee New minimum in basis points, a non-zero multiple of FEE_STEP.
    function setDefaultMinFee(uint256 defaultMinFee) external;

    /// @notice Set the fee bonus of an existing Node Operator type (bond curve). Only
    ///         DEFAULT_ADMIN_ROLE. Shifts only the effective fee, never the weight; a negative
    ///         bonus raises the type's minimum custom fee. Reverts for a nonexistent curve.
    /// @param curveId Bond curve ID of the type.
    /// @param value Magnitude in basis points, a multiple of FEE_STEP: at most
    ///        MAX_BP - DEFAULT_MAX_FEE when positive, DEFAULT_MAX_FEE - defaultMinFee when negative.
    /// @param negative Whether the bonus is subtracted from the custom fee.
    function setTypeBonus(uint256 curveId, uint256 value, bool negative) external;

    /// @notice Set the cooldown used by future fee-increase requests. Only DEFAULT_ADMIN_ROLE;
    ///         existing pending deadlines are unchanged.
    /// @dev Governance invariant, not enforced on-chain: keep it >= one oracle frame + margin;
    ///      raise it when frames are lengthened.
    /// @param feeIncreaseCooldown Stored duration in seconds, in [1, type(uint64).max]. A later
    ///        increase request also requires its absolute deadline to fit uint64.
    function setFeeIncreaseCooldown(uint256 feeIncreaseCooldown) external;

    /// @notice Default minimum custom fee in basis points.
    function getDefaultMinFee() external view returns (uint256);

    /// @notice Fee increase cooldown in seconds.
    function getFeeIncreaseCooldown() external view returns (uint256);

    /// @notice Fee bonus of a Node Operator type.
    /// @param curveId Bond curve ID of the type.
    function getTypeBonus(uint256 curveId) external view returns (TypeBonus memory);

    /// @notice Custom fee of the Node Operator; DEFAULT_MAX_FEE if never set. While an increase
    ///         is pending, the old fee is returned until `applyFeeIncrease`.
    /// @param nodeOperatorId ID of the Node Operator.
    function getFee(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Stored pending increase target, or zero if none. It remains pending after the
    ///         deadline until applied, cancelled, overwritten, or cleared by normalization.
    /// @param nodeOperatorId ID of the Node Operator.
    function getPendingFeeIncrease(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Earliest timestamp at which the pending increase passes its time check, or zero if
    ///         none. The deadline does not clear automatically, and application remains subject to
    ///         current fee validation.
    /// @param nodeOperatorId ID of the Node Operator.
    function getFeeIncreaseCooldownUntil(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Minimum custom fee of the Node Operator: the default minimum raised by the type's
    ///         negative bonus.
    /// @param nodeOperatorId ID of the Node Operator.
    function getMinFee(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Effective fee in basis points, computed from the current custom fee and type bonus.
    ///         A pending increase is excluded until applied. Negative results are clamped at zero.
    ///         Exposed for off-chain fee-report construction.
    /// @param nodeOperatorId ID of the Node Operator.
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256);
}
