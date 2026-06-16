// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "./interfaces/IMetaRegistry.sol";
import { IAdditionalBondRegistry, TierInfo, OperatorTierState } from "./interfaces/IAdditionalBondRegistry.sol";
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

    uint256 public constant MAX_CURVE_MULTIPLIER_INC = 10 * MAX_BP;
    uint256 public constant MAX_WEIGHT_MULTIPLIER_INC = 10 * MAX_BP;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IMetaRegistry public immutable META_REGISTRY;
    uint256 public immutable CURVE_MULTIPLIER_COOLDOWN;

    // keccak256(abi.encode(uint256(keccak256("AdditionalBondRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADDITIONAL_BOND_REGISTRY_STORAGE_LOCATION =
        0xe06435b00cfe5ab72c52612ef2f4c7b5f9c4cc44634ef79a78a1888f5b1eb300;

    /// @param module                CuratedModule address.
    /// @param curveMultiplierCooldown Cooldown in seconds after a tier downgrade before `releaseCurveMultiplier` can be called.
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
    }

    /// @inheritdoc IAdditionalBondRegistry
    function addTier(
        uint256 curveMultiplierInc,
        uint256 weightMultiplierInc
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 tierId) {
        if (curveMultiplierInc > MAX_CURVE_MULTIPLIER_INC) revert InvalidCurveMultiplier();
        if (weightMultiplierInc > MAX_WEIGHT_MULTIPLIER_INC) revert InvalidWeightMultiplier();
        AdditionalBondRegistryStorage storage $ = _storage();
        tierId = ++$.tiersCount;
        $.tiers[tierId] = TierInfo({
            curveMultiplierInc: uint128(curveMultiplierInc),
            weightMultiplierInc: uint128(weightMultiplierInc)
        });
        emit TierAdded(tierId, curveMultiplierInc, weightMultiplierInc);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function selectTier(uint256 nodeOperatorId, uint256 tierId) external {
        AdditionalBondRegistryStorage storage $ = _storage();
        _checkOperatorOwner(nodeOperatorId);

        if (tierId > $.tiersCount) revert InvalidTierId();
        if (tierId == $.operatorTier[nodeOperatorId]) revert SameTier();

        uint256 newMulInc = getTierInfo(tierId).curveMultiplierInc;
        uint256 newMul = MAX_BP + newMulInc;
        if (newMul > ACCOUNTING.getBondCurveMultiplier(nodeOperatorId)) {
            // NOTE: Takes into account current bond amount and keys count.
            if (ACCOUNTING.getRequiredBondForNextKeys(nodeOperatorId, 0, newMul) > 0) revert InsufficientBondForTier();
            if ($.curveMultiplierCooldownUntil[nodeOperatorId] != 0) {
                delete $.curveMultiplierCooldownUntil[nodeOperatorId];
                emit CurveMultiplierCooldownRemoved(nodeOperatorId);
            }
            ACCOUNTING.setBondCurveMultiplier(nodeOperatorId, newMulInc);
        } else {
            if ($.curveMultiplierCooldownUntil[nodeOperatorId] != 0) revert CurveMultiplierCooldownActive();
            _setCurveMultiplierCooldown(nodeOperatorId);
        }

        $.operatorTier[nodeOperatorId] = tierId;
        emit TierSelected(nodeOperatorId, tierId);

        META_REGISTRY.refreshOperatorWeight(nodeOperatorId);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function releaseCurveMultiplier(uint256 nodeOperatorId) external {
        _checkOperatorOwner(nodeOperatorId);

        AdditionalBondRegistryStorage storage $ = _storage();
        uint256 cooldownUntil = $.curveMultiplierCooldownUntil[nodeOperatorId];
        if (cooldownUntil == 0) revert NoCurveMultiplierCooldown();
        if (cooldownUntil > block.timestamp) revert CurveMultiplierCooldownNotElapsed();

        delete $.curveMultiplierCooldownUntil[nodeOperatorId];
        emit CurveMultiplierCooldownRemoved(nodeOperatorId);

        ACCOUNTING.setBondCurveMultiplier(
            nodeOperatorId,
            getTierInfo($.operatorTier[nodeOperatorId]).curveMultiplierInc
        );
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
        state.weightMultiplier = MAX_BP + $.tiers[state.tierId].weightMultiplierInc;
        state.curveMultiplier = ACCOUNTING.getBondCurveMultiplier(nodeOperatorId);
    }

    /// @inheritdoc IAdditionalBondRegistry
    function getTierInfo(uint256 tierId) public view returns (TierInfo memory) {
        AdditionalBondRegistryStorage storage $ = _storage();
        if (tierId > $.tiersCount) revert InvalidTierId();
        if (tierId == 0) return TierInfo({ curveMultiplierInc: 0, weightMultiplierInc: 0 });
        return $.tiers[tierId];
    }

    /// @dev Sets the cooldown deadline to `block.timestamp + CURVE_MULTIPLIER_COOLDOWN`.
    function _setCurveMultiplierCooldown(uint256 nodeOperatorId) internal {
        uint256 cooldownUntil = block.timestamp + CURVE_MULTIPLIER_COOLDOWN;
        _storage().curveMultiplierCooldownUntil[nodeOperatorId] = cooldownUntil;
        emit CurveMultiplierCooldownSet(nodeOperatorId, cooldownUntil);
    }

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
