// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IAdditionalBondRegistry, BoostStep, PendingCurveMultiplier } from "./interfaces/IAdditionalBondRegistry.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Maps an operator's curve multiplier to a weight multiplier via governance-set boost steps.
contract AdditionalBondRegistry is IAdditionalBondRegistry, Initializable, AccessControlEnumerableUpgradeable {
    /// @custom:storage-location erc7201:AdditionalBondRegistry
    struct AdditionalBondRegistryStorage {
        BoostStep[] boostSteps;
        /// @dev Downgrade cooldown and pending curve multiplier increment, per operator.
        mapping(uint256 nodeOperatorId => PendingCurveMultiplier) pending;
    }

    // Sanity guard: effective multiplier <= 10x.
    uint256 public constant MAX_CURVE_MULTIPLIER = 9 * MAX_BP;
    uint256 public constant MAX_WEIGHT_MULTIPLIER = 9 * MAX_BP;
    // Requested curve multiplier must be a multiple of this (1%).
    uint256 public constant CURVE_MULTIPLIER_STEP = MAX_BP / 100;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IMetaRegistry public immutable META_REGISTRY;
    uint256 public immutable CURVE_MULTIPLIER_COOLDOWN;

    // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION =
        0xe06435b00cfe5ab72c52612ef2f4c7b5f9c4cc44634ef79a78a1888f5b1eb300;

    /// @param module                CuratedModule address.
    /// @param curveMultiplierCooldown Cooldown in seconds after a downgrade before `applyCurveMultiplier` can be called.
    constructor(address module, uint256 curveMultiplierCooldown) {
        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        META_REGISTRY = IMetaRegistry(MODULE.META_REGISTRY());

        CURVE_MULTIPLIER_COOLDOWN = curveMultiplierCooldown;

        _disableInitializers();
    }

    /// @inheritdoc IAdditionalBondRegistry
    function initialize(address admin, BoostStep[] calldata boostSteps) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        if (boostSteps.length == 0) revert EmptyBoostSteps();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setBoostSteps(boostSteps);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function setBoostSteps(BoostStep[] calldata boostSteps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBoostSteps(boostSteps);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function requestCurveMultiplier(uint256 nodeOperatorId, uint256 curveMultiplier) external {
        AdditionalBondRegistryStorage storage $ = _storage();
        _checkOperatorOwner(nodeOperatorId);

        if (curveMultiplier > MAX_CURVE_MULTIPLIER || curveMultiplier % CURVE_MULTIPLIER_STEP != 0) {
            revert InvalidCurveMultiplier();
        }

        uint256 newMul = MAX_BP + curveMultiplier;
        uint256 curMul = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId);
        if (newMul == curMul) revert SameCurveMultiplier();

        if (newMul > curMul) {
            // NOTE: Takes into account current bond amount and keys count.
            //       Value `0` as a second arg for the following method means current keys count.
            if (ACCOUNTING.getRequiredBondForNextKeys(nodeOperatorId, 0, newMul) > 0) {
                revert InsufficientBond();
            }
            if ($.pending[nodeOperatorId].cooldownUntil != 0) {
                _removeCurveMultiplierCooldown(nodeOperatorId);
            }
            ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, curveMultiplier);
        } else {
            if ($.pending[nodeOperatorId].cooldownUntil != 0) revert CurveMultiplierCooldownActive();
            _setCurveMultiplierCooldown(nodeOperatorId, curveMultiplier);
        }

        emit CurveMultiplierRequested(nodeOperatorId, curveMultiplier);
        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function applyCurveMultiplier(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        PendingCurveMultiplier storage p = _storage().pending[nodeOperatorId];
        if (p.cooldownUntil == 0) revert NoCurveMultiplierCooldown();
        if (p.cooldownUntil > block.timestamp) revert CurveMultiplierCooldownNotElapsed();

        uint256 curveMultiplier = p.curveMultiplier;
        _removeCurveMultiplierCooldown(nodeOperatorId);
        ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, curveMultiplier);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getBoostSteps() external view returns (BoostStep[] memory) {
        return _storage().boostSteps;
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        PendingCurveMultiplier storage p = _storage().pending[nodeOperatorId];
        // During a downgrade cooldown, weight follows the pending (lower) multiplier; Accounting still holds the higher one.
        uint256 curveMultiplier = p.cooldownUntil != 0
            ? p.curveMultiplier
            : ACCOUNTING.getBondCurveMultiplier(nodeOperatorId) - MAX_BP;
        multiplierBP = _weightMultiplierFor(curveMultiplier);
    }

    function _setBoostSteps(BoostStep[] calldata boostSteps) internal {
        AdditionalBondRegistryStorage storage $ = _storage();
        delete $.boostSteps;
        for (uint256 i = 0; i < boostSteps.length; ++i) {
            _validateBoostStep(boostSteps, i);
            $.boostSteps.push(boostSteps[i]);
        }
        emit BoostStepsSet(boostSteps);
    }

    /// @dev Starts the cooldown and stores the pending curve multiplier increment.
    function _setCurveMultiplierCooldown(uint256 nodeOperatorId, uint256 curveMultiplier) internal {
        uint256 cooldownUntil = block.timestamp + CURVE_MULTIPLIER_COOLDOWN;
        _storage().pending[nodeOperatorId] = PendingCurveMultiplier({
            cooldownUntil: uint128(cooldownUntil),
            curveMultiplier: uint128(curveMultiplier)
        });
        emit CurveMultiplierCooldownSet(nodeOperatorId, cooldownUntil);
    }

    function _removeCurveMultiplierCooldown(uint256 nodeOperatorId) internal {
        delete _storage().pending[nodeOperatorId];
        emit CurveMultiplierCooldownRemoved(nodeOperatorId);
    }

    /// @dev Weight multiplier for a curve multiplier increment: MAX_BP + the highest step at or below it, else MAX_BP.
    function _weightMultiplierFor(uint256 curveMultiplier) internal view returns (uint256 weightMul) {
        BoostStep[] storage boostSteps = _storage().boostSteps;
        weightMul = MAX_BP;
        uint256 len = boostSteps.length;
        for (uint256 i = 0; i < len; ++i) {
            if (curveMultiplier < boostSteps[i].minCurveMultiplier) break;
            weightMul = MAX_BP + boostSteps[i].weightMultiplier;
        }
    }

    // TODO: Have the same in many places. Move to lib
    function _checkOperatorOwner(uint256 nodeOperatorId) internal view {
        if (msg.sender != MODULE.getNodeOperatorOwner(nodeOperatorId)) revert SenderIsNotOperatorOwner();
    }

    /// @dev Validates step `i`: within bounds and strictly above the previous. Fields are increments (0 allowed).
    function _validateBoostStep(BoostStep[] calldata boostSteps, uint256 i) internal pure {
        BoostStep calldata s = boostSteps[i];
        if (s.minCurveMultiplier > MAX_CURVE_MULTIPLIER) revert InvalidCurveMultiplier();
        if (s.weightMultiplier > MAX_WEIGHT_MULTIPLIER) revert InvalidWeightMultiplier();
        if (i == 0) return;
        // Strictly increasing: a higher curve multiplier maps to a higher weight.
        if (s.minCurveMultiplier <= boostSteps[i - 1].minCurveMultiplier) revert InvalidCurveMultiplier();
        if (s.weightMultiplier <= boostSteps[i - 1].weightMultiplier) revert InvalidWeightMultiplier();
    }

    function _storage() internal pure returns (AdditionalBondRegistryStorage storage $) {
        assembly ("memory-safe") {
            // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION
        }
    }
}
