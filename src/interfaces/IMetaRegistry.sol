// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";

/// @notice Stored operator metadata.
struct OperatorMetadata {
    string name;
    string description;
    bool ownerEditsRestricted;
}

/// @notice Meta registry for curated node operator groups.
interface IMetaRegistry {
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

    event OperatorGroupCreated(uint256 indexed groupId, OperatorGroup groupInfo);
    event OperatorGroupUpdated(uint256 indexed groupId, OperatorGroup groupInfo);
    event OperatorGroupCleared(uint256 indexed groupId);
    event BondCurveWeightSet(uint256 indexed curveId, uint256 weight);
    event OperatorMetadataSet(uint256 indexed nodeOperatorId, OperatorMetadata metadata);
    event NodeOperatorEffectiveWeightChanged(uint256 indexed nodeOperatorId, uint256 oldWeight, uint256 newWeight);

    error ZeroModuleAddress();
    error ZeroAccountingAddress();
    error ZeroAdminAddress();
    error ZeroStakingRouterAddress();
    error InvalidOperatorGroup();
    error InvalidSubNodeOperatorShares();
    error InvalidOperatorGroupId();
    error NodeOperatorDoesNotExist();
    error NodeOperatorAlreadyInGroup(uint256 nodeOperatorId);
    error AlreadyUsedAsExternalOperator();
    error NodeOperatorNotInGroup();
    error SenderIsNotModule();
    error SenderIsNotEligible();
    error OwnerEditsRestricted();
    error UnsupportedExternalOperatorType();
    error SameBondCurveWeight();
    error ModuleAddressNotCached();
    error OperatorNameTooLong();
    error OperatorDescriptionTooLong();

    /// @notice Role allowed to manage operator groups.
    function MANAGE_OPERATOR_GROUPS_ROLE() external view returns (bytes32);

    /// @notice Sentinel value representing no operator group.
    function NO_GROUP_ID() external view returns (uint256);

    /// @notice Role allowed to set operator metadata.
    function SET_OPERATOR_INFO_ROLE() external view returns (bytes32);

    /// @notice Role allowed to set bond curve weights.
    function SET_BOND_CURVE_WEIGHT_ROLE() external view returns (bytes32);

    /// @notice Curated module allowed to call module-only hooks.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract used for bond curve lookups.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Initialize the registry.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address admin) external;

    /// @notice Set or update metadata for a node operator (callable by SET_OPERATOR_INFO_ROLE).
    /// @param nodeOperatorId Node operator ID.
    /// @param metadata Metadata payload to persist.
    function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external;

    /// @notice Set or update metadata by the node operator owner.
    /// @param nodeOperatorId Node operator ID.
    /// @param name Display name.
    /// @param description Long description.
    /// @dev Reverts if module does not support IBaseModule interface.
    function setOperatorMetadataAsOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Get metadata for a node operator.
    /// @param nodeOperatorId Node operator ID.
    /// @return metadata Stored metadata struct.
    function getOperatorMetadata(uint256 nodeOperatorId) external view returns (OperatorMetadata memory metadata);

    /// @notice Create a new operator group or update an existing one.
    /// @param groupId Group ID to update, or NO_GROUP_ID to create.
    /// @param groupInfo Group definition.
    /// @dev Creating is allowed only when groupId == NO_GROUP_ID.
    function createOrUpdateOperatorGroup(uint256 groupId, OperatorGroup calldata groupInfo) external;

    /// @notice Fetch an operator group by ID.
    /// @param groupId Group ID to fetch.
    /// @return groupInfo Group definition.
    function getOperatorGroup(uint256 groupId) external view returns (OperatorGroup memory groupInfo);

    /// @notice Returns total operator groups count.
    function getOperatorGroupsCount() external view returns (uint256 count);

    /// @notice Get Node Operator group ID (returns NO_GROUP_ID if the operator is not in any group).
    /// @param nodeOperatorId Node operator ID to query.
    /// @return operatorGroupId Group ID.
    function getNodeOperatorGroupId(uint256 nodeOperatorId) external view returns (uint256 operatorGroupId);

    /// @notice Get External Operator group ID (returns NO_GROUP_ID if the operator is not in any group).
    /// @param op External operator.
    /// @return operatorGroupId Group ID.
    function getExternalOperatorGroupId(ExternalOperator calldata op) external view returns (uint256 operatorGroupId);

    /// @notice Returns base weight for the bond curve ID.
    /// @param curveId Bond curve ID.
    /// @return weight Base allocation weight.
    function getBondCurveWeight(uint256 curveId) external view returns (uint256 weight);

    /// @notice Set base weight for the bond curve ID (callable by SET_BOND_CURVE_WEIGHT_ROLE).
    /// @dev Effective weights for operators using the curve will not be updated automatically.
    ///      refreshOperatorWeight() must be called for the affected operators to update their effective weights.
    /// @param curveId Bond curve ID.
    /// @param weight Base allocation weight.
    function setBondCurveWeight(uint256 curveId, uint256 weight) external;

    /// @notice Returns effective weight for the node operator.
    /// @param nodeOperatorId Node operator ID to query.
    /// @return weight Effective allocation weight.
    /// @dev Returns the cached effective weight.
    /// @dev Operators outside any group are expected to have zero cached weight.
    function getNodeOperatorWeight(uint256 nodeOperatorId) external view returns (uint256 weight);

    /// @notice Returns effective weight and external stake for the node operator.
    /// @param nodeOperatorId Node operator ID to query.
    /// @return weight Effective allocation weight.
    /// @return externalStake External stake amount in wei.
    /// @dev Returns (0, 0) if the operator is not in a group.
    /// @dev During partial deposit info refreshes, cached weights may be updated only for a subset
    ///      of operators, so direct reads can transiently reflect mixed-state group totals.
    ///      Integrations that require a fully refreshed view should prefer the curated module getter.
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake);

    /// @notice Returns allocation weights for the given node operators.
    /// @param nodeOperatorIds Node operator IDs to query.
    /// @return operatorWeights Weights aligned with nodeOperatorIds.
    function getOperatorWeights(
        uint256[] calldata nodeOperatorIds
    ) external view returns (uint256[] memory operatorWeights);

    /// @notice Trigger the operator weight update routine in the registry.
    /// @param nodeOperatorId Node operator ID to trigger the update for.
    function refreshOperatorWeight(uint256 nodeOperatorId) external;
}
