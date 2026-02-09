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
import { IMetaRegistry, OperatorInfo } from "./interfaces/IMetaRegistry.sol";
import { ExternalOperatorLib, OperatorType } from "./lib/ExternalOperatorLib.sol";

/// @notice Stores meta-operator group definitions for the curated module.
contract MetaRegistry is
    IMetaRegistry,
    Initializable,
    AccessControlEnumerableUpgradeable
{
    using ExternalOperatorLib for ExternalOperator;

    struct CachedOperatorGroup {
        uint64[] subNodeOperatorIds;
        ExternalOperator[] externalOperators;
    }

    struct GroupIndex {
        mapping(uint256 nodeOperatorId => uint256) groupIdByOperatorId;
        mapping(bytes32 externalKey => uint256) groupIdByExternalKey;
        mapping(uint256 nodeOperatorId => uint16) shareByOperatorId;
    }

    struct EffectiveWeightCache {
        mapping(uint256 nodeOperatorId => uint256 weight) operatorEffectiveWeight;
        mapping(uint256 groupId => uint256 weight) groupEffectiveWeightSum;
    }

    /// @custom:storage-location erc7201:MetaRegistry
    struct MetaRegistryStorage {
        mapping(uint256 curveId => uint256 weight) bondCurveWeight;
        CachedOperatorGroup[] groups;
        GroupIndex groupIndex;
        EffectiveWeightCache effectiveWeightCache;
        mapping(uint256 nodeOperatorId => OperatorInfo) operatorMetadata;
    }

    bytes32 public constant MANAGE_OPERATOR_GROUPS_ROLE =
        keccak256("MANAGE_OPERATOR_GROUPS_ROLE");
    bytes32 public constant SET_OPERATOR_INFO_ROLE =
        keccak256("SET_OPERATOR_INFO_ROLE");
    bytes32 public constant SET_BOND_CURVE_WEIGHT_ROLE =
        keccak256("SET_BOND_CURVE_WEIGHT_ROLE");

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

        if (address(ACCOUNTING) == address(0)) revert ZeroAccountingAddress();
        if (address(STAKING_ROUTER) == address(0)) {
            revert ZeroStakingRouterAddress();
        }

        _disableInitializers();
    }

    /// @inheritdoc IMetaRegistry
    function initialize(address admin) external initializer {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // NOTE: Put a stone to reserve the NO_GROUP_ID.
        _storage().groups.push();
    }

    /// @inheritdoc IMetaRegistry
    function setOperatorMetadataAsAdmin(
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external onlyRole(SET_OPERATOR_INFO_ROLE) {
        _onlyExistingOperator(address(MODULE), nodeOperatorId);

        OperatorInfo storage stored = _storage().operatorMetadata[
            nodeOperatorId
        ];
        stored.name = info.name;
        stored.description = info.description;
        stored.ownerEditsRestricted = info.ownerEditsRestricted;

        emit OperatorDataSet({
            nodeOperatorId: nodeOperatorId,
            name: info.name,
            description: info.description,
            ownerEditsRestricted: info.ownerEditsRestricted
        });
    }

    /// @inheritdoc IMetaRegistry
    function setOperatorMetadataAsOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        address owner = _nodeOperatorOwner(address(MODULE), nodeOperatorId);
        if (owner == address(0)) {
            revert NodeOperatorDoesNotExist();
        }
        if (owner != msg.sender) {
            revert SenderIsNotEligible();
        }
        OperatorInfo storage stored = _storage().operatorMetadata[
            nodeOperatorId
        ];
        bool ownerEditsRestricted = stored.ownerEditsRestricted;
        if (ownerEditsRestricted) {
            revert OwnerEditsRestricted();
        }

        stored.name = name;
        stored.description = description;

        emit OperatorDataSet({
            nodeOperatorId: nodeOperatorId,
            name: name,
            description: description,
            ownerEditsRestricted: ownerEditsRestricted
        });
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorMetadata(
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        return _storage().operatorMetadata[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function createOrUpdateOperatorGroup(
        uint256 groupId,
        OperatorGroup calldata groupInfo
    ) external onlyRole(MANAGE_OPERATOR_GROUPS_ROLE) {
        MetaRegistryStorage storage $ = _storage();
        if (groupId >= $.groups.length) {
            revert InvalidOperatorGroupId();
        }

        if (groupId == NO_GROUP_ID) {
            uint256 newGroupId = _createGroup(groupInfo);
            emit OperatorGroupCreated(newGroupId, groupInfo);
        } else {
            _updateGroup(groupId, groupInfo);
            emit OperatorGroupUpdated(groupId);
        }
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorGroup(
        uint256 groupId
    ) external view returns (OperatorGroup memory groupInfo) {
        MetaRegistryStorage storage $ = _storage();
        if (groupId >= $.groups.length) {
            revert InvalidOperatorGroupId();
        }

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
        return _storage().groups.length;
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorGroupMembership(
        uint256 nodeOperatorId
    ) external view returns (uint256 operatorGroupId) {
        return _storage().groupIndex.groupIdByOperatorId[nodeOperatorId];
    }

    /// @inheritdoc IMetaRegistry
    function getExternalOperatorGroupMembership(
        ExternalOperator calldata op
    ) external view returns (uint256 operatorGroupId) {
        return _storage().groupIndex.groupIdByExternalKey[op.uniqueKey()];
    }

    /// @inheritdoc IMetaRegistry
    function getBondCurveWeight(
        uint256 curveId
    ) external view returns (uint256 weight) {
        weight = _storage().bondCurveWeight[curveId];
    }

    /// @inheritdoc IMetaRegistry
    function setBondCurveWeight(
        uint256 curveId,
        uint256 weight
    ) external onlyRole(SET_BOND_CURVE_WEIGHT_ROLE) {
        MetaRegistryStorage storage $ = _storage();
        if ($.bondCurveWeight[curveId] == weight) {
            revert SameBondCurveWeight();
        }

        $.bondCurveWeight[curveId] = weight;
        emit BondCurveWeightSet(curveId, weight);

        MODULE.requestFullOperatorWeightsUpdate();
    }

    /// @inheritdoc IMetaRegistry
    function getNodeOperatorWeightAndExternalStake(
        uint256 noId
    ) external view returns (uint256 weight, uint256 externalStake) {
        MetaRegistryStorage storage $ = _storage();
        uint256 groupId = $.groupIndex.groupIdByOperatorId[noId];
        // If Node Operator is not in any group, it has no weight and external stake.
        if (groupId == NO_GROUP_ID) {
            return (0, 0);
        }

        weight = $.effectiveWeightCache.operatorEffectiveWeight[noId];
        // If the operator has no weight, it can't have external stake either, so we can skip the calculations.
        if (weight == 0) {
            return (0, 0);
        }

        uint256 totalExternalStake = _totalExternalStake(
            $.groups[groupId].externalOperators
        );
        if (totalExternalStake == 0) {
            return (weight, 0);
        }

        externalStake = Math.mulDiv(
            totalExternalStake,
            weight,
            $.effectiveWeightCache.groupEffectiveWeightSum[groupId]
        );
    }

    /// @inheritdoc IMetaRegistry
    function getOperatorsWeights(
        uint256[] calldata nodeOperatorIds
    ) external view returns (uint256[] memory operatorWeights) {
        MetaRegistryStorage storage $ = _storage();
        uint256 count = nodeOperatorIds.length;
        operatorWeights = new uint256[](count);

        for (uint256 i; i < count; ++i) {
            operatorWeights[i] = $.effectiveWeightCache.operatorEffectiveWeight[
                nodeOperatorIds[i]
            ];
        }
    }

    /// @inheritdoc IMetaRegistry
    function refreshOperatorWeight(
        uint256 nodeOperatorId
    ) external returns (bool changed) {
        uint256 groupId = _storage().groupIndex.groupIdByOperatorId[
            nodeOperatorId
        ];
        if (groupId == NO_GROUP_ID) {
            return false;
        }

        return _refreshOperatorWeight(groupId, nodeOperatorId);
    }

    function _createGroup(
        OperatorGroup calldata groupInfo
    ) internal returns (uint256 groupId) {
        if (groupInfo.subNodeOperators.length == 0) {
            revert InvalidOperatorGroup();
        }

        MetaRegistryStorage storage $ = _storage();
        groupId = $.groups.length;
        $.groups.push();

        _storeSubOperators(groupId, groupInfo.subNodeOperators);
        _storeExternalOperators(groupId, groupInfo.externalOperators);
    }

    function _updateGroup(
        uint256 groupId,
        OperatorGroup calldata groupInfo
    ) internal {
        _resetGroup(groupId);

        if (groupInfo.subNodeOperators.length == 0) {
            // NOTE: Sanity check for an empty group in `groupInfo`.
            if (groupInfo.externalOperators.length != 0) {
                revert InvalidOperatorGroup();
            }

            return;
        }

        _storeSubOperators(groupId, groupInfo.subNodeOperators);
        _storeExternalOperators(groupId, groupInfo.externalOperators);
    }

    function _resetGroup(uint256 groupId) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] = 0;

        for (uint256 i; i < group.subNodeOperatorIds.length; ++i) {
            uint256 noId = group.subNodeOperatorIds[i];
            delete $.groupIndex.groupIdByOperatorId[noId];
            delete $.groupIndex.shareByOperatorId[noId];
            delete $.effectiveWeightCache.operatorEffectiveWeight[noId];
        }

        for (uint256 i; i < group.externalOperators.length; ++i) {
            ExternalOperator storage op = group.externalOperators[i];
            delete $.groupIndex.groupIdByExternalKey[op.uniqueKey()];
        }

        delete group.subNodeOperatorIds;
        delete group.externalOperators;
    }

    function _storeSubOperators(
        uint256 groupId,
        SubNodeOperator[] calldata subNodeOperators
    ) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        uint256 shareSum;
        uint256 effectiveWeightSum;
        for (uint256 i; i < subNodeOperators.length; ++i) {
            uint64 noId = subNodeOperators[i].nodeOperatorId;
            uint16 share = subNodeOperators[i].share;

            _onlyExistingOperator(address(MODULE), noId);

            if ($.groupIndex.groupIdByOperatorId[noId] != NO_GROUP_ID) {
                revert NodeOperatorAlreadyInGroup(noId);
            }
            $.groupIndex.groupIdByOperatorId[noId] = groupId;
            $.groupIndex.shareByOperatorId[noId] = share;
            group.subNodeOperatorIds.push(noId);

            uint256 effectiveWeight = _getLatestEffectiveWeight(noId, share);
            _setEffectiveWeight(noId, effectiveWeight);
            effectiveWeightSum += effectiveWeight;
            shareSum += share;
        }

        if (shareSum != MAX_BP) revert InvalidSubNodeOperatorShares();

        $.effectiveWeightCache.groupEffectiveWeightSum[
            groupId
        ] = effectiveWeightSum;
    }

    function _storeExternalOperators(
        uint256 groupId,
        ExternalOperator[] calldata externalOperators
    ) internal {
        MetaRegistryStorage storage $ = _storage();
        CachedOperatorGroup storage group = $.groups[groupId];

        for (uint256 i; i < externalOperators.length; ++i) {
            ExternalOperator calldata op = externalOperators[i];
            bytes32 extKey = op.uniqueKey();

            if ($.groupIndex.groupIdByExternalKey[extKey] != NO_GROUP_ID) {
                revert AlreadyUsedAsExternalOperator();
            }

            OperatorType opType = op.tryGetOpType();
            if (opType == OperatorType.NOR) {
                _checkExternalOperatorExistsTypeNOR(op);
            }

            $.groupIndex.groupIdByExternalKey[extKey] = groupId;
            group.externalOperators.push(op);
        }
    }

    /// @dev `noId` should be a part of group with `groupId`.
    function _refreshOperatorWeight(
        uint256 groupId,
        uint256 noId
    ) internal returns (bool changed) {
        MetaRegistryStorage storage $ = _storage();
        uint256 share = $.groupIndex.shareByOperatorId[noId];

        uint256 newWeight = _getLatestEffectiveWeight(noId, share);
        uint256 oldWeight = _setEffectiveWeight(noId, newWeight);

        if (oldWeight == newWeight) return false;

        $.effectiveWeightCache.groupEffectiveWeightSum[groupId] =
            $.effectiveWeightCache.groupEffectiveWeightSum[groupId] +
            newWeight -
            oldWeight;

        return true;
    }

    function _getLatestEffectiveWeight(
        uint256 nodeOperatorId,
        uint256 share
    ) internal view returns (uint256) {
        uint256 baseWeight = _getOperatorBaseWeight(nodeOperatorId);
        if (baseWeight == 0 || share == 0) return 0;
        return Math.mulDiv(baseWeight, share, MAX_BP);
    }

    function _getOperatorBaseWeight(
        uint256 nodeOperatorId
    ) internal view returns (uint256) {
        return
            _storage().bondCurveWeight[
                ACCOUNTING.getBondCurveId(nodeOperatorId)
            ];
    }

    function _setEffectiveWeight(
        uint256 nodeOperatorId,
        uint256 newWeight
    ) internal returns (uint256 oldWeight) {
        MetaRegistryStorage storage $ = _storage();
        oldWeight = $.effectiveWeightCache.operatorEffectiveWeight[
            nodeOperatorId
        ];

        if (oldWeight == newWeight) {
            return oldWeight;
        }

        $.effectiveWeightCache.operatorEffectiveWeight[
            nodeOperatorId
        ] = newWeight;
        emit NodeOperatorEffectiveWeightChanged(
            nodeOperatorId,
            oldWeight,
            newWeight
        );
    }

    function _checkExternalOperatorExistsTypeNOR(
        ExternalOperator calldata op
    ) internal view {
        (uint8 moduleId, uint64 noId) = op.unpackEntryTypeNOR();
        address module = STAKING_ROUTER
            .getStakingModule(moduleId)
            .stakingModuleAddress;
        _onlyExistingOperator(module, noId);
    }

    function _onlyExistingOperator(
        address module,
        uint256 nodeOperatorId
    ) internal view {
        if (!_nodeOperatorExists(module, nodeOperatorId)) {
            revert NodeOperatorDoesNotExist();
        }
    }

    function _nodeOperatorExists(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (bool) {
        return nodeOperatorId < IStakingModule(module).getNodeOperatorsCount();
    }

    function _nodeOperatorOwner(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (address) {
        return IBaseModule(module).getNodeOperatorOwner(nodeOperatorId);
    }

    function _totalExternalStake(
        ExternalOperator[] storage externalOperators
    ) internal view returns (uint256 totalExternalStake) {
        for (uint256 i; i < externalOperators.length; ++i) {
            ExternalOperator memory op = externalOperators[i];

            OperatorType opType = op.tryGetOpType();
            if (opType == OperatorType.NOR) {
                totalExternalStake += _getOperatorExternalStakeTypeNOR(op);
            }
        }
    }

    function _getOperatorExternalStakeTypeNOR(
        ExternalOperator memory op
    ) internal view returns (uint256 stake) {
        (uint8 moduleId, uint64 noId) = op.unpackEntryTypeNOR();

        address module = STAKING_ROUTER
            .getStakingModule(moduleId)
            .stakingModuleAddress;

        (
            ,
            ,
            ,
            ,
            uint64 totalExitedValidators,
            ,
            uint64 totalDepositedValidators
        ) = INodeOperatorsRegistry(module).getNodeOperator(noId, false);

        uint256 activeValidators = totalDepositedValidators -
            totalExitedValidators;
        if (activeValidators == 0) return stake;
        stake = activeValidators * EXTERNAL_STAKE_PER_VALIDATOR;
    }

    function _storage() internal pure returns (MetaRegistryStorage storage $) {
        assembly ("memory-safe") {
            $.slot := META_REGISTRY_STORAGE_LOCATION
        }
    }
}
