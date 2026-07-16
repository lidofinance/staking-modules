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
 * ── Fee scale and per-type ranges ─────────────────────────────────────────────
 *
 *    All fees are basis points (BP) of the operator's own rewards; the lower
 *    axis shows the same fee as a share of the total staking rewards at a 4%
 *    module share. One character is one step of 250 BP.
 *    An operator picks a custom fee between defaultMinFee and DEFAULT_MAX_FEE;
 *    the lower the fee, the higher the allocation weight. A type bonus shifts
 *    only the effective fee.
 *    ● custom (set by the operator)   ○ effective (billed by the oracle)
 *
 * portion BP      0         2500      5000 6250      8750 10000
 *                 ├─────────┼─────────┼────┼─────────┼────┤
 * total at 4%     0%        1%        2%   2.5%      3.5% 4%
 *                           └ defaultMinFee          └ DEFAULT_MAX_FEE
 *
 * type A — bonus +1250, effective = custom + 1250:
 *   custom                  ●────────────────────────●
 *   effective                    ○────────────────────────○
 *
 * type B — bonus -2500, effective = custom - 2500; the minimum rises to 5000:
 *   custom                            ●──────────────●
 *   effective               ○──────────────○
 *
 * A and B both pick custom = 5000: equal weights, different effective fees:
 *   custom A = B                      ●
 *   effective A                            ○
 *   effective B             ○
 *
 * ── Fee increase timeline and oracle frames ───────────────────────────────────
 *
 *    Z is the fee-increase cooldown. The oracle reads the fee at the refSlot.
 *    Keeping Z >= frame + margin (a governance invariant) guarantees at least one
 *    report at the old fee while the weight is already low. A decrease needs
 *    no timeline: it applies at once and cancels any pending increase.
 *
 *                         requestFee(6000)
 *                         │                applyFeeIncrease()
 *                         │                │
 * time            ────────●━━ Z >= frame ━━●──────────────────────►
 * frames          ├───────────────┼───────────────┼───────────────┤
 *                      frame k        frame k+1       frame k+2
 * weight          ──high──▼ low ───────────────────────────────────
 * pending                 ├────────────────┤
 * oracle samples                  ▲ old           ▲ new           ▲ new
 * frame billed          old *          new **           new
 *
 *    pending: a decrease cancels it; a new increase overwrites it and restarts
 *    the cooldown.
 *    *  the report the cooldown guarantees: the weight is already low, yet frame k
 *       is still billed at the old fee.
 *    ** the oracle reads the fee at this frame's refSlot, so a change made
 *       mid-frame takes effect for the whole frame.
 */
/// @notice Per-operator custom fees and the allocation weight boost derived from them: the lower
///         the custom fee, the higher the operator's allocation weight. The effective fee
///         (custom + type bonus) is what the fee oracle bills. See the diagrams above.
interface ICustomFeeRegistry is IWeightBoostProvider {
    event FeeSet(uint256 indexed nodeOperatorId, uint256 fee);
    event FeeIncreaseRequested(uint256 indexed nodeOperatorId, uint256 pendingFeeIncrease, uint256 cooldownUntil);
    event FeeIncreaseApplied(uint256 indexed nodeOperatorId, uint256 fee);
    event DefaultMinFeeSet(uint256 defaultMinFee);
    event TypeBonusSet(uint256 indexed curveId, uint256 value, bool negative);
    event FeeIncreaseCooldownSet(uint256 feeIncreaseCooldown);

    error ZeroAdminAddress();
    error SenderIsNotOperatorOwner();
    error InvalidFee();
    error SameFee();
    error FeeNotBelowMinFee();
    error FeeIncreaseCooldownActive();
    error NoFeeIncreaseCooldown();
    error FeeIncreaseCooldownNotElapsed();
    error InvalidDefaultMinFee();
    error InvalidTypeBonus();
    error InvalidFeeIncreaseCooldown();

    /// @notice Curated module address.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract holding bond curves; an operator's type is its curve id.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice MetaRegistry notified via `notifyWeightBoostChanged` on weight changes.
    function META_REGISTRY() external view returns (IMetaRegistry);

    /// @notice The starting fee of every operator, in basis points; a custom fee can only go
    ///         below it.
    function DEFAULT_MAX_FEE() external view returns (uint256);

    /// @notice Slope of the weight line: multiplier basis points per FEE_STEP below DEFAULT_MAX_FEE.
    function WEIGHT_BOOST_PER_STEP() external view returns (uint256);

    /// @notice Custom fee granularity in basis points.
    function FEE_STEP() external view returns (uint256);

    /// @notice Initialize the registry.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    /// @param defaultMinFee Initial minimum custom fee: a non-zero multiple of FEE_STEP below
    ///        DEFAULT_MAX_FEE.
    /// @param feeIncreaseCooldown Fee increase cooldown in seconds, non-zero.
    function initialize(address admin, uint256 defaultMinFee, uint256 feeIncreaseCooldown) external;

    /// @notice Request a custom fee. Only the Node Operator owner. A decrease applies immediately
    ///         and cancels any pending increase; an increase drops the weight at once but applies
    ///         only via `applyFeeIncrease` after the cooldown. A repeated increase overwrites the
    ///         pending one and restarts the cooldown.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param fee Fee in basis points: a multiple of FEE_STEP within
    ///        [getMinFee(id), DEFAULT_MAX_FEE].
    function requestFee(uint256 nodeOperatorId, uint256 fee) external;

    /// @notice Apply a pending fee increase after its cooldown. Only the Node Operator owner.
    ///         The weight already follows the pending fee.
    /// @param nodeOperatorId ID of the Node Operator.
    function applyFeeIncrease(uint256 nodeOperatorId) external;

    /// @notice Permissionlessly raise a custom fee left below the type's minimum (after a bonus
    ///         change) exactly to that minimum. Immediate; reverts while an increase is pending.
    /// @param nodeOperatorId ID of the Node Operator.
    function restoreFeeToMin(uint256 nodeOperatorId) external;

    /// @notice Lower the default minimum custom fee. Only downwards and never zero.
    /// @param defaultMinFee New minimum in basis points, a non-zero multiple of FEE_STEP.
    function setDefaultMinFee(uint256 defaultMinFee) external;

    /// @notice Set the fee bonus of a Node Operator type (bond curve). Shifts only the effective
    ///         fee, never the weight; a negative bonus raises the type's minimum custom fee.
    /// @param curveId Bond curve ID of the type.
    /// @param value Magnitude in basis points, a multiple of FEE_STEP: at most
    ///        MAX_BP - DEFAULT_MAX_FEE when positive, DEFAULT_MAX_FEE - defaultMinFee when negative.
    /// @param negative Whether the bonus is subtracted from the custom fee.
    function setTypeBonus(uint256 curveId, uint256 value, bool negative) external;

    /// @notice Set the fee increase cooldown.
    /// @dev Governance invariant, not enforced on-chain: keep it >= one oracle frame + margin;
    ///      raise it when frames are lengthened.
    /// @param feeIncreaseCooldown Cooldown in seconds, non-zero.
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

    /// @notice Minimum custom fee of the Node Operator: the default minimum raised by the type's
    ///         negative bonus.
    /// @param nodeOperatorId ID of the Node Operator.
    function getMinFee(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Effective fee of the Node Operator: custom fee + type bonus, clamped at zero.
    ///         The reward share the fee oracle bills.
    /// @param nodeOperatorId ID of the Node Operator.
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256);
}
