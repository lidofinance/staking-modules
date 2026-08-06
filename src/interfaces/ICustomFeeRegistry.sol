// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { IStepwiseWeightBoost, Step } from "./IStepwiseWeightBoost.sol";

/// @dev Custom fee state of a Node Operator. `currentFee == 0` means "never set" and reads as
///      `DEFAULT_MAX_FEE`. `cooldownUntil == 0` means no pending increase. Packed into a single slot.
struct OperatorFee {
    uint16 currentFee;
    uint16 pendingFeeIncrease;
    uint64 cooldownUntil;
}

/// @dev Sign-magnitude fee modifier of a Node Operator type: `value` basis points are subtracted from
///      the custom fee when `negative` is true, added otherwise. Packed into a single slot.
struct FeeModifier {
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
 *    DEFAULT_MAX_FEE; a negative fee modifier raises that lower bound above
 *    defaultMinFee. The lower the custom fee, the higher the allocation weight.
 *    A fee modifier shifts only the effective fee.
 *    ● custom (set by the operator)   ○ effective (exposed for fee reporting)
 *
 * portion BP    0                   2500                5000      6250                8750      10000
 *               ├───────────────────┼───────────────────┼─────────┼───────────────────┼─────────┤
 * total at 4%   0%                  1%                  2%        2.5%                3.5%      4%
 *                                   └ defaultMinFee                                   └ DEFAULT_MAX_FEE
 *
 * type A — modifier +1250, effective = custom + 1250:
 *   custom                          ●─────────────────────────────────────────────────●
 *   effective                                 ○─────────────────────────────────────────────────○
 *
 * type B — modifier -2500, effective = custom - 2500; the minimum rises to 5000:
 *   custom                                              ●─────────────────────────────●
 *   effective                       ○─────────────────────────────○
 *
 * A and B both pick custom = 5000: equal weights, different effective fees:
 *   custom A = B                                        ●
 *   effective A                                                   ○
 *   effective B                     ○
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
 *    pending: an explicit cancellation or a decrease clears it; a new increase
 *    overwrites it and restarts the cooldown.
 *    *  under the snapshot convention, the weight is already low while frame k
 *       still uses the old fee.
 *    ** the new fee is used once it is present at the selected refSlot.
 */
/// @notice Per-operator custom fees and the allocation weight boost derived from them: the lower
///         the custom fee, the higher the operator's allocation weight. The effective fee
///         (custom fee adjusted by the fee modifier) is exposed for off-chain fee-report construction.
///         In this provider, `Step.threshold` is the minimum fee discount from DEFAULT_MAX_FEE and
///         `Step.value` is the weight multiplier increment above MAX_BP. The registry itself does not
///         enforce report timing or construction. See the diagrams above.
interface ICustomFeeRegistry is IStepwiseWeightBoost {
    event FeeSet(uint256 indexed nodeOperatorId, uint256 fee);
    event FeeIncreaseRequested(uint256 indexed nodeOperatorId, uint256 pendingFeeIncrease, uint256 cooldownUntil);
    event FeeIncreaseApplied(uint256 indexed nodeOperatorId, uint256 fee);
    event FeeIncreaseCancelled(uint256 indexed nodeOperatorId);
    event DefaultMinFeeSet(uint256 defaultMinFee);
    event FeeModifierSet(uint256 indexed curveId, uint256 value, bool negative);
    event FeeIncreaseCooldownSet(uint256 feeIncreaseCooldown);

    error InvalidFee();
    error SameFee();
    error NoFeeIncreaseCooldown();
    error FeeIncreaseCooldownNotElapsed();
    error InvalidDefaultMinFee();
    error InvalidFeeModifier();
    error InvalidFeeIncreaseCooldown();

    /// @notice Accounting contract holding bond curves; an operator's type is its curve id.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Fee returned for an operator whose fee has never been set, and the inclusive upper
    ///         bound for custom fees, in basis points.
    function DEFAULT_MAX_FEE() external view returns (uint256);

    /// @notice Custom fee granularity in basis points.
    function FEE_STEP() external view returns (uint256);

    /// @notice Maximum configurable fee-increase cooldown in seconds.
    function MAX_FEE_INCREASE_COOLDOWN() external view returns (uint256);

    /// @notice Initialize the provider.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param defaultMinFee Initial minimum custom fee: a non-zero multiple of FEE_STEP below
    ///        DEFAULT_MAX_FEE.
    /// @param feeIncreaseCooldown Stored cooldown duration in seconds, in
    ///        [1, MAX_FEE_INCREASE_COOLDOWN].
    /// @param steps Initial steps. Thresholds must be FEE_STEP-aligned and below DEFAULT_MAX_FEE; values
    ///        must not exceed MAX_STEP_VALUE.
    function initialize(
        address admin,
        uint256 defaultMinFee,
        uint256 feeIncreaseCooldown,
        Step[] calldata steps
    ) external;

    /// @notice Request a custom fee. Only the Node Operator owner. A decrease applies immediately
    ///         and cancels any pending increase. A request above the current fee creates or replaces
    ///         a pending increase: allocation weight immediately follows the requested target, while
    ///         the current and effective fees change only after `applyFeeIncrease`. Every replacement
    ///         restarts the cooldown. Requesting the current fee reverts.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param fee Fee in basis points, a multiple of FEE_STEP within
    ///        [getMinFee(nodeOperatorId), DEFAULT_MAX_FEE].
    function requestFee(uint256 nodeOperatorId, uint256 fee) external;

    /// @notice Cancel a pending fee increase. Only the Node Operator owner. Restores allocation
    ///         weight to the current fee and reverts if no increase is pending.
    /// @param nodeOperatorId ID of the Node Operator.
    function cancelFeeIncrease(uint256 nodeOperatorId) external;

    /// @notice Apply a pending fee increase after its cooldown. Only the Node Operator owner.
    ///         Allocation weight already follows the pending fee. The fee is validated again
    ///         against the current range because a curve or modifier may have changed during cooldown.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyFeeIncrease(uint256 nodeOperatorId) external;

    /// @notice Permissionlessly normalize custom fees left below the current minimum after a curve
    ///         or modifier change: each is set to the minimum and its pending increase is cancelled.
    ///         Operators whose fees are already valid are skipped. Duplicate IDs are allowed and
    ///         normalized at most once.
    /// @param nodeOperatorIds IDs of the Node Operators.
    /// @return normalizedCount Number of fees normalized.
    function normalizeFees(uint256[] calldata nodeOperatorIds) external returns (uint256 normalizedCount);

    /// @notice Lower the default minimum custom fee. Only DEFAULT_ADMIN_ROLE; only downwards and
    ///         never zero.
    /// @param defaultMinFee New minimum in basis points, a non-zero multiple of FEE_STEP.
    function setDefaultMinFee(uint256 defaultMinFee) external;

    /// @notice Set the fee modifier of an existing Node Operator type (bond curve). Only
    ///         DEFAULT_ADMIN_ROLE. Shifts only the effective fee, never the weight; a negative
    ///         modifier raises the type's minimum custom fee. Reverts for a nonexistent curve.
    /// @param curveId Bond curve ID of the type.
    /// @param value Magnitude in basis points, a multiple of FEE_STEP: at most
    ///        MAX_BP - DEFAULT_MAX_FEE when positive, DEFAULT_MAX_FEE - defaultMinFee when negative.
    /// @param negative Whether the modifier is subtracted from the custom fee.
    function setFeeModifier(uint256 curveId, uint256 value, bool negative) external;

    /// @notice Set the cooldown used by future fee-increase requests. Only DEFAULT_ADMIN_ROLE;
    ///         existing pending deadlines are unchanged.
    /// @dev Governance invariant, not enforced on-chain: keep it >= one oracle frame + margin;
    ///      raise it when frames are lengthened.
    /// @param feeIncreaseCooldown Stored duration in seconds, in [1, MAX_FEE_INCREASE_COOLDOWN].
    function setFeeIncreaseCooldown(uint256 feeIncreaseCooldown) external;

    /// @notice Default minimum custom fee in basis points.
    function getDefaultMinFee() external view returns (uint256);

    /// @notice Fee increase cooldown in seconds.
    function getFeeIncreaseCooldown() external view returns (uint256);

    /// @notice Fee modifier of a Node Operator type.
    /// @param curveId Bond curve ID of the type.
    function getFeeModifier(uint256 curveId) external view returns (FeeModifier memory);

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
    ///         negative modifier.
    /// @param nodeOperatorId ID of the Node Operator.
    function getMinFee(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Effective fee in basis points, computed from the current custom fee and fee modifier.
    ///         A pending increase is excluded until applied. Negative results are clamped at zero.
    ///         Exposed for off-chain fee-report construction.
    /// @param nodeOperatorId ID of the Node Operator.
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256);
}
