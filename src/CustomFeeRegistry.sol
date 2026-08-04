// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBondCurve } from "./interfaces/IBondCurve.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { ICustomFeeRegistry, OperatorFee, FeeModifier } from "./interfaces/ICustomFeeRegistry.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Per-operator custom fees and the allocation weight boost derived from them. See
///         ICustomFeeRegistry for the model.
contract CustomFeeRegistry is ICustomFeeRegistry, Initializable, AccessControlEnumerableUpgradeable {
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:CustomFeeRegistry
    struct CustomFeeRegistryStorage {
        uint256 defaultMinFee;
        uint256 feeIncreaseCooldown;
        mapping(uint256 curveId => FeeModifier) feeModifier;
        mapping(uint256 nodeOperatorId => OperatorFee) fees;
    }

    // All fees are basis points of the operator's own rewards.
    // A custom fee moves in these increments: 2.5% of the operator's rewards, which is 0.1%
    // of the total staking rewards at a 4% module reward share.
    uint256 public constant FEE_STEP = 250; // 2.5%
    // The fee of an unset operator and the inclusive upper bound for custom fees.
    uint256 public constant DEFAULT_MAX_FEE = 35 * FEE_STEP; // 87.5%
    // Slope of the weight line: multiplier basis points per FEE_STEP below DEFAULT_MAX_FEE.
    uint256 public constant WEIGHT_BOOST_PER_STEP = 400;
    uint256 public constant MAX_FEE_INCREASE_COOLDOWN = type(uint32).max;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IMetaRegistry public immutable META_REGISTRY;

    // keccak256(abi.encode(uint256(keccak256("CustomFeeRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CUSTOM_FEE_REGISTRY_STORAGE_LOCATION =
        0x231651de169707bf46042ddc0065dcd629da5632e3ccd31978f43f09a90a1200;

    /// @param module Curated module address.
    constructor(address module) {
        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        META_REGISTRY = IMetaRegistry(MODULE.META_REGISTRY());

        _disableInitializers();
    }

    /// @inheritdoc ICustomFeeRegistry
    function initialize(address admin, uint256 defaultMinFee, uint256 feeIncreaseCooldown) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setDefaultMinFee(defaultMinFee, DEFAULT_MAX_FEE);
        _setFeeIncreaseCooldown(feeIncreaseCooldown);
    }

    /// @inheritdoc ICustomFeeRegistry
    function requestFee(uint256 nodeOperatorId, uint256 requestedFee) external {
        _checkOperatorOwner(nodeOperatorId);

        uint256 currentFee = _getCurrentFee(nodeOperatorId);
        if (requestedFee == currentFee) revert SameFee();

        _validateFee(nodeOperatorId, requestedFee);

        if (requestedFee < currentFee) {
            _setCurrentFee(nodeOperatorId, requestedFee);
        } else {
            _scheduleFeeIncrease(nodeOperatorId, requestedFee);
        }
    }

    /// @inheritdoc ICustomFeeRegistry
    function cancelFeeIncrease(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        OperatorFee storage operatorFee = _storage().fees[nodeOperatorId];
        if (operatorFee.cooldownUntil == 0) revert NoFeeIncreaseCooldown();

        operatorFee.pendingFeeIncrease = 0;
        operatorFee.cooldownUntil = 0;
        emit FeeIncreaseCancelled(nodeOperatorId);
        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @inheritdoc ICustomFeeRegistry
    function applyFeeIncrease(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        OperatorFee storage operatorFee = _storage().fees[nodeOperatorId];
        if (operatorFee.cooldownUntil == 0) revert NoFeeIncreaseCooldown();
        if (operatorFee.cooldownUntil > block.timestamp) revert FeeIncreaseCooldownNotElapsed();

        uint16 pendingFee = operatorFee.pendingFeeIncrease;
        // The fee may have become invalid during the cooldown after a curve or modifier change.
        _validateFee(nodeOperatorId, pendingFee);

        operatorFee.currentFee = pendingFee;
        operatorFee.pendingFeeIncrease = 0;
        operatorFee.cooldownUntil = 0;
        emit FeeIncreaseApplied(nodeOperatorId, pendingFee);
        // No notification: the allocation weight changed when the increase was requested.
    }

    /// @inheritdoc ICustomFeeRegistry
    function normalizeFee(uint256 nodeOperatorId) external {
        if (!_normalizeFee(nodeOperatorId)) revert FeeNotBelowMinFee();
    }

    /// @inheritdoc ICustomFeeRegistry
    function normalizeFees(uint256[] calldata nodeOperatorIds) external returns (uint256 normalizedCount) {
        for (uint256 i; i < nodeOperatorIds.length; ++i) {
            if (_normalizeFee(nodeOperatorIds[i])) ++normalizedCount;
        }
    }

    /// @inheritdoc ICustomFeeRegistry
    function setDefaultMinFee(uint256 defaultMinFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Only downwards: fees already set stay valid.
        _setDefaultMinFee(defaultMinFee, _storage().defaultMinFee);
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeModifier(uint256 curveId, uint256 value, bool negative) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (curveId >= ACCOUNTING.getCurvesCount()) revert IBondCurve.InvalidBondCurveId();

        CustomFeeRegistryStorage storage $ = _storage();
        // Keeps the effective fee within MAX_BP and the per-type minimum within DEFAULT_MAX_FEE.
        uint256 maxValue = negative ? DEFAULT_MAX_FEE - $.defaultMinFee : MAX_BP - DEFAULT_MAX_FEE;
        if (value > maxValue || value % FEE_STEP != 0) revert InvalidFeeModifier();

        $.feeModifier[curveId] = FeeModifier({ value: value.toUint248(), negative: negative });
        emit FeeModifierSet(curveId, value, negative);
        // No weight notification: the modifier shifts only the effective fee.
    }

    /// @inheritdoc ICustomFeeRegistry
    function setFeeIncreaseCooldown(uint256 feeIncreaseCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeIncreaseCooldown(feeIncreaseCooldown);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getDefaultMinFee() external view returns (uint256) {
        return _storage().defaultMinFee;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeIncreaseCooldown() external view returns (uint256) {
        return _storage().feeIncreaseCooldown;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeModifier(uint256 curveId) external view returns (FeeModifier memory) {
        return _storage().feeModifier[curveId];
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFee(uint256 nodeOperatorId) external view returns (uint256) {
        return _getCurrentFee(nodeOperatorId);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getPendingFeeIncrease(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().fees[nodeOperatorId].pendingFeeIncrease;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFeeIncreaseCooldownUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return _storage().fees[nodeOperatorId].cooldownUntil;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getMinFee(uint256 nodeOperatorId) external view returns (uint256) {
        return _getMinFee(nodeOperatorId);
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        OperatorFee storage operatorFee = _storage().fees[nodeOperatorId];
        // A pending increase affects allocation weight before it becomes the current fee.
        uint256 fee = operatorFee.cooldownUntil != 0 ? operatorFee.pendingFeeIncrease : _getCurrentFee(nodeOperatorId);
        // The multiplier is 1x for an operator at DEFAULT_MAX_FEE and grows by
        // WEIGHT_BOOST_PER_STEP for every step below it. Fees are multiples of FEE_STEP,
        // so the division has no remainder.
        multiplierBP = MAX_BP + ((DEFAULT_MAX_FEE - fee) * WEIGHT_BOOST_PER_STEP) / FEE_STEP;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256) {
        uint256 currentFee = _getCurrentFee(nodeOperatorId);
        FeeModifier storage feeModifier = _storage().feeModifier[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        if (feeModifier.negative) {
            // A curve or modifier change can leave the current fee below the negative modifier.
            return currentFee > feeModifier.value ? currentFee - feeModifier.value : 0;
        }

        // The modifier bounds keep the sum within MAX_BP.
        return currentFee + feeModifier.value;
    }

    /// @dev Sets the custom fee immediately, drops any pending increase, and notifies if the
    ///      allocation weight changes.
    function _setCurrentFee(uint256 nodeOperatorId, uint256 newCurrentFee) internal {
        OperatorFee storage operatorFee = _storage().fees[nodeOperatorId];
        bool hadPendingIncrease = operatorFee.cooldownUntil != 0;
        // A pending increase, if any, is the fee currently affecting allocation weight.
        uint256 previousFee = hadPendingIncrease ? operatorFee.pendingFeeIncrease : _getCurrentFee(nodeOperatorId);

        operatorFee.currentFee = newCurrentFee.toUint16();
        operatorFee.pendingFeeIncrease = 0;
        operatorFee.cooldownUntil = 0;
        if (hadPendingIncrease) emit FeeIncreaseCancelled(nodeOperatorId);
        emit FeeSet(nodeOperatorId, newCurrentFee);
        if (previousFee != newCurrentFee) META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @dev Stores or replaces a pending increase, restarts its cooldown, and notifies MetaRegistry.
    ///      Notification is sent even if the pending target and multiplier are unchanged.
    function _scheduleFeeIncrease(uint256 nodeOperatorId, uint256 pendingFee) internal {
        CustomFeeRegistryStorage storage $ = _storage();
        OperatorFee storage operatorFee = $.fees[nodeOperatorId];
        uint256 cooldownUntil = block.timestamp + $.feeIncreaseCooldown;
        operatorFee.pendingFeeIncrease = pendingFee.toUint16();
        operatorFee.cooldownUntil = cooldownUntil.toUint64();
        emit FeeIncreaseRequested(nodeOperatorId, pendingFee, cooldownUntil);
        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @dev The minimum must remain non-zero because zero currentFee is the unset marker.
    function _setDefaultMinFee(uint256 defaultMinFee, uint256 maxExclusive) internal {
        if (defaultMinFee == 0 || defaultMinFee >= maxExclusive || defaultMinFee % FEE_STEP != 0) {
            revert InvalidDefaultMinFee();
        }
        _storage().defaultMinFee = defaultMinFee;
        emit DefaultMinFeeSet(defaultMinFee);
    }

    function _setFeeIncreaseCooldown(uint256 feeIncreaseCooldown) internal {
        if (feeIncreaseCooldown == 0 || feeIncreaseCooldown > MAX_FEE_INCREASE_COOLDOWN) {
            revert InvalidFeeIncreaseCooldown();
        }
        _storage().feeIncreaseCooldown = feeIncreaseCooldown;
        emit FeeIncreaseCooldownSet(feeIncreaseCooldown);
    }

    /// @dev Normalizes the fee if a curve or modifier change left it below the current minimum.
    function _normalizeFee(uint256 nodeOperatorId) internal returns (bool normalized) {
        uint256 minFee = _getMinFee(nodeOperatorId);
        if (_getCurrentFee(nodeOperatorId) >= minFee) return false;

        _setCurrentFee(nodeOperatorId, minFee);
        return true;
    }

    function _validateFee(uint256 nodeOperatorId, uint256 fee) internal view {
        if (fee < _getMinFee(nodeOperatorId) || fee > DEFAULT_MAX_FEE || fee % FEE_STEP != 0) revert InvalidFee();
    }

    /// @dev A negative modifier raises the per-type minimum so a valid current fee has an effective
    ///      fee of at least defaultMinFee. Existing fees may remain below it until normalized.
    function _getMinFee(uint256 nodeOperatorId) internal view returns (uint256) {
        CustomFeeRegistryStorage storage $ = _storage();
        FeeModifier storage feeModifier = $.feeModifier[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        return feeModifier.negative ? $.defaultMinFee + feeModifier.value : $.defaultMinFee;
    }

    /// @dev Zero means "never set" and reads as DEFAULT_MAX_FEE; a real fee is never zero (defaultMinFee > 0).
    function _getCurrentFee(uint256 nodeOperatorId) internal view returns (uint256) {
        uint256 fee = _storage().fees[nodeOperatorId].currentFee;
        return fee == 0 ? DEFAULT_MAX_FEE : fee;
    }

    function _checkOperatorOwner(uint256 nodeOperatorId) internal view {
        if (msg.sender != MODULE.getNodeOperatorOwner(nodeOperatorId)) {
            revert SenderIsNotOperatorOwner();
        }
    }

    function _storage() internal pure returns (CustomFeeRegistryStorage storage $) {
        assembly ("memory-safe") {
            // keccak256(abi.encode(uint256(keccak256("CustomFeeRegistry")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := CUSTOM_FEE_REGISTRY_STORAGE_LOCATION
        }
    }
}
