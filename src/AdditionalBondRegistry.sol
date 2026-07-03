// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IAdditionalBondRegistry, TierInfo, OperatorTierState } from "./interfaces/IAdditionalBondRegistry.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "./lib/Constants.sol";

/// @notice Manages operator tiers.
contract AdditionalBondRegistry is IAdditionalBondRegistry, Initializable, AccessControlEnumerableUpgradeable {
    /// @custom:storage-location erc7201:AdditionalBondRegistry
    struct AdditionalBondRegistryStorage {
        mapping(uint256 tierId => TierInfo) tiers;
        uint256 tiersCount;
        mapping(uint256 nodeOperatorId => uint256 tierId) operatorTier;
        /// @dev Cooldown deadline (unix timestamp) after a tier downgrade. 0 = no active cooldown.
        mapping(uint256 nodeOperatorId => uint256) curveMultiplierCooldownUntil;
    }

    // NOTE: Sanity guard for tier creation: effective multiplier <= 10x the default multiplier.
    uint256 public constant MAX_CURVE_MULTIPLIER = 9 * MAX_BP;
    uint256 public constant MAX_WEIGHT_MULTIPLIER = 9 * MAX_BP;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IMetaRegistry public immutable META_REGISTRY;
    uint256 public immutable CURVE_MULTIPLIER_COOLDOWN;

    // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION =
        0xe06435b00cfe5ab72c52612ef2f4c7b5f9c4cc44634ef79a78a1888f5b1eb300;

    /// @param module                CuratedModule address.
    /// @param curveMultiplierCooldown Cooldown in seconds after a tier downgrade before `applyCurveMultiplier` can be called.
    constructor(address module, uint256 curveMultiplierCooldown) {
        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        META_REGISTRY = IMetaRegistry(MODULE.META_REGISTRY());

        CURVE_MULTIPLIER_COOLDOWN = curveMultiplierCooldown;

        _disableInitializers();
    }

    /// @inheritdoc IAdditionalBondRegistry
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // TODO: set initial tiers here
    }

    /// @inheritdoc IAdditionalBondRegistry
    function addTier(
        uint256 curveMultiplier,
        uint256 weightMultiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 tierId) {
        if (curveMultiplier > MAX_CURVE_MULTIPLIER) revert InvalidCurveMultiplier();
        if (weightMultiplier > MAX_WEIGHT_MULTIPLIER) revert InvalidWeightMultiplier();
        AdditionalBondRegistryStorage storage $ = _storage();
        tierId = ++$.tiersCount;
        $.tiers[tierId] = TierInfo({
            curveMultiplier: uint128(curveMultiplier),
            weightMultiplier: uint128(weightMultiplier)
        });
        emit TierAdded(tierId, curveMultiplier, weightMultiplier);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function selectTier(uint256 nodeOperatorId, uint256 tierId) external {
        AdditionalBondRegistryStorage storage $ = _storage();
        _checkOperatorOwner(nodeOperatorId);

        if (tierId > $.tiersCount) revert InvalidTierId();
        if (tierId == $.operatorTier[nodeOperatorId]) revert SameTier();

        uint256 newMulInc = $.tiers[tierId].curveMultiplier;
        uint256 newMul = MAX_BP + newMulInc;
        if (newMul > ACCOUNTING.getBondCurveMultiplier(nodeOperatorId)) {
            // NOTE: Takes into account current bond amount and keys count.
            //       Value `0` as a second arg for the following method means current keys count.
            if (ACCOUNTING.getRequiredBondForNextKeys(nodeOperatorId, 0, newMul) > 0) revert InsufficientBondForTier();
            if ($.curveMultiplierCooldownUntil[nodeOperatorId] != 0) {
                _removeCurveMultiplierCooldown(nodeOperatorId);
            }
            ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, newMulInc);
        } else {
            if ($.curveMultiplierCooldownUntil[nodeOperatorId] != 0) revert CurveMultiplierCooldownActive();
            _setCurveMultiplierCooldown(nodeOperatorId);
        }

        $.operatorTier[nodeOperatorId] = tierId;
        emit TierSelected(nodeOperatorId, tierId);

        META_REGISTRY.notifyWeightBoostChanged(nodeOperatorId);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function applyCurveMultiplier(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        AdditionalBondRegistryStorage storage $ = _storage();
        uint256 cooldownUntil = $.curveMultiplierCooldownUntil[nodeOperatorId];
        if (cooldownUntil == 0) revert NoCurveMultiplierCooldown();
        if (cooldownUntil > block.timestamp) revert CurveMultiplierCooldownNotElapsed();

        _removeCurveMultiplierCooldown(nodeOperatorId);

        ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, $.tiers[$.operatorTier[nodeOperatorId]].curveMultiplier);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getTiersCount() external view returns (uint256) {
        return _storage().tiersCount;
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getOperatorTierState(uint256 nodeOperatorId) external view returns (OperatorTierState memory state) {
        AdditionalBondRegistryStorage storage $ = _storage();
        state.tierId = $.operatorTier[nodeOperatorId];
        state.curveMultiplierCooldownUntil = $.curveMultiplierCooldownUntil[nodeOperatorId];
        state.weightMultiplier = MAX_BP + $.tiers[state.tierId].weightMultiplier;
        state.curveMultiplier = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId);
    }

    /// @inheritdoc IWeightBoostProvider
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        AdditionalBondRegistryStorage storage $ = _storage();
        multiplierBP = MAX_BP + $.tiers[$.operatorTier[nodeOperatorId]].weightMultiplier;
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getTierInfo(uint256 tierId) public view returns (TierInfo memory) {
        AdditionalBondRegistryStorage storage $ = _storage();
        if (tierId > $.tiersCount) revert InvalidTierId();
        TierInfo storage t = $.tiers[tierId];
        return
            TierInfo({
                curveMultiplier: uint128(MAX_BP + t.curveMultiplier),
                weightMultiplier: uint128(MAX_BP + t.weightMultiplier)
            });
    }

    /// @dev Sets the cooldown deadline to `block.timestamp + CURVE_MULTIPLIER_COOLDOWN`.
    function _setCurveMultiplierCooldown(uint256 nodeOperatorId) internal {
        uint256 cooldownUntil = block.timestamp + CURVE_MULTIPLIER_COOLDOWN;
        _storage().curveMultiplierCooldownUntil[nodeOperatorId] = cooldownUntil;
        emit CurveMultiplierCooldownSet(nodeOperatorId, cooldownUntil);
    }

    function _removeCurveMultiplierCooldown(uint256 nodeOperatorId) internal {
        delete _storage().curveMultiplierCooldownUntil[nodeOperatorId];
        emit CurveMultiplierCooldownRemoved(nodeOperatorId);
    }

    // TODO: Have the same in many places. Move to lib
    function _checkOperatorOwner(uint256 nodeOperatorId) internal view {
        if (msg.sender != MODULE.getNodeOperatorOwner(nodeOperatorId)) revert SenderIsNotOperatorOwner();
    }

    function _storage() internal pure returns (AdditionalBondRegistryStorage storage $) {
        assembly ("memory-safe") {
            // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION
        }
    }
}
