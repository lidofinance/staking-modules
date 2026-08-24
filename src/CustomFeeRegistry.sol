// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { ICustomFeeRegistry, FeeDiscountState } from "./interfaces/ICustomFeeRegistry.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Per-operator fee discounts and the allocation weight boost derived from them.
contract CustomFeeRegistry is ICustomFeeRegistry, StepwiseWeightBoost {
    /// @custom:storage-location erc7201:CustomFeeRegistry
    struct CustomFeeRegistryStorage {
        uint256 feeDiscountCutCooldown;
        mapping(uint256 nodeOperatorId => FeeDiscountState) feeDiscounts;
    }

    uint256 public constant FEE_DISCOUNT_STEP = MAX_BP / 100;
    uint256 public constant MAX_FEE_DISCOUNT_CUT_COOLDOWN = 365 days;

    // keccak256(abi.encode(uint256(keccak256("CustomFeeRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUSTOM_FEE_REGISTRY_STORAGE_LOCATION =
        0x231651de169707bf46042ddc0065dcd629da5632e3ccd31978f43f09a90a1200;

    /// @param module Curated module address.
    constructor(address module) StepwiseWeightBoost(module) {}

    /// @inheritdoc ICustomFeeRegistry
    function initialize(address admin, uint256 feeDiscountCutCooldown, Step[] calldata steps) external initializer {
        _setFeeDiscountCutCooldown(feeDiscountCutCooldown);
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc ICustomFeeRegistry
    function requestFeeDiscount(uint256 nodeOperatorId, uint256 feeDiscount) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);
        if (feeDiscount > MAX_BP || feeDiscount % FEE_DISCOUNT_STEP != 0) revert InvalidFeeDiscount();

        CustomFeeRegistryStorage storage $ = _storage();
        FeeDiscountState storage state = $.feeDiscounts[nodeOperatorId];
        uint256 currentFeeDiscount = state.currentFeeDiscount;
        if (feeDiscount == currentFeeDiscount) revert SameFeeDiscount();

        uint256 previousTargetFeeDiscount = _getTargetFeeDiscount(state);

        if (feeDiscount > currentFeeDiscount) {
            if (state.cooldownUntil != 0) _cancelFeeDiscountCut(nodeOperatorId);
            state.currentFeeDiscount = uint16(feeDiscount);
            emit FeeDiscountSet(nodeOperatorId, feeDiscount);
        } else {
            uint256 cooldownUntil = block.timestamp + $.feeDiscountCutCooldown;
            state.pendingFeeDiscount = uint16(feeDiscount);
            state.cooldownUntil = uint64(cooldownUntil);
            emit FeeDiscountCutRequested(nodeOperatorId, feeDiscount, cooldownUntil);
        }

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, previousTargetFeeDiscount, feeDiscount);
    }

    /// @inheritdoc ICustomFeeRegistry
    function cancelFeeDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeDiscountCut();

        uint256 pendingFeeDiscount = state.pendingFeeDiscount;
        uint256 currentFeeDiscount = state.currentFeeDiscount;
        _cancelFeeDiscountCut(nodeOperatorId);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(nodeOperatorId, pendingFeeDiscount, currentFeeDiscount);
    }

    /// @inheritdoc ICustomFeeRegistry
    function applyFeeDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeDiscountCut();
        if (state.cooldownUntil > block.timestamp) revert FeeDiscountCutCooldownNotElapsed();

        uint256 feeDiscount = state.pendingFeeDiscount;
        state.currentFeeDiscount = uint16(feeDiscount);
        state.pendingFeeDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeDiscountCutApplied(nodeOperatorId, feeDiscount);
        // No notification: the allocation weight changed when the cut was requested.
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeDiscountCutCooldown(feeDiscountCutCooldown);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscountCutCooldown() external view returns (uint256) {
        return _storage().feeDiscountCutCooldown;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getPendingFeeDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].pendingFeeDiscount;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].cooldownUntil;
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP =
            MAX_BP +
            StepwiseWeightBoost._stepValueAt(_getTargetFeeDiscount(_storage().feeDiscounts[nodeOperatorId]));
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeDiscounts[nodeOperatorId].currentFeeDiscount;
    }

    function _cancelFeeDiscountCut(uint256 nodeOperatorId) internal {
        FeeDiscountState storage state = _storage().feeDiscounts[nodeOperatorId];
        state.pendingFeeDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeDiscountCutCancelled(nodeOperatorId);
    }

    function _setFeeDiscountCutCooldown(uint256 feeDiscountCutCooldown) internal {
        if (feeDiscountCutCooldown == 0 || feeDiscountCutCooldown > MAX_FEE_DISCOUNT_CUT_COOLDOWN) {
            revert InvalidFeeDiscountCutCooldown();
        }
        _storage().feeDiscountCutCooldown = feeDiscountCutCooldown;
        emit FeeDiscountCutCooldownSet(feeDiscountCutCooldown);
    }

    function _getTargetFeeDiscount(FeeDiscountState storage state) internal view returns (uint256) {
        return state.cooldownUntil != 0 ? state.pendingFeeDiscount : state.currentFeeDiscount;
    }

    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold <= MAX_BP && step.threshold % FEE_DISCOUNT_STEP == 0;
    }

    function _storage() internal pure returns (CustomFeeRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CUSTOM_FEE_REGISTRY_STORAGE_LOCATION
        }
    }
}
