// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";

// TODO: Unify MarkedUint248 definition across interfaces.
struct MarkedUint248 {
    uint248 value;
    bool isValue;
}

/// @notice Stored operator metadata.
struct OperatorInfo {
    string name;
    string description;
    bool ownerEditsRestricted;
}

/// @notice Meta registry for curated node operator groups.
interface IMetaOperatorRegistry {
    struct SubNodeOperator {
        uint64 nodeOperatorId;
        uint16 share;
    }

    struct ExternalOperator {
        bytes data;
    }

    struct OperatorGroup {
        SubNodeOperator[] subNodeOperators;
        ExternalOperator[] externalOperators;
    }

    event OperatorGroupCreated(uint256 indexed groupId);
    event OperatorGroupUpdated(uint256 indexed groupId);
    event BondCurveWeightSet(uint256 indexed curveId, uint256 weight);
    event OperatorDataSet(
        uint256 indexed moduleId,
        uint256 indexed nodeOperatorId,
        string name,
        string description,
        bool ownerEditsRestricted
    );
    event NodeOperatorEffectiveWeightChanged(
        uint256 indexed nodeOperatorId,
        uint256 oldWeight,
        uint256 newWeight
    );

    error ZeroModuleAddress();
    error ZeroAccountingAddress();
    error ZeroAdminAddress();
    error ZeroStakingRouterAddress();
    error InvalidOperatorGroup();
    error InvalidSubNodeOperatorShares();
    error InvalidOperatorGroupId();
    error NodeOperatorDoesNotExist();
    error NodeOperatorAlreadyInGroup();
    error NodeOperatorNotInGroup();
    error SenderIsNotModule();
    error SenderIsNotEligible();
    error OwnerEditsRestricted();
    error UnsupportedExternalOperatorType();
    error UnknownModule();
    error InvariantFailed();

    /// @notice Role allowed to manage operator groups.
    function CMC_ROLE() external view returns (bytes32);

    /// @notice Role allowed to set operator metadata.
    function SET_OPERATOR_INFO_ROLE() external view returns (bytes32);

    /// @notice Curated module allowed to call module-only hooks.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract used for bond curve lookups.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Initialize the registry.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address admin) external;

    /// @notice Set or update metadata for a node operator (callable by SET_OPERATOR_INFO_ROLE).
    /// @param moduleId Module id.
    /// @param nodeOperatorId Node operator id.
    /// @param info Metadata payload to persist.
    function setOperatorMetadataAsAdmin(
        uint256 moduleId,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external;

    /// @notice Set or update metadata by the node operator owner.
    /// @param moduleId Module id.
    /// @param nodeOperatorId Node operator id.
    /// @param name Display name.
    /// @param description Long description.
    /// @dev Reverts if module does not support IBaseModule interface.
    function setOperatorMetadataAsOwner(
        uint256 moduleId,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Get metadata for a node operator.
    /// @param moduleId Module id.
    /// @param nodeOperatorId Node operator id.
    /// @return info Stored metadata struct.
    function getOperatorMetadata(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info);

    /// @notice Create a new operator group or update an existing one.
    /// @param groupId Group id to create or update.
    /// @param groupInfo Group definition.
    /// @dev Creating is allowed only when groupId == getOperatorGroupsCount().
    function createOrUpdateOperatorGroup(
        uint256 groupId,
        OperatorGroup calldata groupInfo
    ) external;

    /// @notice Fetch an operator group by id.
    /// @param groupId Group id to fetch.
    /// @return groupInfo Group definition.
    function getOperatorGroup(
        uint256 groupId
    ) external view returns (OperatorGroup memory groupInfo);

    /// @notice Returns total operator groups count.
    function getOperatorGroupsCount() external view returns (uint256 count);

    /// @notice Check whether a node operator is in a group.
    /// @param nodeOperatorId Node operator id to query.
    /// @return isInGroup Whether the operator is in a group.
    /// @return operatorGroupId Group id when present.
    function getNodeOperatorGroupMembership(
        uint256 nodeOperatorId
    ) external view returns (bool isInGroup, uint256 operatorGroupId);

    /// @notice Check whether an external operator is in a group.
    /// @param data External operator data.
    /// @return isInGroup Whether the external operator is in a group.
    /// @return operatorGroupId Group id when present.
    function getExternalOperatorGroupMembership(
        bytes calldata data
    ) external view returns (bool isInGroup, uint256 operatorGroupId);

    /// @notice Returns base weight for the bond curve id.
    /// @param curveId Bond curve id.
    /// @return weight Base allocation weight.
    function getBondCurveWeight(
        uint256 curveId
    ) external view returns (uint256 weight);

    /// @notice Set base weight for the bond curve id.
    /// @param curveId Bond curve id.
    /// @param weight Base allocation weight.
    function setBondCurveWeight(uint256 curveId, uint256 weight) external;

    /// @notice Returns effective weight and external stake for the node operator.
    /// @param nodeOperatorId Node operator id to query.
    /// @return weight Effective allocation weight.
    /// @return externalStake External stake amount in wei.
    /// @dev Returns (0, 0) if the operator is not in a group.
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake);

    /// @notice Notify the registry about a node operator weight update.
    /// @param nodeOperatorId Node operator id that triggered the update.
    /// @return changed Whether any affected operator weight changed.
    function onNodeOperatorWeightUpdated(
        uint256 nodeOperatorId
    ) external returns (bool changed);
}
