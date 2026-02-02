// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { INodeOperatorRegistry } from "./interfaces/INodeOperatorRegistry.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { IStakingRouter } from "./interfaces/IStakingRouter.sol";
import { IMetaOperatorRegistry, MarkedUint248, OperatorInfo } from "./interfaces/IMetaOperatorRegistry.sol";
import { ExternalOperatorLib } from "./lib/ExternalOperatorLib.sol";

/// @notice Stores meta-operator group definitions for the curated module.
contract MetaOperatorRegistry is
    IMetaOperatorRegistry,
    Initializable,
    AccessControlEnumerableUpgradeable
{
    using SafeCast for uint256;

    struct GroupIndex {
        mapping(uint256 nodeOperatorId => MarkedUint248) groupIdByOperatorId;
        mapping(uint256 nodeOperatorId => MarkedUint248) operatorShareById;
        mapping(bytes32 externalKey => MarkedUint248) groupIdByExternalKey;
    }

    struct CachedOperatorGroup {
        uint64[] subNodeOperatorIds;
        ExternalOperator[] externalOperators;
    }

    struct WeightCache {
        mapping(uint256 nodeOperatorId => uint256 weight) operatorEffectiveWeight;
        mapping(uint256 groupId => uint256 weight) groupEffectiveWeightSum;
    }

    bytes32 public constant MANAGE_OPERATOR_GROUPS_ROLE =
        keccak256("MANAGE_OPERATOR_GROUPS_ROLE");
    bytes32 public constant SET_OPERATOR_INFO_ROLE =
        keccak256("SET_OPERATOR_INFO_ROLE");

    uint256 public constant CREATE_GROUP_SENTINEL = type(uint256).max;

    ICuratedModule public immutable MODULE;
    IAccounting public immutable ACCOUNTING;
    IStakingRouter public immutable STAKING_ROUTER;

    uint256 internal constant MAX_BP = 10000;
    uint256 internal constant EXTERNAL_STAKE_PER_VALIDATOR = 32 ether;

    mapping(uint256 curveId => uint256 weight) internal _bondCurveWeight;
    CachedOperatorGroup[] internal _groups;
    GroupIndex internal _groupIndex;

    WeightCache internal _weightCache;

    mapping(bytes32 key => OperatorInfo) internal _operatorMetadata;
    mapping(uint256 moduleId => address moduleAddress) internal _modules;

    modifier onlyExistingGroup(uint256 groupId) {
        if (groupId >= _groups.length) {
            revert InvalidOperatorGroupId();
        }
        _;
    }

    constructor(address module, address stakingRouter) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }

        if (stakingRouter == address(0)) {
            revert ZeroStakingRouterAddress();
        }

        MODULE = ICuratedModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());
        STAKING_ROUTER = IStakingRouter(payable(stakingRouter));

        _disableInitializers();
    }

    /// @inheritdoc IMetaOperatorRegistry
    function initialize(address admin) external initializer {
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IMetaOperatorRegistry
    function setOperatorMetadataAsAdmin(
        uint256 moduleId,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external onlyRole(SET_OPERATOR_INFO_ROLE) {
        address module = _resolveModuleAddress(moduleId);
        if (!_nodeOperatorExists(module, nodeOperatorId)) {
            revert NodeOperatorDoesNotExist();
        }

        OperatorInfo storage stored = _operatorMetadata[
            _metadataKey(moduleId, nodeOperatorId)
        ];
        stored.name = info.name;
        stored.description = info.description;
        stored.ownerEditsRestricted = info.ownerEditsRestricted;

        emit OperatorDataSet({
            moduleId: moduleId,
            nodeOperatorId: nodeOperatorId,
            name: info.name,
            description: info.description,
            ownerEditsRestricted: info.ownerEditsRestricted
        });
    }

    /// @inheritdoc IMetaOperatorRegistry
    function setOperatorMetadataAsOwner(
        uint256 moduleId,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        address module = _resolveModuleAddress(moduleId);
        address owner = _nodeOperatorOwner(module, nodeOperatorId);
        if (owner == address(0)) {
            revert NodeOperatorDoesNotExist();
        }
        if (owner != msg.sender) {
            revert SenderIsNotEligible();
        }

        OperatorInfo storage stored = _operatorMetadata[
            _metadataKey(moduleId, nodeOperatorId)
        ];
        bool ownerEditsRestricted = stored.ownerEditsRestricted;
        if (ownerEditsRestricted) {
            revert OwnerEditsRestricted();
        }

        stored.name = name;
        stored.description = description;

        emit OperatorDataSet({
            moduleId: moduleId,
            nodeOperatorId: nodeOperatorId,
            name: name,
            description: description,
            ownerEditsRestricted: ownerEditsRestricted
        });
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getOperatorMetadata(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        return _operatorMetadata[_metadataKey(moduleId, nodeOperatorId)];
    }

    /// @inheritdoc IMetaOperatorRegistry
    function createOrUpdateOperatorGroup(
        uint256 groupId,
        OperatorGroup calldata groupInfo
    ) external onlyRole(MANAGE_OPERATOR_GROUPS_ROLE) {
        if (groupId == CREATE_GROUP_SENTINEL) {
            uint256 newGroupId = _groups.length;
            _groups.push();
            _storeGroup(newGroupId.toUint248(), groupInfo, false);
            emit OperatorGroupCreated(newGroupId);
            return;
        }

        if (groupId >= _groups.length) {
            revert InvalidOperatorGroupId();
        }

        _clearGroupMembership(groupId);
        _storeGroup(groupId.toUint248(), groupInfo, true);
        emit OperatorGroupUpdated(groupId);
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getOperatorGroup(
        uint256 groupId
    )
        external
        view
        onlyExistingGroup(groupId)
        returns (OperatorGroup memory groupInfo)
    {
        CachedOperatorGroup storage group = _groups[groupId];
        uint256 subOpCount = group.subNodeOperatorIds.length;
        groupInfo.subNodeOperators = new SubNodeOperator[](subOpCount);
        for (uint256 i; i < subOpCount; ++i) {
            uint64 noId = group.subNodeOperatorIds[i];
            MarkedUint248 memory shareData = _groupIndex.operatorShareById[
                noId
            ];
            groupInfo.subNodeOperators[i] = SubNodeOperator({
                nodeOperatorId: noId,
                share: uint16(shareData.value)
            });
        }
        groupInfo.externalOperators = group.externalOperators;
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getOperatorGroupsCount() external view returns (uint256 count) {
        return _groups.length;
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getNodeOperatorGroupMembership(
        uint256 nodeOperatorId
    ) external view returns (bool isInGroup, uint256 operatorGroupId) {
        MarkedUint248 memory groupData = _groupIndex.groupIdByOperatorId[
            nodeOperatorId
        ];
        if (!groupData.isValue) {
            return (false, 0);
        }
        return (true, groupData.value);
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getExternalOperatorGroupMembership(
        bytes calldata data
    ) external view returns (bool isInGroup, uint256 operatorGroupId) {
        bytes32 externalKey = ExternalOperatorLib.uniqueKey(data);
        MarkedUint248 memory groupData = _groupIndex.groupIdByExternalKey[
            externalKey
        ];
        if (!groupData.isValue) {
            return (false, 0);
        }
        return (true, groupData.value);
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getBondCurveWeight(
        uint256 curveId
    ) external view returns (uint256 weight) {
        return _bondCurveWeight[curveId];
    }

    /// @inheritdoc IMetaOperatorRegistry
    function setBondCurveWeight(
        uint256 curveId,
        uint256 weight
    ) external onlyRole(MANAGE_OPERATOR_GROUPS_ROLE) {
        if (_bondCurveWeight[curveId] == weight) {
            return;
        }

        _bondCurveWeight[curveId] = weight;
        emit BondCurveWeightSet(curveId, weight);

        MODULE.onBondCurveWeightUpdated();
    }

    /// @inheritdoc IMetaOperatorRegistry
    function getNodeOperatorWeightAndExternalStake(
        uint256 noId
    ) external view returns (uint256 weight, uint256 externalStake) {
        MarkedUint248 memory groupData = _groupIndex.groupIdByOperatorId[noId];
        if (!groupData.isValue) {
            return (0, 0);
        }

        uint256 groupId = groupData.value;

        weight = _weightCache.operatorEffectiveWeight[noId];
        if (weight == 0) {
            return (0, 0);
        }

        uint256 totalExternalStake = _totalExternalStake(_groups[groupId]);
        if (totalExternalStake == 0) {
            return (weight, 0);
        }

        uint256 groupTotalWeight = _weightCache.groupEffectiveWeightSum[
            groupId
        ];
        if (groupTotalWeight == 0) {
            revert InvariantFailed();
        }
        externalStake = Math.mulDiv(
            totalExternalStake,
            weight,
            groupTotalWeight
        );
    }

    /// @inheritdoc IMetaOperatorRegistry
    function onNodeOperatorWeightUpdated(
        uint256 nodeOperatorId
    ) external returns (bool changed) {
        uint256 groupId = _requireOperatorInGroup(nodeOperatorId);
        return _refreshOperatorWeight(groupId, nodeOperatorId);
    }

    function _storeGroup(
        uint248 groupId,
        OperatorGroup calldata groupInfo,
        bool allowEmpty
    ) internal {
        CachedOperatorGroup storage group = _groups[groupId];
        delete group.subNodeOperatorIds;
        delete group.externalOperators;

        if (groupInfo.subNodeOperators.length == 0) {
            if (!allowEmpty || groupInfo.externalOperators.length != 0) {
                revert InvalidOperatorGroup();
            }

            _weightCache.groupEffectiveWeightSum[groupId] = 0;
            return;
        }

        uint256 effectiveWeightSum = _storeSubOperators(
            group,
            groupId,
            groupInfo.subNodeOperators
        );
        _weightCache.groupEffectiveWeightSum[groupId] = effectiveWeightSum;

        _storeExternalOperators(group, groupId, groupInfo.externalOperators);
    }

    function _storeSubOperators(
        CachedOperatorGroup storage group,
        uint248 groupId,
        SubNodeOperator[] calldata subNodeOperators
    ) internal returns (uint256 effectiveWeightSum) {
        uint256 shareSum;
        uint256 subOpCount = subNodeOperators.length;
        for (uint256 i; i < subOpCount; ++i) {
            SubNodeOperator memory subOperator = subNodeOperators[i];
            uint64 noId = subOperator.nodeOperatorId;
            uint16 share = subOperator.share;

            if (!_nodeOperatorExists(address(MODULE), noId)) {
                revert NodeOperatorDoesNotExist();
            }

            MarkedUint248 memory groupData = _groupIndex.groupIdByOperatorId[
                noId
            ];
            if (groupData.isValue) {
                revert NodeOperatorAlreadyInGroup();
            }

            _groupIndex.groupIdByOperatorId[noId] = MarkedUint248(
                groupId,
                true
            );
            _groupIndex.operatorShareById[noId] = MarkedUint248(
                uint256(share).toUint248(),
                true
            );
            group.subNodeOperatorIds.push(noId);

            uint256 effectiveWeight = _getEffectiveWeight(noId, share);
            _setEffectiveWeight(noId, effectiveWeight);
            effectiveWeightSum += effectiveWeight;
            shareSum += share;
        }

        if (shareSum != MAX_BP) revert InvalidSubNodeOperatorShares();
    }

    function _storeExternalOperators(
        CachedOperatorGroup storage group,
        uint248 groupId,
        ExternalOperator[] calldata externalOperators
    ) internal {
        uint256 extOpCount = externalOperators.length;
        for (uint256 i; i < extOpCount; ++i) {
            ExternalOperator calldata extOp = externalOperators[i];
            bytes32 extKey = ExternalOperatorLib.uniqueKey(extOp.data);
            MarkedUint248 memory groupData = _groupIndex.groupIdByExternalKey[
                extKey
            ];
            if (groupData.isValue) {
                revert AlreadyUsedAsExternalOperator();
            }

            if (!ExternalOperatorLib.isNOR(extOp.data)) {
                revert UnsupportedExternalOperatorType();
            }
            (uint8 moduleId, uint64 noId) = ExternalOperatorLib.unpackEntry(
                extOp.data
            );
            address module = _resolveModuleAddress(moduleId);
            if (!_nodeOperatorExists(module, noId)) {
                revert NodeOperatorDoesNotExist();
            }

            _groupIndex.groupIdByExternalKey[extKey] = MarkedUint248(
                groupId,
                true
            );
            group.externalOperators.push(extOp);
        }
    }

    function _clearGroupMembership(uint256 groupId) internal {
        CachedOperatorGroup storage group = _groups[groupId];

        uint256 subOperatorsCount = group.subNodeOperatorIds.length;
        for (uint256 i; i < subOperatorsCount; ++i) {
            uint256 nodeOperatorId = group.subNodeOperatorIds[i];
            delete _groupIndex.groupIdByOperatorId[nodeOperatorId];
            delete _groupIndex.operatorShareById[nodeOperatorId];
        }

        uint256 extOpCount = group.externalOperators.length;
        for (uint256 i; i < extOpCount; ++i) {
            ExternalOperator storage op = group.externalOperators[i];
            bytes32 externalKey = ExternalOperatorLib.uniqueKey(op.data);
            delete _groupIndex.groupIdByExternalKey[externalKey];
        }
    }

    /// @dev `noId` should be a part of group with `groupId`.
    function _refreshOperatorWeight(
        uint256 groupId,
        uint256 noId
    ) internal returns (bool changed) {
        MarkedUint248 memory shareData = _groupIndex.operatorShareById[noId];

        uint256 newWeight = _getEffectiveWeight(noId, shareData.value);
        uint256 oldWeight = _setEffectiveWeight(noId, newWeight);

        uint256 sum = _weightCache.groupEffectiveWeightSum[groupId];
        _weightCache.groupEffectiveWeightSum[groupId] =
            sum +
            newWeight -
            oldWeight;

        return true;
    }

    function _getEffectiveWeight(
        uint256 nodeOperatorId,
        uint256 share
    ) internal view returns (uint256) {
        uint256 curveId = ACCOUNTING.getBondCurveId(nodeOperatorId);
        uint256 baseWeight = _bondCurveWeight[curveId];
        if (baseWeight == 0 || share == 0) return 0;
        return Math.mulDiv(baseWeight, share, MAX_BP);
    }

    function _setEffectiveWeight(
        uint256 nodeOperatorId,
        uint256 newWeight
    ) internal returns (uint256 oldWeight) {
        oldWeight = _weightCache.operatorEffectiveWeight[nodeOperatorId];

        if (oldWeight == newWeight) {
            return oldWeight;
        }

        _weightCache.operatorEffectiveWeight[nodeOperatorId] = newWeight;
        emit NodeOperatorEffectiveWeightChanged(
            nodeOperatorId,
            oldWeight,
            newWeight
        );
    }

    function _requireOperatorInGroup(
        uint256 nodeOperatorId
    ) internal view returns (uint256 groupId) {
        MarkedUint248 memory groupData = _groupIndex.groupIdByOperatorId[
            nodeOperatorId
        ];
        if (!groupData.isValue) {
            revert NodeOperatorNotInGroup();
        }
        groupId = groupData.value;
    }

    function _metadataKey(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(moduleId, nodeOperatorId));
    }

    function _resolveModuleAddress(
        uint256 moduleId
    ) internal returns (address module) {
        module = _modules[moduleId];
        if (module == address(0)) {
            // NOTE: StakingRouter reverts with StakingModuleUnregistered if the module is not found.
            module = STAKING_ROUTER
                .getStakingModule(moduleId)
                .stakingModuleAddress;
            _modules[moduleId] = module;
        }
    }

    function _getModuleAddress(
        uint256 moduleId
    ) internal view returns (address module) {
        module = _modules[moduleId];
        if (module == address(0)) {
            module = STAKING_ROUTER
                .getStakingModule(moduleId)
                .stakingModuleAddress;
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
        CachedOperatorGroup storage group
    ) internal view returns (uint256 totalExternalStake) {
        uint256 opCount = group.externalOperators.length;
        if (opCount == 0) {
            return 0;
        }

        for (uint256 i; i < opCount; ++i) {
            bytes memory data = group.externalOperators[i].data;
            if (!ExternalOperatorLib.isNOR(data)) {
                revert UnsupportedExternalOperatorType();
            }

            (uint8 moduleId, uint64 noId) = ExternalOperatorLib.unpackEntry(
                data
            );
            address module = _getModuleAddress(moduleId);

            (
                ,
                ,
                ,
                ,
                uint64 totalExitedValidators,
                ,
                uint64 totalDepositedValidators
            ) = INodeOperatorRegistry(module).getNodeOperator(noId, false);

            uint256 activeValidators = totalDepositedValidators -
                totalExitedValidators;
            if (activeValidators == 0) continue;
            totalExternalStake +=
                activeValidators *
                EXTERNAL_STAKE_PER_VALIDATOR;
        }
    }
}
