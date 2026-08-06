// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { StepwiseWeightBoost } from "./abstract/StepwiseWeightBoost.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IAdditionalBondRegistry, PendingCurveMultiplierReduction } from "./interfaces/IAdditionalBondRegistry.sol";
import { Step } from "./interfaces/IStepwiseWeightBoost.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Maps an operator's curve multiplier to a weight multiplier via governance-set steps. See
///         IAdditionalBondRegistry for the model.
contract AdditionalBondRegistry is IAdditionalBondRegistry, StepwiseWeightBoost {
    /// @custom:storage-location erc7201:AdditionalBondRegistry
    struct AdditionalBondRegistryStorage {
        uint256 curveMultiplierReductionCooldown;
        /// @dev Downgrade cooldown and pending curve multiplier increment, per operator.
        mapping(uint256 nodeOperatorId => PendingCurveMultiplierReduction) pending;
    }

    // Sanity guard: effective multiplier <= 10x.
    uint256 public constant MAX_CURVE_MULTIPLIER = 9 * MAX_BP;
    // Requested curve multiplier must be a multiple of this (1%).
    uint256 public constant CURVE_MULTIPLIER_STEP = MAX_BP / 100;
    uint256 public constant MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN = 365 days;

    IAccounting public immutable ACCOUNTING;

    // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION =
        0xe06435b00cfe5ab72c52612ef2f4c7b5f9c4cc44634ef79a78a1888f5b1eb300;

    /// @param module CuratedModule proxy address.
    constructor(address module) StepwiseWeightBoost(module) {
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
    }

    /// @inheritdoc IAdditionalBondRegistry
    function initialize(
        address admin,
        uint256 curveMultiplierReductionCooldown,
        Step[] calldata steps
    ) external initializer {
        _setCurveMultiplierReductionCooldown(curveMultiplierReductionCooldown);
        StepwiseWeightBoost._initialize(admin, steps);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function requestCurveMultiplier(uint256 nodeOperatorId, uint256 curveMultiplier) external {
        AdditionalBondRegistryStorage storage $ = _storage();
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        if (curveMultiplier > MAX_CURVE_MULTIPLIER || curveMultiplier % CURVE_MULTIPLIER_STEP != 0) {
            revert InvalidCurveMultiplier();
        }

        uint256 newMul = MAX_BP + curveMultiplier;
        uint256 curMul = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId);
        if (newMul == curMul) revert SameCurveMultiplier();

        PendingCurveMultiplierReduction storage pending = $.pending[nodeOperatorId];
        uint256 previousEffectiveCurveMultiplier = _getEffectiveCurveMultiplier(pending, curMul);

        if (newMul > curMul) {
            // NOTE: Takes into account current bond amount and keys count.
            //       Value `0` as a second arg for the following method means current keys count.
            if (ACCOUNTING.getRequiredBondForNextKeys(nodeOperatorId, 0, newMul) > 0) {
                revert InsufficientBond();
            }
            if (pending.cooldownUntil != 0) {
                delete $.pending[nodeOperatorId];
                emit CurveMultiplierReductionCancelled(nodeOperatorId);
            }
            ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, curveMultiplier);
        } else {
            uint256 cooldownUntil = block.timestamp + $.curveMultiplierReductionCooldown;
            $.pending[nodeOperatorId] = PendingCurveMultiplierReduction({
                cooldownUntil: uint128(cooldownUntil),
                curveMultiplier: uint128(curveMultiplier)
            });
            emit CurveMultiplierReductionRequested(nodeOperatorId, curveMultiplier, cooldownUntil);
        }

        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(
            nodeOperatorId,
            previousEffectiveCurveMultiplier,
            curveMultiplier
        );
    }

    /// @inheritdoc IAdditionalBondRegistry
    function applyCurveMultiplierReduction(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        PendingCurveMultiplierReduction storage p = _storage().pending[nodeOperatorId];
        if (p.cooldownUntil == 0) revert NoCurveMultiplierReductionCooldown();
        if (p.cooldownUntil > block.timestamp) revert CurveMultiplierReductionCooldownNotElapsed();

        uint256 curveMultiplier = p.curveMultiplier;
        delete _storage().pending[nodeOperatorId];
        emit CurveMultiplierReductionApplied(nodeOperatorId, curveMultiplier);
        ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, curveMultiplier);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function cancelCurveMultiplierReduction(uint256 nodeOperatorId) external {
        StepwiseWeightBoost._onlyNodeOperatorOwner(nodeOperatorId);

        PendingCurveMultiplierReduction storage pending = _storage().pending[nodeOperatorId];
        if (pending.cooldownUntil == 0) revert NoCurveMultiplierReductionCooldown();

        uint256 previousCurveMultiplier = pending.curveMultiplier;
        // Dropping the pending target hands the weight back to the multiplier Accounting still holds.
        uint256 currentCurveMultiplier = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId) - MAX_BP;

        delete _storage().pending[nodeOperatorId];
        emit CurveMultiplierReductionCancelled(nodeOperatorId);
        StepwiseWeightBoost._notifyMetaRegistryIfWeightChanged(
            nodeOperatorId,
            previousCurveMultiplier,
            currentCurveMultiplier
        );
    }

    /// @inheritdoc IAdditionalBondRegistry
    function setCurveMultiplierReductionCooldown(
        uint256 curveMultiplierReductionCooldown
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setCurveMultiplierReductionCooldown(curveMultiplierReductionCooldown);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getCurveMultiplierReductionCooldown() external view returns (uint256) {
        return _storage().curveMultiplierReductionCooldown;
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getPendingCurveMultiplier(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().pending[nodeOperatorId].curveMultiplier;
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getCurveMultiplierReductionCooldownUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().pending[nodeOperatorId].cooldownUntil;
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        PendingCurveMultiplierReduction storage pending = _storage().pending[nodeOperatorId];
        uint256 currentMultiplierBP = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId);
        multiplierBP =
            MAX_BP +
            StepwiseWeightBoost._stepValueAt(_getEffectiveCurveMultiplier(pending, currentMultiplierBP));
    }

    function _setCurveMultiplierReductionCooldown(uint256 curveMultiplierReductionCooldown) internal {
        if (
            curveMultiplierReductionCooldown == 0 ||
            curveMultiplierReductionCooldown > MAX_CURVE_MULTIPLIER_REDUCTION_COOLDOWN
        ) {
            revert InvalidCurveMultiplierReductionCooldown();
        }
        _storage().curveMultiplierReductionCooldown = curveMultiplierReductionCooldown;
        emit CurveMultiplierReductionCooldownSet(curveMultiplierReductionCooldown);
    }

    /// @dev During a downgrade cooldown, weight follows the pending lower multiplier while Accounting
    ///      continues to hold the current higher multiplier.
    function _getEffectiveCurveMultiplier(
        PendingCurveMultiplierReduction storage pending,
        uint256 currentMultiplierBP
    ) internal view returns (uint256) {
        return pending.cooldownUntil != 0 ? pending.curveMultiplier : currentMultiplierBP - MAX_BP;
    }

    function _isValidStep(Step calldata step) internal pure override returns (bool) {
        return step.threshold <= MAX_CURVE_MULTIPLIER;
    }

    function _storage() internal pure returns (AdditionalBondRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION
        }
    }
}
