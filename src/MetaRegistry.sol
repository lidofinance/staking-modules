// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBondCurve } from "./interfaces/IBondCurve.sol";
import { INodeOperatorsRegistry } from "./interfaces/INodeOperatorsRegistry.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IWeightBoostProvider } from "./interfaces/IWeightBoostProvider.sol";
import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { IStakingRouter } from "./interfaces/IStakingRouter.sol";
import { IMetaRegistry, OperatorMetadata } from "./interfaces/IMetaRegistry.sol";
import { IAdditionalBondRegistry } from "./interfaces/IAdditionalBondRegistry.sol";
import { ExternalOperatorLib, OperatorType } from "./lib/ExternalOperatorLib.sol";
import { MAX_BP } from "./lib/Constants.sol";
import { ValidatorBalanceLimits } from "./lib/ValidatorBalanceLimits.sol";

/// @notice Stores meta-operator group definitions and weight composition for the curated module.
contract MetaRegistry is IMetaRegistry, Initializable, AccessControlEnumerableUpgradeable {
    using ExternalOperatorLib for ExternalOperator;

    uint64 internal constant INITIALIZED_VERSION = 2;

    struct CachedOperatorGroup {
        string name;
        uint64[] subNodeOperatorIds;
        ExternalOperator[] externalOperators;
    }

    struct GroupIndex {
        mapping(uint256 nodeOperatorId => uint256 groupId) groupIdByOperatorId;
        mapping(bytes32 externalKey => uint256 groupId) groupIdByExternalKey;
        mapping(uint256 nodeOperatorId => uint16 share) shareByOperatorId;
    }

    struct EffectiveWeightCache {
        // Invariant: operators outside any group must have zero cached effective weight.
        mapping(uint256 nodeOperatorId => uint256 weight) operatorEffectiveWeight;
        mapping(uint256 groupId => uint256 weight) groupEffectiveWeightSum;
    }

    /// @custom:storage-location erc7201:MetaRegistry
    struct MetaRegistryStorage {
        mapping(uint256 curveId => uint256 weight) bondCurveWeight;
        mapping(uint256 groupId => CachedOperatorGroup) groups;
        GroupIndex groupIndex;
        EffectiveWeightCache effectiveWeightCache;
        mapping(uint256 nodeOperatorId => OperatorMetadata) operatorMetadata;
        mapping(uint256 moduleId => address moduleAddress) moduleAddressCache;
        uint256 groupsCount;
        mapping(uint256 providerId => WeightBoostProviderEntry entry) weightBoostProviders;
        mapping(address provider => uint256 providerId) weightBoostProviderIdByAddress;
        uint256 weightBoostProvidersCount;
        uint256 stakeCap;
    }

    bytes32 public constant MANAGE_OPERATOR_GROUPS_ROLE = keccak256("MANAGE_OPERATOR_GROUPS_ROLE");
    bytes32 public constant SET_OPERATOR_INFO_ROLE = keccak256("SET_OPERATOR_INFO_ROLE");
    bytes32 public constant SET_BOND_CURVE_WEIGHT_ROLE = keccak256("SET_BOND_CURVE_WEIGHT_ROLE");
    bytes32 public constant MANAGE_STAKE_CAP_ROLE = keccak256("MANAGE_STAKE_CAP_ROLE");

    // ID of the stub node operator group that means "not in any group". This value is used for all node operators that are not assigned to any group, so it
    // can't be used as a real group ID.
    uint256 public constant NO_GROUP_ID = 0;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IStakingRouter public immutable STAKING_ROUTER;
    IAdditionalBondRegistry public immutable ADDITIONAL_BOND_REGISTRY;

    uint256 internal constant EXTERNAL_STAKE_PER_VALIDATOR = 32 ether;
    uint256 internal constant MAX_NAME_LENGTH = 256;
    uint256 internal constant MAX_DESCRIPTION_LENGTH = 1024;

    // keccak256(abi.encode(uint256(keccak256("MetaRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant META_REGISTRY_STORAGE_LOCATION =
        0xa7ec41e1a061c67796a04fcd9cc7cab9545b0a750beebc54139d9ed9d2251c00;

    /// @param module       CuratedModule proxy address.
    /// @param additionalBondRegistry AdditionalBondRegistry proxy address.
    constructor(address module, address additionalBondRegistry) {
        if (module == address(0)) revert ZeroModuleAddress();

        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        STAKING_ROUTER = IStakingRouter(MODULE.LIDO_LOCATOR().stakingRouter());
        ADDITIONAL_BOND_REGISTRY = IAdditionalBondRegistry(additionalBondRegistry);

        _disableInitializers();
    }

    /// @inheritdoc IMetaRegistry
    function initialize(address admin, uint256 initialCap) external reinitializer(INITIALIZED_VERSION) {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setStakeCap(initialCap);
    }

    /// @inheritdoc IMetaRegistry
    function finalizeUpgradeV2(uint256 initialCap) external reinitializer(INITIALIZED_VERSION) {
        _setStakeCap(initialCap);
    }

    /// @inheritdoc IMetaRegistry
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IMetaRegistry
    function stakeCap() external view returns (uint256 cap) {
        return _storage().stakeCap;
    }

    /// @inheritdoc IMetaRegistry
    function setStakeCap(uint256 newCap) external onlyRole(MANAGE_STAKE_CAP_ROLE) {
        _setStakeCap(newCap);
    }

    /// @inheritdoc IMetaRegistry
    function setOperatorMetadataAsAdmin(
        uint256 nodeOperatorId,
        OperatorMetadata calldata metadata
    ) external onlyRole(SET_OPERATOR_INFO_ROLE) {
        _onlyExistingOperator(address(MODULE), nodeOperatorId);
        _storeOperatorMetadata(nodeOperatorId, metadata);
    }

    /// @inheritdoc IMetaRegistry
    function setOperatorMetadataAsOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        address owner = _nodeOperatorOwner(address(MODULE), nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert SenderIsNotEligible();

        OperatorMetadata storage stored = _storage().operatorMetadata[nodeOperatorId];
        bool ownerEditsRestricted = stored.ownerEditsRestricted;
        if (ownerEditsRestricted) revert OwnerEditsRestricted();

        _storeOperatorMetadata(
            nodeOperatorId,
            OperatorMetadata({ name: name, description: description, ownerEditsRestricted: ownerEditsRestricted })
        );
    }

    /// @inheritdoc IMetaRegistry
    function createOrUpdateOperatorGroup(
        uint256 groupId,
        OperatorGroup calldata groupInfo
    ) external onlyRole(MANAGE_OPERATOR_GROUPS_ROLE) {
        if (groupId == NO_GROUP_ID) {
            _createGroup(groupInfo);
        } else {
            _updateGroup(groupId, groupInfo);
        }
    }

    /// @inheritdoc IMetaRegistry
    function setBondCurveWeight(uint256 curveId, uint256 weight) external onlyRole(SET_BOND_CURVE_WEIGHT_ROLE) {
        MetaRegistryStorage storage $ = _storage();
        if (curveId >= ACCOUNTING.getCurvesCount()) revert IBondCurve.InvalidBondCurveId();
        if (weight != 0 && weight < MAX_BP) revert InvalidBondCurveWeight();
        if ($.bondCurveWeight[curveId] == weight) revert SameBondCurveWeight();

        $.bondCurveWeight[curveId] = weight;
        emit BondCurveWeightSet(curveId, weight);
        _requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function addWeightBoostProvider(
        IWeightBoostProvider provider,
        WeightBoostProviderMode mode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address providerAddr = address(provider);
        if (providerAddr == address(0)) revert InvalidWeightBoostProvider();

        MetaRegistryStorage storage $ = _storage();
        if ($.weightBoostProviderIdByAddress[providerAddr] != 0) {
            revert WeightBoostProviderAlreadyAdded();
        }

        uint256 providerId = ++$.weightBoostProvidersCount;
        $.weightBoostProviders[providerId] = WeightBoostProviderEntry({
            provider: provider,
            mode: mode,
            enabled: true
        });
        $.weightBoostProviderIdByAddress[providerAddr] = providerId;
        emit WeightBoostProviderAdded(providerAddr, mode);
        _requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function setWeightBoostProviderEnabled(uint256 providerId, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MetaRegistryStorage storage $ = _storage();
        WeightBoostProviderEntry storage entry = $.weightBoostProviders[providerId];
        address providerAddr = address(entry.provider);
        if (providerAddr == address(0)) revert WeightBoostProviderNotFound();
        if (entry.enabled == enabled) revert SameWeightBoostProviderEnabled();

        entry.enabled = enabled;
        emit WeightBoostProviderEnabledSet(providerAddr, enabled);
        _requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function refreshOperatorWeight(uint256 nodeOperatorId) external {
        uint256 groupId = _storage().groupIndex.groupIdByOperatorId[nodeOperatorId];
        if (groupId == NO_GROUP_ID) return;

        _refreshOperatorWeight(groupId, nodeOperatorId);
    }

    /// @inheritdoc IMetaRegistry
    function refreshGroupWeights(uint256 groupId) external {
        if (groupId == NO_GROUP_ID) revert InvalidOperatorGroupId();
        if (groupId > _storage().groupsCount) revert InvalidOperatorGroupId();

        _refreshGroupWeights(groupId);
    }

    /// @inheritdoc IMetaRegistry
    function notifyWeightBoostProviderConfigChanged() external {
        MetaRegistryStorage storage $ = _storage();
        uint256 providerId = $.weightBoostProviderIdByAddress[msg.sender];
        if (providerId == 0) revert WeightBoostProviderNotFound();

        if (!$.weightBoostProviders[providerId].enabled) return;

        emit WeightBoostProviderConfigChanged(msg.sender);
        _requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function notifyWeightBoostChanged(uint256 nodeOperatorId) external {
        MetaRegistryStorage storage $ = _storage();
        uint256 providerId = $.weightBoostProviderIdByAddress[msg.sender];
        if (providerId == 0) revert WeightBoostProviderNotFound();

        uint256 groupId = $.groupIndex.groupIdByOperatorId[nodeOperatorId];
        // Provider notifications are node-operator scoped; operators outside groups have no group cache to refresh.
        if (groupId == NO_GROUP_ID) return;

        WeightBoostProviderEntry storage entry = $.weightBoostProviders[providerId];
        if (!entry.enabled) return;

        if (entry.mode == WeightBoostProviderMode.NodeOperator) {
            _refreshOperatorWeight(groupId, nodeOperatorId);
            return;
        }

        if (entry.mode == WeightBoostProviderMode.GroupMax) {
            _refreshGroupWeights(groupId);
            return;
        }

        revert InvalidWeightBoostProviderMode();
    }

    /// @inheritdoc IMetaRegistry
    function getWeightBoostProviders() external view returns (IWeightBoostProvider[] memory providers) {
        MetaRegistryStorage storage $ = _storage();
        uint256 providersCount = $.weightBoostProvidersCount;
        providers = new IWeightBoostProvider[](providersCount);
        for (uint256 i; i < providersCount; ++i) {
            providers[i] = $.weightBoostProviders[i + 1].provider;
        }
    }

    /// @inheritdoc IMetaRegistry
    function getWeightBoostProvidersCount() external view returns (uint256 count) {
        count = _storage().weightBoostProvidersCount;
    }

    /// @inheritdoc IMetaRegistry
    function getWeightBoostProvider(uint256 providerId) external view returns (WeightBoostProviderEntry memory entry) {
        entry = _storage().weightBoostProviders[providerId];
    }

    /// @inheritdoc IMetaRegistry
    function getWeightBoostProviderMode(uint256 providerId) external view returns (WeightBoostProviderMode mode) {
        mode = _storage().weightBoostProviders[providerId].mode;
    }

    /// @inheritdoc IMetaRegistry
    function getWeightBoostProviderId(address provider) external view returns (uint256 providerId) {
        providerId = _storage().weightBoostProviderIdByAddress[provider];
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorMetadata(uint256 nodeOperatorId) external view returns (OperatorMetadata memory metadata) {
        return _storage().operatorMetadata[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorGroup(uint256 groupId) external view returns (OperatorGroup memory groupInfo) {
        MetaRegistryStorage storage $ = _storage();
        if (groupId > $.groupsCount) revert InvalidOperatorGroupId();

        CachedOperatorGroup storage group = $.groups[groupId];
        groupInfo.name = group.name;
        uint256 subOpCount = group.subNodeOperatorIds.length;
        groupInfo.subNodeOperators = new SubNodeOperator[](subOpCount);
        for (uint256 i; i < subOpCount; ++i) {
            uint64 noId = group.subNodeOperatorIds[i];
            groupInfo.subNodeOperators[i] = SubNodeOperator({
                nodeOperatorId: noId,
                share: $.groupIndex.shareByOperatorId[noId]
            });
        }
        groupInfo.externalOperators = group.externalOperators;
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorGroupsCount() external view returns (uint256 count) {
        count = _storage().groupsCount;
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorGroupId(uint256 nodeOperatorId) external view returns (uint256 operatorGroupId) {
        operatorGroupId = _storage().groupIndex.groupIdByOperatorId[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function getExternalOperatorGroupId(ExternalOperator calldata op) external view returns (uint256 operatorGroupId) {
        operatorGroupId = _storage().groupIndex.groupIdByExternalKey[op.uniqueKey()];
    }

    /// @inheritdoc IMetaRegistry
    function getBondCurveWeight(uint256 curveId) external view returns (uint256 weight) {
        weight = _storage().bondCurveWeight[curveId];
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorWeight(uint256 nodeOperatorId) external view returns (uint256 weight) {
        weight = _storage().effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake) {
        MetaRegistryStorage storage $ = _storage();
        uint256 groupId = $.groupIndex.groupIdByOperatorId[nodeOperatorId];
        // If Node Operator is not in any group, it has no weight and external stake.
        if (groupId == NO_GROUP_ID) return (0, 0);

        weight = $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId];
        // If the operator has no weight, it can't have external stake either, so we can skip the calculations.
        if (weight == 0) return (0, 0);

        uint256 totalExternalStake = _totalExternalStake($.groups[groupId].externalOperators);
        if (totalExternalStake == 0) return (weight, 0);

        externalStake = Math.mulDiv(
            totalExternalStake,
            weight,
            $.effectiveWeightCache.groupEffectiveWeightSum[groupId]
        );
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorWeights(
        uint256[] calldata nodeOperatorIds
    ) external view returns (uint256[] memory operatorWeights) {
        MetaRegistryStorage storage $ = _storage();
        uint256 count = nodeOperatorIds.length;
        operatorWeights = new uint256[](count);

        for (uint256 i; i < count; ++i) {
            operatorWeights[i] = $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorIds[i]];
        }
    }

    function _createGroup(OperatorGroup calldata groupInfo) internal {
        if (groupInfo.subNodeOperators.length == 0) revert InvalidOperatorGroup();

        uint256 groupId = ++_storage().groupsCount;
        _storeGroupData(groupId, groupInfo);
        _refreshGroupWeights(groupId);
        emit OperatorGroupCreated(groupId, groupInfo);
    }

    function _updateGroup(uint256 groupId, OperatorGroup calldata groupInfo) internal {
        _resetGroup(groupId);

        if (groupInfo.subNodeOperators.length == 0) {
            // NOTE: Sanity check for an empty group in `groupInfo`.
            if (groupInfo.externalOperators.length != 0 || bytes(groupInfo.name).length != 0)
                revert InvalidOperatorGroup();

            emit OperatorGroupCleared(groupId);
        } else {
            _storeGroupData(groupId, groupInfo);
            _refreshGroupWeights(groupId);
            emit OperatorGroupUpdated(groupId, groupInfo);
        }
    }

    function _storeGroupData(uint256 groupId, OperatorGroup calldata groupInfo) internal {
        _setGroupName(groupId, groupInfo.name);
        _storeSubOperators(groupId, groupInfo.subNodeOperators);
        _storeExternalOperators(groupId, groupInfo.externalOperators);
    }

    function _resetGroup(uint256 groupId) internal {
        MetaRegistryStorage storage $ = _storage();
        if (groupId > $.groupsCount) revert InvalidOperatorGroupId();

        CachedOperatorGroup storage group = $.groups[groupId];

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] = 0;

        uint256 subOperatorsCount = group.subNodeOperatorIds.length;
        for (uint256 i; i < subOperatorsCount; ++i) {
            uint256 noId = group.subNodeOperatorIds[i];
            delete $.groupIndex.groupIdByOperatorId[noId];
            delete $.groupIndex.shareByOperatorId[noId];
            // Keep removed operators consistent with direct cache-backed weight reads.
            _setEffectiveWeight(noId, 0);
        }

        uint256 externalOperatorsCount = group.externalOperators.length;
        for (uint256 i; i < externalOperatorsCount; ++i) {
            delete $.groupIndex.groupIdByExternalKey[group.externalOperators[i].uniqueKey()];
        }

        delete group.subNodeOperatorIds;
        delete group.externalOperators;
        delete group.name;
    }

    function _setGroupName(uint256 groupId, string calldata name) internal {
        if (bytes(name).length > MAX_NAME_LENGTH) revert InvalidOperatorGroupName();
        _storage().groups[groupId].name = name;
    }

    function _storeSubOperators(uint256 groupId, SubNodeOperator[] calldata subNodeOperators) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        uint256 shareSum;
        for (uint256 i; i < subNodeOperators.length; ++i) {
            uint64 noId = subNodeOperators[i].nodeOperatorId;
            uint16 share = subNodeOperators[i].share;

            _onlyExistingOperator(address(MODULE), noId);

            if ($.groupIndex.groupIdByOperatorId[noId] != NO_GROUP_ID) revert NodeOperatorAlreadyInGroup(noId);
            $.groupIndex.groupIdByOperatorId[noId] = groupId;
            $.groupIndex.shareByOperatorId[noId] = share;
            group.subNodeOperatorIds.push(noId);

            shareSum += share;
        }

        if (shareSum != MAX_BP) revert InvalidSubNodeOperatorShares();
    }

    function _storeExternalOperators(uint256 groupId, ExternalOperator[] calldata externalOperators) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        for (uint256 i; i < externalOperators.length; ++i) {
            ExternalOperator memory op = externalOperators[i];
            bytes32 extKey = op.uniqueKey();

            if ($.groupIndex.groupIdByExternalKey[extKey] != NO_GROUP_ID) revert AlreadyUsedAsExternalOperator();

            OperatorType opType = op.tryGetExtOpType();
            if (opType == OperatorType.NOR) _checkExternalOperatorExistsTypeNOR(op);

            $.groupIndex.groupIdByExternalKey[extKey] = groupId;
            group.externalOperators.push(op);
        }
    }

    /// @dev `noId` should be a part of group with `groupId`.
    function _refreshOperatorWeight(uint256 groupId, uint256 noId) internal {
        MetaRegistryStorage storage $ = _storage();
        uint256 share = $.groupIndex.shareByOperatorId[noId];

        uint256 multiplierBP = _getWeightBoostMultiplierBP($.groups[groupId], noId);
        uint256 newWeight = _getLatestEffectiveWeight(noId, share, multiplierBP);
        uint256 oldWeight = _setEffectiveWeight(noId, newWeight);

        if (oldWeight != newWeight) {
            // It's unlikely in practice that the new weight will be large enough to lead to an overflow
            // and the old weight subtraction can't underflow since it's part of the weight sum.
            unchecked {
                $.effectiveWeightCache.groupEffectiveWeightSum[groupId] =
                    $.effectiveWeightCache.groupEffectiveWeightSum[groupId] +
                    newWeight -
                    oldWeight;
            }
        }
    }

    function _refreshGroupWeights(uint256 groupId) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];
        uint256 providersCount = $.weightBoostProvidersCount;
        uint256[] memory groupMaxMultipliersBP = new uint256[](providersCount);
        bool[] memory groupMaxMultiplierCached = new bool[](providersCount);

        uint256 effectiveWeightSum;
        uint256 subOperatorsCount = group.subNodeOperatorIds.length;
        for (uint256 i; i < subOperatorsCount; ++i) {
            uint256 noId = group.subNodeOperatorIds[i];
            uint256 share = $.groupIndex.shareByOperatorId[noId];
            // Keep full-group and single-operator refreshes on the same ordered multiplier path.
            // Each Math.mulDiv floors, so pre-aggregating providers by mode can produce different weights.
            uint256 multiplierBP = _getWeightBoostMultiplierBP(
                group,
                noId,
                groupMaxMultipliersBP,
                groupMaxMultiplierCached
            );
            uint256 effectiveWeight = _getLatestEffectiveWeight(noId, share, multiplierBP);
            _setEffectiveWeight(noId, effectiveWeight);
            effectiveWeightSum += effectiveWeight;
        }

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] = effectiveWeightSum;
        emit GroupWeightsRefreshed(groupId);
    }

    function _setEffectiveWeight(uint256 nodeOperatorId, uint256 newWeight) internal returns (uint256 oldWeight) {
        MetaRegistryStorage storage $ = _storage();
        oldWeight = $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId];

        if (oldWeight == newWeight) return oldWeight;

        $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId] = newWeight;
        emit NodeOperatorEffectiveWeightChanged(nodeOperatorId, oldWeight, newWeight);

        MODULE.notifyNodeOperatorWeightChange(nodeOperatorId, oldWeight, newWeight);
    }

    function _requestFullDepositInfoUpdate() internal {
        MODULE.requestFullDepositInfoUpdate();
    }

    function _setStakeCap(uint256 newCap) internal {
        if (newCap == 0 || newCap % ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE != 0) revert InvalidStakeCap();

        MetaRegistryStorage storage $ = _storage();
        uint256 previousCap = $.stakeCap;
        if (newCap == previousCap) revert SameStakeCap();

        $.stakeCap = newCap;
        emit StakeCapSet(previousCap, newCap);
        _requestFullDepositInfoUpdate();
    }

    function _storeOperatorMetadata(uint256 nodeOperatorId, OperatorMetadata memory metadata) internal {
        if (bytes(metadata.name).length > MAX_NAME_LENGTH) revert OperatorNameTooLong();
        if (bytes(metadata.description).length > MAX_DESCRIPTION_LENGTH) revert OperatorDescriptionTooLong();
        _storage().operatorMetadata[nodeOperatorId] = metadata;
        emit OperatorMetadataSet({ nodeOperatorId: nodeOperatorId, metadata: metadata });
    }

    function _checkExternalOperatorExistsTypeNOR(ExternalOperator memory op) internal {
        (uint8 moduleId, uint64 noId) = op.unpackEntryTypeNOR();
        address module = _getOrCacheModuleAddress(moduleId);
        if (noId >= INodeOperatorsRegistry(module).getNodeOperatorsCount()) revert NodeOperatorDoesNotExist();
    }

    /// @dev Returns the module address for `moduleId`, resolving from
    ///      STAKING_ROUTER on cache miss.
    function _getOrCacheModuleAddress(uint8 moduleId) internal returns (address addr) {
        addr = _storage().moduleAddressCache[moduleId];
        if (addr == address(0)) {
            addr = STAKING_ROUTER.getStakingModule(moduleId).stakingModuleAddress;
            _storage().moduleAddressCache[moduleId] = addr;
        }
    }

    function _getLatestEffectiveWeight(
        uint256 nodeOperatorId,
        uint256 share,
        uint256 multiplierBP
    ) internal view returns (uint256) {
        uint256 baseWeight = _getOperatorBaseWeight(nodeOperatorId);
        if (baseWeight == 0 || share == 0) return 0;

        uint256 sharedBaseWeight = Math.mulDiv(baseWeight, share, MAX_BP);
        return Math.mulDiv(sharedBaseWeight, multiplierBP, MAX_BP);
    }

    function _getOperatorBaseWeight(uint256 nodeOperatorId) internal view returns (uint256) {
        return _storage().bondCurveWeight[ACCOUNTING.getBondCurveId(nodeOperatorId)];
    }

    function _getWeightBoostMultiplierBP(
        CachedOperatorGroup storage group,
        uint256 nodeOperatorId
    ) internal view returns (uint256 multiplierBP) {
        MetaRegistryStorage storage $ = _storage();
        multiplierBP = MAX_BP;
        uint256 providersCount = $.weightBoostProvidersCount;
        for (uint256 i; i < providersCount; ++i) {
            WeightBoostProviderEntry storage entry = $.weightBoostProviders[i + 1];
            if (!entry.enabled) continue;

            IWeightBoostProvider provider = entry.provider;
            if (entry.mode == WeightBoostProviderMode.NodeOperator) {
                multiplierBP = Math.mulDiv(multiplierBP, provider.getWeightBoostMultiplierBP(nodeOperatorId), MAX_BP);
            } else if (entry.mode == WeightBoostProviderMode.GroupMax) {
                multiplierBP = Math.mulDiv(
                    multiplierBP,
                    _getProviderGroupMaxWeightBoostMultiplierBP(provider, group),
                    MAX_BP
                );
            } else {
                revert InvalidWeightBoostProviderMode();
            }
        }
    }

    function _getWeightBoostMultiplierBP(
        CachedOperatorGroup storage group,
        uint256 nodeOperatorId,
        uint256[] memory groupMaxMultipliersBP,
        bool[] memory groupMaxMultiplierCached
    ) internal view returns (uint256 multiplierBP) {
        MetaRegistryStorage storage $ = _storage();
        multiplierBP = MAX_BP;
        uint256 providersCount = groupMaxMultipliersBP.length;
        for (uint256 i; i < providersCount; ++i) {
            WeightBoostProviderEntry storage entry = $.weightBoostProviders[i + 1];
            if (!entry.enabled) continue;

            IWeightBoostProvider provider = entry.provider;
            if (entry.mode == WeightBoostProviderMode.NodeOperator) {
                multiplierBP = Math.mulDiv(multiplierBP, provider.getWeightBoostMultiplierBP(nodeOperatorId), MAX_BP);
            } else if (entry.mode == WeightBoostProviderMode.GroupMax) {
                if (!groupMaxMultiplierCached[i]) {
                    groupMaxMultipliersBP[i] = _getProviderGroupMaxWeightBoostMultiplierBP(provider, group);
                    groupMaxMultiplierCached[i] = true;
                }
                multiplierBP = Math.mulDiv(multiplierBP, groupMaxMultipliersBP[i], MAX_BP);
            } else {
                revert InvalidWeightBoostProviderMode();
            }
        }
    }

    function _getProviderGroupMaxWeightBoostMultiplierBP(
        IWeightBoostProvider provider,
        CachedOperatorGroup storage group
    ) internal view returns (uint256 maxMultiplierBP) {
        uint256 subOperatorsCount = group.subNodeOperatorIds.length;
        if (subOperatorsCount == 0) return MAX_BP;

        maxMultiplierBP = provider.getWeightBoostMultiplierBP(group.subNodeOperatorIds[0]);
        for (uint256 i = 1; i < subOperatorsCount; ++i) {
            uint256 candidateMultiplierBP = provider.getWeightBoostMultiplierBP(group.subNodeOperatorIds[i]);
            if (candidateMultiplierBP > maxMultiplierBP) {
                maxMultiplierBP = candidateMultiplierBP;
            }
        }
    }

    /// @dev Returns the cached module address. Reverts if the address was
    ///      never resolved via `_getOrCacheModuleAddress`.
    function _getCachedModuleAddress(uint8 moduleId) internal view returns (address addr) {
        addr = _storage().moduleAddressCache[moduleId];
        if (addr == address(0)) revert ModuleAddressNotCached();
    }

    function _onlyExistingOperator(address module, uint256 nodeOperatorId) internal view {
        if (!_nodeOperatorExists(module, nodeOperatorId)) revert NodeOperatorDoesNotExist();
    }

    function _nodeOperatorExists(address module, uint256 nodeOperatorId) internal view returns (bool) {
        return nodeOperatorId < IStakingModule(module).getNodeOperatorsCount();
    }

    function _nodeOperatorOwner(address module, uint256 nodeOperatorId) internal view returns (address) {
        return IBaseModule(module).getNodeOperatorOwner(nodeOperatorId);
    }

    function _totalExternalStake(
        ExternalOperator[] storage externalOperators
    ) internal view returns (uint256 totalExternalStake) {
        uint256 externalOperatorsCount = externalOperators.length;
        for (uint256 i; i < externalOperatorsCount; ++i) {
            ExternalOperator memory op = externalOperators[i];

            OperatorType opType = op.tryGetExtOpType();
            if (opType == OperatorType.NOR) totalExternalStake += _getOperatorExternalStakeTypeNOR(op);
        }
    }

    function _getOperatorExternalStakeTypeNOR(ExternalOperator memory op) internal view returns (uint256 stake) {
        (uint8 moduleId, uint64 noId) = op.unpackEntryTypeNOR();

        // NOTE: The module address is expected to be cached during _storeExternalOperators.
        address module = _getCachedModuleAddress(moduleId);

        (, , , , uint64 totalExitedValidators, , uint64 totalDepositedValidators) = INodeOperatorsRegistry(module)
            .getNodeOperator(noId, false);
        stake = (totalDepositedValidators - totalExitedValidators) * EXTERNAL_STAKE_PER_VALIDATOR;
    }

    function _storage() internal pure returns (MetaRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := META_REGISTRY_STORAGE_LOCATION
        }
    }
}
