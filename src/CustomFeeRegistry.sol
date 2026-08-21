// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBondCurve } from "./interfaces/IBondCurve.sol";
import { ICustomFeeRegistry, FeeDiscountState, FeeModifier } from "./interfaces/ICustomFeeRegistry.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Per-operator fee discounts and the allocation weight boost derived from them. See
///         ICustomFeeRegistry for the model.
contract CustomFeeRegistry is ICustomFeeRegistry, StepwiseWeightBoost {
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:CustomFeeRegistry
    struct CustomFeeRegistryStorage {
        uint256 defaultMaxFeeDiscount;
        uint256 feeDiscountCutCooldown;
        mapping(uint256 curveId => FeeModifier) feeModifier;
        mapping(uint256 nodeOperatorId => FeeDiscountState) feeDiscounts;
    }

    // All fees and discounts are basis points of the operator's own rewards.
    uint256 public constant FEE_GRANULARITY = 250; // 2.5%
    // The operator's share of the module's rewards, mirroring the protocol reward share config.
    uint256 public constant BASE_FEE = 8_750; // 87.5% of the module fee on SR
    uint256 public constant MAX_FEE_DISCOUNT_CUT_COOLDOWN = 365 days;

    IAccounting public immutable ACCOUNTING;

    // keccak256(abi.encode(uint256(keccak256("CustomFeeRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUSTOM_FEE_REGISTRY_STORAGE_LOCATION =
        0x231651de169707bf46042ddc0065dcd629da5632e3ccd31978f43f09a90a1200;

    /// @param module Curated module address.
    constructor(address module) StepwiseWeightBoost(module) {
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
    }

    /// @inheritdoc ICustomFeeRegistry
    function initialize(
        address admin,
        uint256 defaultMaxFeeDiscount,
        uint256 feeDiscountCutCooldown,
        Step[] calldata steps
    ) external initializer {
        _setDefaultMaxFeeDiscount(defaultMaxFeeDiscount);
        _setFeeDiscountCutCooldown(feeDiscountCutCooldown);
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc ICustomFeeRegistry
    function requestFeeDiscount(uint256 nodeOperatorId, uint256 feeDiscount) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        uint256 currentFeeDiscount = _storage().feeDiscounts[nodeOperatorId].currentFeeDiscount;
        if (feeDiscount == currentFeeDiscount) revert SameFeeDiscount();

        _validateFeeDiscount(nodeOperatorId, feeDiscount);

        if (feeDiscount > currentFeeDiscount) {
            _setCurrentFeeDiscount(nodeOperatorId, feeDiscount);
        } else {
            _scheduleFeeDiscountCut(nodeOperatorId, feeDiscount);
        }
    }

    /// @inheritdoc ICustomFeeRegistry
    function cancelFeeDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeDiscountCut();

        uint256 previousFeeDiscount = _getTargetFeeDiscount(nodeOperatorId);
        uint256 currentFeeDiscount = state.currentFeeDiscount;

        state.pendingFeeDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeDiscountCutCancelled(nodeOperatorId);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, previousFeeDiscount, currentFeeDiscount);
    }

    /// @inheritdoc ICustomFeeRegistry
    function applyFeeDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeDiscountCut();
        if (state.cooldownUntil > block.timestamp) revert FeeDiscountCutCooldownNotElapsed();

        uint16 pendingFeeDiscount = state.pendingFeeDiscount;
        // A curve or modifier change during the cooldown may have invalidated it. If so, the cut has to be
        // dropped via `cancelFeeDiscountCut` and a new discount requested if still needed.
        _validateFeeDiscount(nodeOperatorId, pendingFeeDiscount);

        state.currentFeeDiscount = pendingFeeDiscount;
        state.pendingFeeDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeDiscountCutApplied(nodeOperatorId, pendingFeeDiscount);
        // No notification: the allocation weight changed when the cut was requested.
    }

    /// @inheritdoc ICustomFeeRegistry
    function normalizeFeeDiscounts(uint256[] calldata nodeOperatorIds) external returns (uint256[] memory normalized) {
        normalized = new uint256[](nodeOperatorIds.length);
        uint256 count;
        for (uint256 i; i < nodeOperatorIds.length; ++i) {
            uint256 nodeOperatorId = nodeOperatorIds[i];
            if (_normalizeFeeDiscount(nodeOperatorId)) {
                normalized[count] = nodeOperatorId;
                ++count;
            }
        }

        assembly ("memory-safe") {
            // Shrink the array to the operators normalized; the unused tail stays allocated but unreferenced.
            mstore(normalized, count)
        }
    }

    /// @inheritdoc ICustomFeeRegistry
    function setDefaultMaxFeeDiscount(uint256 defaultMaxFeeDiscount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultMaxFeeDiscount(defaultMaxFeeDiscount);
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeModifier(uint256 curveId, uint256 value, bool negative) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (curveId >= ACCOUNTING.getCurvesCount()) revert IBondCurve.InvalidBondCurveId();

        CustomFeeRegistryStorage storage $ = _storage();
        // Positive: keeps the effective fee within MAX_BP. Negative: keeps the per-type ceiling non-negative.
        uint256 maxValue = negative ? $.defaultMaxFeeDiscount : MAX_BP - BASE_FEE;
        if (value > maxValue || value % FEE_GRANULARITY != 0) revert InvalidFeeModifier();

        $.feeModifier[curveId] = FeeModifier({ value: value.toUint248(), negative: negative });
        emit FeeModifierSet(curveId, value, negative);
        // No weight notification: the modifier shifts only the effective fee.
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeDiscountCutCooldown(feeDiscountCutCooldown);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getDefaultMaxFeeDiscount() external view returns (uint256) {
        return _storage().defaultMaxFeeDiscount;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscountCutCooldown() external view returns (uint256) {
        return _storage().feeDiscountCutCooldown;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeModifier(uint256 curveId) external view returns (FeeModifier memory) {
        return _storage().feeModifier[curveId];
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].currentFeeDiscount;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getPendingFeeDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].pendingFeeDiscount;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].cooldownUntil;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getMaxFeeDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _getMaxFeeDiscount(nodeOperatorId);
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = MAX_BP + StepwiseWeightBoost._stepValueAt(_getTargetFeeDiscount(nodeOperatorId));
    }

    /// @inheritdoc ICustomFeeRegistry
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256) {
        uint256 currentFee = _asFee(_storage().feeDiscounts[nodeOperatorId].currentFeeDiscount);
        FeeModifier storage feeModifier = _storage().feeModifier[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        if (feeModifier.negative) {
            // A curve or modifier change can leave the fee below the negative modifier.
            return currentFee > feeModifier.value ? currentFee - feeModifier.value : 0;
        }

        // The modifier bounds keep the sum within MAX_BP.
        return currentFee + feeModifier.value;
    }

    function _setCurrentFeeDiscount(uint256 nodeOperatorId, uint256 newCurrentFeeDiscount) internal {
        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        bool hadPendingCut = state.cooldownUntil != 0;
        uint256 previousFeeDiscount = _getTargetFeeDiscount(nodeOperatorId);

        state.currentFeeDiscount = newCurrentFeeDiscount.toUint16();
        state.pendingFeeDiscount = 0;
        state.cooldownUntil = 0;
        if (hadPendingCut) emit FeeDiscountCutCancelled(nodeOperatorId);
        emit FeeDiscountSet(nodeOperatorId, newCurrentFeeDiscount);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(
            nodeOperatorId,
            previousFeeDiscount,
            newCurrentFeeDiscount
        );
    }

    function _scheduleFeeDiscountCut(uint256 nodeOperatorId, uint256 pendingFeeDiscount) internal {
        CustomFeeRegistryStorage storage $ = _storage();
        FeeDiscountState storage state = $.feeDiscounts[nodeOperatorId];
        uint256 previousFeeDiscount = _getTargetFeeDiscount(nodeOperatorId);
        uint256 cooldownUntil = block.timestamp + $.feeDiscountCutCooldown;
        state.pendingFeeDiscount = pendingFeeDiscount.toUint16();
        state.cooldownUntil = cooldownUntil.toUint64();
        emit FeeDiscountCutRequested(nodeOperatorId, pendingFeeDiscount, cooldownUntil);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, previousFeeDiscount, pendingFeeDiscount);
    }

    /// @dev Only upwards, so discounts already set stay valid; storage is zero on initialization. The
    ///      BASE_FEE bound keeps a non-zero fee for the operator.
    function _setDefaultMaxFeeDiscount(uint256 defaultMaxFeeDiscount) internal {
        CustomFeeRegistryStorage storage $ = _storage();
        if (
            defaultMaxFeeDiscount <= $.defaultMaxFeeDiscount ||
            defaultMaxFeeDiscount >= BASE_FEE ||
            defaultMaxFeeDiscount % FEE_GRANULARITY != 0
        ) {
            revert InvalidDefaultMaxFeeDiscount();
        }
        $.defaultMaxFeeDiscount = defaultMaxFeeDiscount;
        emit DefaultMaxFeeDiscountSet(defaultMaxFeeDiscount);
    }

    function _setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) internal {
        if (feeDiscountCutCooldown == 0 || feeDiscountCutCooldown > MAX_FEE_DISCOUNT_CUT_COOLDOWN) {
            revert InvalidFeeDiscountCutCooldown();
        }
        _storage().feeDiscountCutCooldown = feeDiscountCutCooldown;
        emit FeeDiscountCutCooldownSet(feeDiscountCutCooldown);
    }

    function _normalizeFeeDiscount(uint256 nodeOperatorId) internal returns (bool normalized) {
        uint256 maxFeeDiscount = _getMaxFeeDiscount(nodeOperatorId);
        if (_storage().feeDiscounts[nodeOperatorId].currentFeeDiscount <= maxFeeDiscount) return false;

        _setCurrentFeeDiscount(nodeOperatorId, maxFeeDiscount);
        return true;
    }

    function _validateFeeDiscount(uint256 nodeOperatorId, uint256 feeDiscount) internal view {
        if (feeDiscount > _getMaxFeeDiscount(nodeOperatorId) || feeDiscount % FEE_GRANULARITY != 0) {
            revert InvalidFeeDiscount();
        }
    }

    /// @dev A negative modifier lowers the per-type ceiling, keeping the effective fee at or above the
    ///      protocol floor. Stored discounts may exceed it until normalized.
    function _getMaxFeeDiscount(uint256 nodeOperatorId) internal view returns (uint256) {
        CustomFeeRegistryStorage storage $ = _storage();
        FeeModifier storage feeModifier = $.feeModifier[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        uint256 maxFeeDiscount = $.defaultMaxFeeDiscount;
        // NOTE: No underflow: a negative modifier is capped at the default ceiling, which only grows.
        return feeModifier.negative ? maxFeeDiscount - feeModifier.value : maxFeeDiscount;
    }

    /// @dev The discount the allocation weight follows: the pending one while a cut is scheduled.
    function _getTargetFeeDiscount(uint256 nodeOperatorId) internal view returns (uint256) {
        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        return state.cooldownUntil != 0 ? state.pendingFeeDiscount : state.currentFeeDiscount;
    }

    /// @dev The only crossing back into fee space, for the off-chain reward distribution.
    function _asFee(uint256 feeDiscount) internal pure returns (uint256) {
        return BASE_FEE - feeDiscount;
    }

    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold < BASE_FEE && step.threshold % FEE_GRANULARITY == 0;
    }

    function _storage() internal pure returns (CustomFeeRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CUSTOM_FEE_REGISTRY_STORAGE_LOCATION
        }
    }
}
