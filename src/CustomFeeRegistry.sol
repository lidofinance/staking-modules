// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { ICustomFeeRegistry, OperatorFee, TypeBonus } from "./interfaces/ICustomFeeRegistry.sol";
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
        mapping(uint256 curveId => TypeBonus) typeBonus;
        mapping(uint256 nodeOperatorId => OperatorFee) fees;
    }

    // All fees are basis points of the operator's own rewards.
    // A custom fee moves in these increments: 2.5% of the operator's rewards, which is 0.1%
    // of the total staking rewards at a 4% module reward share.
    uint256 public constant FEE_STEP = 250; // 2.5%
    // The starting fee of every operator; a custom fee can only go below it.
    uint256 public constant DEFAULT_MAX_FEE = 35 * FEE_STEP; // 87.5%
    // Slope of the weight line: multiplier basis points per FEE_STEP below DEFAULT_MAX_FEE.
    uint256 public constant WEIGHT_BOOST_PER_STEP = 400;

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
    function requestFee(uint256 nodeOperatorId, uint256 fee) external {
        _checkOperatorOwner(nodeOperatorId);

        uint256 minFee = _getMinFee(nodeOperatorId);
        if (fee < minFee || fee > DEFAULT_MAX_FEE || fee % FEE_STEP != 0) revert InvalidFee();

        uint256 curFee = _getFee(nodeOperatorId);
        if (fee == curFee) revert SameFee();

        if (fee < curFee) {
            // A decrease also cancels any pending increase along with its cooldown.
            _setFee(nodeOperatorId, fee);
            return;
        }

        _requestFeeIncrease(nodeOperatorId, fee);
    }

    /// @inheritdoc ICustomFeeRegistry
    function applyFeeIncrease(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        CustomFeeRegistryStorage storage $ = _storage();
        OperatorFee storage f = $.fees[nodeOperatorId];
        if (f.cooldownUntil == 0) revert NoFeeIncreaseCooldown();
        if (f.cooldownUntil > block.timestamp) revert FeeIncreaseCooldownNotElapsed();

        uint16 fee = f.pendingFeeIncrease;
        $.fees[nodeOperatorId] = OperatorFee({ currentFee: fee, pendingFeeIncrease: 0, cooldownUntil: 0 });
        emit FeeIncreaseApplied(nodeOperatorId, fee);
        // No weight notification: the weight has followed the pending fee since the request.
    }

    /// @inheritdoc ICustomFeeRegistry
    function restoreFeeToMin(uint256 nodeOperatorId) external {
        if (_storage().fees[nodeOperatorId].cooldownUntil != 0) revert FeeIncreaseCooldownActive();

        uint256 minFee = _getMinFee(nodeOperatorId);
        // A fee below the type's minimum can only be left over from a tightened type bonus.
        if (_getFee(nodeOperatorId) >= minFee) revert FeeNotBelowMinFee();

        _setFee(nodeOperatorId, minFee);
    }

    /// @inheritdoc ICustomFeeRegistry
    function setDefaultMinFee(uint256 defaultMinFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Only downwards: fees already set stay valid.
        _setDefaultMinFee(defaultMinFee, _storage().defaultMinFee);
    }

    /// @inheritdoc ICustomFeeRegistry
    function setTypeBonus(uint256 curveId, uint256 value, bool negative) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CustomFeeRegistryStorage storage $ = _storage();
        // Keeps the effective fee within MAX_BP and the per-type minimum within DEFAULT_MAX_FEE.
        uint256 maxValue = negative ? DEFAULT_MAX_FEE - $.defaultMinFee : MAX_BP - DEFAULT_MAX_FEE;
        if (value > maxValue || value % FEE_STEP != 0) revert InvalidTypeBonus();

        $.typeBonus[curveId] = TypeBonus({ value: value.toUint248(), negative: negative });
        emit TypeBonusSet(curveId, value, negative);
        // No weight notification: the bonus shifts only the effective fee.
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
    function getTypeBonus(uint256 curveId) external view returns (TypeBonus memory) {
        return _storage().typeBonus[curveId];
    }

    /// @inheritdoc ICustomFeeRegistry
    function getFee(uint256 nodeOperatorId) external view returns (uint256) {
        return _getFee(nodeOperatorId);
    }

    /// @inheritdoc ICustomFeeRegistry
    function getMinFee(uint256 nodeOperatorId) external view returns (uint256) {
        return _getMinFee(nodeOperatorId);
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        OperatorFee storage f = _storage().fees[nodeOperatorId];
        // During a pending increase the weight already follows the higher pending fee.
        uint256 fee = f.pendingFeeIncrease > 0 ? f.pendingFeeIncrease : _getFee(nodeOperatorId);
        // The multiplier is 1x for an operator at DEFAULT_MAX_FEE and grows by
        // WEIGHT_BOOST_PER_STEP for every step below it. Fees are multiples of FEE_STEP,
        // so the division has no remainder.
        multiplierBP = MAX_BP + ((DEFAULT_MAX_FEE - fee) / FEE_STEP) * WEIGHT_BOOST_PER_STEP;
    }

    /// @inheritdoc ICustomFeeRegistry
    function getEffectiveFee(uint256 nodeOperatorId) external view returns (uint256) {
        uint256 fee = _getFee(nodeOperatorId);
        TypeBonus storage bonus = _storage().typeBonus[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        if (bonus.negative) {
            // A tightened bonus can leave the fee below its value.
            return fee > bonus.value ? fee - bonus.value : 0;
        }

        // The bonus bounds keep the sum within MAX_BP.
        return fee + bonus.value;
    }

    /// @dev Sets the custom fee immediately, dropping any pending increase, and notifies the
    ///      weight change.
    function _setFee(uint256 nodeOperatorId, uint256 fee) internal {
        _storage().fees[nodeOperatorId] = OperatorFee({
            currentFee: fee.toUint16(),
            pendingFeeIncrease: 0,
            cooldownUntil: 0
        });
        emit FeeSet(nodeOperatorId, fee);
        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @dev Locks in a pending fee increase with its cooldown and notifies the weight change; the
    ///      fee itself applies via `applyFeeIncrease` once the cooldown elapses. A repeated
    ///      increase overwrites the pending one and restarts the cooldown.
    function _requestFeeIncrease(uint256 nodeOperatorId, uint256 fee) internal {
        CustomFeeRegistryStorage storage $ = _storage();
        OperatorFee storage f = $.fees[nodeOperatorId];
        // Unreachable for an unset operator, so `f.currentFee` is never zero here.
        uint256 cooldownUntil = block.timestamp + $.feeIncreaseCooldown;
        $.fees[nodeOperatorId] = OperatorFee({
            currentFee: f.currentFee,
            pendingFeeIncrease: fee.toUint16(),
            cooldownUntil: cooldownUntil.toUint64()
        });
        emit FeeIncreaseRequested(nodeOperatorId, fee, cooldownUntil);
        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @dev Never zero: a zero stored custom fee is the "never set" marker.
    function _setDefaultMinFee(uint256 defaultMinFee, uint256 maxAllowed) internal {
        if (defaultMinFee == 0 || defaultMinFee >= maxAllowed || defaultMinFee % FEE_STEP != 0) {
            revert InvalidDefaultMinFee();
        }
        _storage().defaultMinFee = defaultMinFee;
        emit DefaultMinFeeSet(defaultMinFee);
    }

    function _setFeeIncreaseCooldown(uint256 feeIncreaseCooldown) internal {
        if (feeIncreaseCooldown == 0) revert InvalidFeeIncreaseCooldown();
        _storage().feeIncreaseCooldown = feeIncreaseCooldown;
        emit FeeIncreaseCooldownSet(feeIncreaseCooldown);
    }

    /// @dev Per-type minimum: a negative bonus raises it so the effective fee stays above the
    ///      default min fee.
    function _getMinFee(uint256 nodeOperatorId) internal view returns (uint256) {
        CustomFeeRegistryStorage storage $ = _storage();
        TypeBonus storage bonus = $.typeBonus[ACCOUNTING.getBondCurveId(nodeOperatorId)];
        return bonus.negative ? $.defaultMinFee + bonus.value : $.defaultMinFee;
    }

    /// @dev Zero means "never set" and reads as DEFAULT_MAX_FEE; a real fee is never zero (defaultMinFee > 0).
    function _getFee(uint256 nodeOperatorId) internal view returns (uint256) {
        uint256 fee = _storage().fees[nodeOperatorId].currentFee;
        return fee == 0 ? DEFAULT_MAX_FEE : fee;
    }

    // TODO: Have the same in many places. Move to lib
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
