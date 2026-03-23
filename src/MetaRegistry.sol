// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { INodeOperatorsRegistry } from "./interfaces/INodeOperatorsRegistry.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { IStakingRouter } from "./interfaces/IStakingRouter.sol";
import { IMetaRegistry, OperatorMetadata } from "./interfaces/IMetaRegistry.sol";
import { ExternalOperatorLib, OperatorType } from "./lib/ExternalOperatorLib.sol";

/// @notice Stores meta-operator group definitions for the curated module.
contract MetaRegistry is IMetaRegistry, Initializable, AccessControlEnumerableUpgradeable {
    using ExternalOperatorLib for ExternalOperator;

    struct CachedOperatorGroup {
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
        CachedOperatorGroup[] groups;
        GroupIndex groupIndex;
        EffectiveWeightCache effectiveWeightCache;
        mapping(uint256 nodeOperatorId => OperatorMetadata) operatorMetadata;
        mapping(uint256 moduleId => address moduleAddress) moduleAddressCache;
    }

    bytes32 public constant MANAGE_OPERATOR_GROUPS_ROLE = keccak256("MANAGE_OPERATOR_GROUPS_ROLE");
    bytes32 public constant SET_OPERATOR_INFO_ROLE = keccak256("SET_OPERATOR_INFO_ROLE");
    bytes32 public constant SET_BOND_CURVE_WEIGHT_ROLE = keccak256("SET_BOND_CURVE_WEIGHT_ROLE");

    // ID of the stub node operator group that means "not in any group". This value is used for all node operators that are not assigned to any group, so it
    // can't be used as a real group ID.
    uint256 public constant NO_GROUP_ID = 0;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IStakingRouter public immutable STAKING_ROUTER;

    uint256 internal constant MAX_BP = 10000;
    uint256 internal constant EXTERNAL_STAKE_PER_VALIDATOR = 32 ether;

    // keccak256(abi.encode(uint256(keccak256("MetaRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant META_REGISTRY_STORAGE_LOCATION =
        0xa7ec41e1a061c67796a04fcd9cc7cab9545b0a750beebc54139d9ed9d2251c00;

    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();

        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        STAKING_ROUTER = IStakingRouter(MODULE.LIDO_LOCATOR().stakingRouter());

        _disableInitializers();
    }

    /// @inheritdoc IMetaRegistry
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // NOTE: Put a stone to reserve the NO_GROUP_ID.
        _storage().groups.push();
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
        MetaRegistryStorage storage $ = _storage();
        if (groupId >= $.groups.length) revert InvalidOperatorGroupId();
        if (groupId == NO_GROUP_ID) {
            _createGroup(groupInfo);
        } else {
            _updateGroup(groupId, groupInfo);
        }
    }

    /// @inheritdoc IMetaRegistry
    function setBondCurveWeight(uint256 curveId, uint256 weight) external onlyRole(SET_BOND_CURVE_WEIGHT_ROLE) {
        MetaRegistryStorage storage $ = _storage();
        if ($.bondCurveWeight[curveId] == weight) revert SameBondCurveWeight();

        $.bondCurveWeight[curveId] = weight;
        emit BondCurveWeightSet(curveId, weight);
        MODULE.requestFullDepositInfoUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function refreshOperatorWeight(uint256 nodeOperatorId) external {
        uint256 groupId = _storage().groupIndex.groupIdByOperatorId[nodeOperatorId];
        if (groupId == NO_GROUP_ID) return;

        _refreshOperatorWeight(groupId, nodeOperatorId);
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorMetadata(uint256 nodeOperatorId) external view returns (OperatorMetadata memory metadata) {
        return _storage().operatorMetadata[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorGroup(uint256 groupId) external view returns (OperatorGroup memory groupInfo) {
        MetaRegistryStorage storage $ = _storage();
        if (groupId >= $.groups.length) revert InvalidOperatorGroupId();

        CachedOperatorGroup storage group = $.groups[groupId];
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
        count = _storage().groups.length;
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
    function getNodeOperatorWeight(uint256 noId) external view returns (uint256 weight) {
        weight = _storage().effectiveWeightCache.operatorEffectiveWeight[noId];
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorWeightAndExternalStake(
        uint256 noId
    ) external view returns (uint256 weight, uint256 externalStake) {
        MetaRegistryStorage storage $ = _storage();
        uint256 groupId = $.groupIndex.groupIdByOperatorId[noId];
        // If Node Operator is not in any group, it has no weight and external stake.
        if (groupId == NO_GROUP_ID) return (0, 0);

        weight = $.effectiveWeightCache.operatorEffectiveWeight[noId];
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

        MetaRegistryStorage storage $ = _storage();
        uint256 groupId = $.groups.length;
        $.groups.push();

        _storeSubOperators(groupId, groupInfo.subNodeOperators);
        _storeExternalOperators(groupId, groupInfo.externalOperators);
        emit OperatorGroupCreated(groupId, groupInfo);
    }

    function _updateGroup(uint256 groupId, OperatorGroup calldata groupInfo) internal {
        _resetGroup(groupId);

        if (groupInfo.subNodeOperators.length == 0) {
            // NOTE: Sanity check for an empty group in `groupInfo`.
            if (groupInfo.externalOperators.length != 0) revert InvalidOperatorGroup();

            emit OperatorGroupCleared(groupId);
        } else {
            _storeSubOperators(groupId, groupInfo.subNodeOperators);
            _storeExternalOperators(groupId, groupInfo.externalOperators);
            emit OperatorGroupUpdated(groupId, groupInfo);
        }
    }

    function _resetGroup(uint256 groupId) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] = 0;

        for (uint256 i; i < group.subNodeOperatorIds.length; ++i) {
            uint256 noId = group.subNodeOperatorIds[i];
            delete $.groupIndex.groupIdByOperatorId[noId];
            delete $.groupIndex.shareByOperatorId[noId];
            // Keep removed operators consistent with direct cache-backed weight reads.
            _setEffectiveWeight(noId, 0);
        }

        for (uint256 i; i < group.externalOperators.length; ++i) {
            delete $.groupIndex.groupIdByExternalKey[group.externalOperators[i].uniqueKey()];
        }

        delete group.subNodeOperatorIds;
        delete group.externalOperators;
    }

    function _storeSubOperators(uint256 groupId, SubNodeOperator[] calldata subNodeOperators) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        uint256 shareSum;
        uint256 effectiveWeightSum;
        for (uint256 i; i < subNodeOperators.length; ++i) {
            uint64 noId = subNodeOperators[i].nodeOperatorId;
            uint16 share = subNodeOperators[i].share;

            _onlyExistingOperator(address(MODULE), noId);

            if ($.groupIndex.groupIdByOperatorId[noId] != NO_GROUP_ID) revert NodeOperatorAlreadyInGroup(noId);
            $.groupIndex.groupIdByOperatorId[noId] = groupId;
            $.groupIndex.shareByOperatorId[noId] = share;
            group.subNodeOperatorIds.push(noId);

            uint256 effectiveWeight = _getLatestEffectiveWeight(noId, share);
            _setEffectiveWeight(noId, effectiveWeight);
            effectiveWeightSum += effectiveWeight;
            shareSum += share;
        }

        if (shareSum != MAX_BP) revert InvalidSubNodeOperatorShares();

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] = effectiveWeightSum;
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

        uint256 newWeight = _getLatestEffectiveWeight(noId, share);
        uint256 oldWeight = _setEffectiveWeight(noId, newWeight);

        if (oldWeight != newWeight) {
            $.effectiveWeightCache.groupEffectiveWeightSum[groupId] =
                $.effectiveWeightCache.groupEffectiveWeightSum[groupId] +
                newWeight -
                oldWeight;
        }
    }

    function _setEffectiveWeight(uint256 nodeOperatorId, uint256 newWeight) internal returns (uint256 oldWeight) {
        MetaRegistryStorage storage $ = _storage();
        oldWeight = $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId];

        if (oldWeight == newWeight) return oldWeight;

        $.effectiveWeightCache.operatorEffectiveWeight[nodeOperatorId] = newWeight;
        emit NodeOperatorEffectiveWeightChanged(nodeOperatorId, oldWeight, newWeight);

        MODULE.notifyNodeOperatorWeightChange(nodeOperatorId, oldWeight, newWeight);
    }

    function _storeOperatorMetadata(uint256 nodeOperatorId, OperatorMetadata memory metadata) internal {
        if (bytes(metadata.name).length > 256) revert OperatorNameTooLong();
        if (bytes(metadata.description).length > 1024) revert OperatorDescriptionTooLong();
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

    function _getLatestEffectiveWeight(uint256 nodeOperatorId, uint256 share) internal view returns (uint256) {
        uint256 baseWeight = _getOperatorBaseWeight(nodeOperatorId);
        if (baseWeight == 0 || share == 0) return 0;
        return Math.mulDiv(baseWeight, share, MAX_BP);
    }

    function _getOperatorBaseWeight(uint256 nodeOperatorId) internal view returns (uint256) {
        return _storage().bondCurveWeight[ACCOUNTING.getBondCurveId(nodeOperatorId)];
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
        for (uint256 i; i < externalOperators.length; ++i) {
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
