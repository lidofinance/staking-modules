// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { ICustomFeeRegistry, FeeShareDiscountState } from "./interfaces/ICustomFeeRegistry.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Per-operator fee share discounts and the allocation weight boost derived from them.
contract CustomFeeRegistry is ICustomFeeRegistry, StepwiseWeightBoost {
    /// @custom:storage-location erc7201:CustomFeeRegistry
    struct CustomFeeRegistryStorage {
        uint256 feeShareDiscountCutCooldown;
        mapping(uint256 nodeOperatorId => FeeShareDiscountState) feeShareDiscounts;
    }

    uint256 public constant FEE_SHARE_DISCOUNT_STEP = MAX_BP / 100;
    uint256 public constant MAX_FEE_SHARE_DISCOUNT_CUT_COOLDOWN = 365 days;

    // keccak256(abi.encode(uint256(keccak256("CustomFeeRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUSTOM_FEE_REGISTRY_STORAGE_LOCATION =
        0x231651de169707bf46042ddc0065dcd629da5632e3ccd31978f43f09a90a1200;

    /// @param module Curated module address.
    constructor(address module) StepwiseWeightBoost(module) {}

    /// @inheritdoc ICustomFeeRegistry
    function initialize(
        address admin,
        uint256 feeShareDiscountCutCooldown,
        Step[] calldata steps
    ) external initializer {
        _setFeeShareDiscountCutCooldown(feeShareDiscountCutCooldown);
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc ICustomFeeRegistry
    function requestFeeShareDiscount(uint256 nodeOperatorId, uint256 feeShareDiscount) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);
        if (feeShareDiscount > MAX_BP || feeShareDiscount % FEE_SHARE_DISCOUNT_STEP != 0)
            revert InvalidFeeShareDiscount();

        CustomFeeRegistryStorage storage $ = _storage();
        FeeShareDiscountState storage state = $.feeShareDiscounts[nodeOperatorId];
        uint256 currentFeeShareDiscount = state.currentFeeShareDiscount;
        if (feeShareDiscount == currentFeeShareDiscount) revert SameFeeShareDiscount();

        uint256 previousTargetFeeShareDiscount = _getTargetFeeShareDiscount(state);

        if (feeShareDiscount > currentFeeShareDiscount) {
            if (state.cooldownUntil != 0) _cancelFeeShareDiscountCut(nodeOperatorId);
            state.currentFeeShareDiscount = uint16(feeShareDiscount);
            emit FeeShareDiscountSet(nodeOperatorId, feeShareDiscount);
        } else {
            uint256 cooldownUntil = block.timestamp + $.feeShareDiscountCutCooldown;
            state.pendingFeeShareDiscount = uint16(feeShareDiscount);
            state.cooldownUntil = uint64(cooldownUntil);
            emit FeeShareDiscountCutRequested(nodeOperatorId, feeShareDiscount, cooldownUntil);
        }

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(
            nodeOperatorId,
            previousTargetFeeShareDiscount,
            feeShareDiscount
        );
    }

    /// @inheritdoc ICustomFeeRegistry
    function cancelFeeShareDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeShareDiscountState storage state = _storage().feeShareDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeShareDiscountCut();

        uint256 pendingFeeShareDiscount = state.pendingFeeShareDiscount;
        uint256 currentFeeShareDiscount = state.currentFeeShareDiscount;
        _cancelFeeShareDiscountCut(nodeOperatorId);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(
            nodeOperatorId,
            pendingFeeShareDiscount,
            currentFeeShareDiscount
        );
    }

    /// @inheritdoc ICustomFeeRegistry
    function applyFeeShareDiscountCut(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        FeeShareDiscountState storage state = _storage().feeShareDiscounts[nodeOperatorId];
        if (state.cooldownUntil == 0) revert NoPendingFeeShareDiscountCut();
        if (state.cooldownUntil > block.timestamp) revert FeeShareDiscountCutCooldownNotElapsed();

        uint256 feeShareDiscount = state.pendingFeeShareDiscount;
        state.currentFeeShareDiscount = uint16(feeShareDiscount);
        state.pendingFeeShareDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeShareDiscountCutApplied(nodeOperatorId, feeShareDiscount);
        // No notification: the allocation weight changed when the cut was requested.
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeShareDiscountCutCooldown(uint256 feeShareDiscountCutCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeShareDiscountCutCooldown(feeShareDiscountCutCooldown);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeShareDiscountCutCooldown() external view returns (uint256) {
        return _storage().feeShareDiscountCutCooldown;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getPendingFeeShareDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeShareDiscounts[nodeOperatorId].pendingFeeShareDiscount;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeShareDiscountCutCooldownUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeShareDiscounts[nodeOperatorId].cooldownUntil;
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP =
            MAX_BP +
            StepwiseWeightBoost._stepValueAt(_getTargetFeeShareDiscount(_storage().feeShareDiscounts[nodeOperatorId]));
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeShareDiscount(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().feeShareDiscounts[nodeOperatorId].currentFeeShareDiscount;
    }

    function _cancelFeeShareDiscountCut(uint256 nodeOperatorId) internal {
        FeeShareDiscountState storage state = _storage().feeShareDiscounts[nodeOperatorId];
        state.pendingFeeShareDiscount = 0;
        state.cooldownUntil = 0;
        emit FeeShareDiscountCutCancelled(nodeOperatorId);
    }

    function _setFeeShareDiscountCutCooldown(uint256 feeShareDiscountCutCooldown) internal {
        if (feeShareDiscountCutCooldown == 0 || feeShareDiscountCutCooldown > MAX_FEE_SHARE_DISCOUNT_CUT_COOLDOWN) {
            revert InvalidFeeShareDiscountCutCooldown();
        }
        _storage().feeShareDiscountCutCooldown = feeShareDiscountCutCooldown;
        emit FeeShareDiscountCutCooldownSet(feeShareDiscountCutCooldown);
    }

    function _getTargetFeeShareDiscount(FeeShareDiscountState storage state) internal view returns (uint256) {
        return state.cooldownUntil != 0 ? state.pendingFeeShareDiscount : state.currentFeeShareDiscount;
    }

    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold <= MAX_BP && step.threshold % FEE_SHARE_DISCOUNT_STEP == 0;
    }

    function _storage() internal pure returns (CustomFeeRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CUSTOM_FEE_REGISTRY_STORAGE_LOCATION
        }
    }
}
