// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./IAccounting.sol";
import { ICuratedModule } from "./ICuratedModule.sol";
import { IWeightBoostProvider } from "./IWeightBoostProvider.sol";

/// @notice Stored operator metadata.
struct OperatorMetadata {
    string name;
    string description;
    bool ownerEditsRestricted;
}

/// @notice Meta registry for curated Node Operator groups.
interface IMetaRegistry {
    struct SubNodeOperator {
        uint64 nodeOperatorId;
        uint16 share;
    }

    struct ExternalOperator {
        bytes data;
    }

    struct OperatorGroup {
        string name;
        SubNodeOperator[] subNodeOperators;
        ExternalOperator[] externalOperators;
    }

    /// @dev `PerNodeOperator` applies the provider multiplier directly to each Node Operator.
    ///      `MaxPerGroup` applies the max provider multiplier among group sub-operators to the whole group.
    enum WeightBoostProviderMode {
        PerNodeOperator,
        MaxPerGroup
    }

    struct WeightBoostProviderEntry {
        IWeightBoostProvider provider;
        WeightBoostProviderMode mode;
    }

    event OperatorGroupCreated(uint256 indexed groupId, OperatorGroup groupInfo);
    event OperatorGroupUpdated(uint256 indexed groupId, OperatorGroup groupInfo);
    event OperatorGroupCleared(uint256 indexed groupId);
    event BondCurveWeightSet(uint256 indexed curveId, uint256 weight);
    event WeightBoostProviderAdded(address indexed provider, WeightBoostProviderMode mode);
    event WeightBoostProviderRemoved(address indexed provider);
    event WeightBoostProviderConfigChanged(address indexed provider);
    event GroupWeightsRefreshed(uint256 indexed groupId);
    event OperatorMetadataSet(uint256 indexed nodeOperatorId, OperatorMetadata metadata);
    event NodeOperatorEffectiveWeightChanged(uint256 indexed nodeOperatorId, uint256 oldWeight, uint256 newWeight);

    error ZeroModuleAddress();
    error ZeroAdminAddress();
    error InvalidOperatorGroup();
    error InvalidSubNodeOperatorShares();
    error InvalidOperatorGroupId();
    error InvalidOperatorGroupName();
    error NodeOperatorDoesNotExist();
    error NodeOperatorAlreadyInGroup(uint256 nodeOperatorId);
    error AlreadyUsedAsExternalOperator();
    error SenderIsNotEligible();
    error OwnerEditsRestricted();
    error SameBondCurveWeight();
    error InvalidBondCurveWeight();
    error InvalidWeightBoostProvider();
    error WeightBoostProviderAlreadyAdded();
    error TooManyWeightBoostProviders();
    error WeightBoostProviderNotFound();
    error ModuleAddressNotCached();
    error OperatorNameTooLong();
    error OperatorDescriptionTooLong();

    /// @notice Role allowed to manage operator groups.
    function MANAGE_OPERATOR_GROUPS_ROLE() external view returns (bytes32);

    /// @notice Sentinel value representing no operator group.
    function NO_GROUP_ID() external view returns (uint256);

    /// @notice Maximum number of weight boost providers that can be registered.
    function MAX_WEIGHT_BOOST_PROVIDERS() external view returns (uint256);

    /// @notice Maximum bond curve base weight, in BP.
    function MAX_BOND_CURVE_WEIGHT() external view returns (uint256);

    /// @notice Role allowed to set operator metadata.
    function SET_OPERATOR_INFO_ROLE() external view returns (bytes32);

    /// @notice Role allowed to set bond curve weights.
    function SET_BOND_CURVE_WEIGHT_ROLE() external view returns (bytes32);

    /// @notice Curated module the registry serves: weight changes and deposit info update requests are
    ///         pushed to it, and it is the source of operator existence and ownership.
    function MODULE() external view returns (ICuratedModule);

    /// @notice Accounting contract used for bond curve lookups.
    function ACCOUNTING() external view returns (IAccounting);

    /// @notice Returns configured weight boost provider entries (provider and mode).
    /// @return providers Configured boost provider entries.
    function getWeightBoostProviders() external view returns (WeightBoostProviderEntry[] memory providers);

    /// @notice Initialize the registry.
    /// @param admin Address to receive DEFAULT_ADMIN_ROLE.
    function initialize(address admin) external;

    /// @notice Returns the initialized version of the contract.
    function getInitializedVersion() external view returns (uint64);

    /// @notice Set or update metadata for a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param metadata Metadata payload to persist.
    function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external;

    /// @notice Set or update metadata by the Node Operator owner.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @param name Display name.
    /// @param description Long description.
    function setOperatorMetadataAsOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Returns metadata of a Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return metadata Stored metadata struct.
    function getOperatorMetadata(uint256 nodeOperatorId) external view returns (OperatorMetadata memory metadata);

    /// @notice Create a new operator group or update an existing one.
    /// @param groupId Group ID to update, or NO_GROUP_ID to create.
    /// @param groupInfo Group definition.
    /// @dev Creating is allowed only when groupId == NO_GROUP_ID.
    /// @dev To clear a group pass empty subNodeOperators, empty externalOperators, and empty name.
    function createOrUpdateOperatorGroup(uint256 groupId, OperatorGroup calldata groupInfo) external;

    /// @notice Fetch an operator group by ID.
    /// @param groupId Group ID to fetch.
    /// @return groupInfo Group definition.
    function getOperatorGroup(uint256 groupId) external view returns (OperatorGroup memory groupInfo);

    /// @notice Returns total operator groups count.
    function getOperatorGroupsCount() external view returns (uint256 count);

    /// @notice Returns the Node Operator group ID ( NO_GROUP_ID if the operator is not in any group).
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return operatorGroupId Group ID.
    function getNodeOperatorGroupId(uint256 nodeOperatorId) external view returns (uint256 operatorGroupId);

    /// @notice Returns the External Operator group ID ( NO_GROUP_ID if the operator is not in any group).
    /// @param op External operator.
    /// @return operatorGroupId Group ID.
    function getExternalOperatorGroupId(ExternalOperator calldata op) external view returns (uint256 operatorGroupId);

    /// @notice Returns base weight for the bond curve ID.
    /// @param curveId Bond curve ID.
    /// @return weight Base allocation weight.
    function getBondCurveWeight(uint256 curveId) external view returns (uint256 weight);

    /// @notice Set base weight for the bond curve ID.
    /// @dev Requests a full deposit info update that refreshes cached weights. Deposits are blocked until it completes.
    /// @param curveId Bond curve ID.
    /// @param weight Base allocation weight.
    function setBondCurveWeight(uint256 curveId, uint256 weight) external;

    /// @notice Add a weight boost provider.
    /// @dev Requests a full deposit info update that refreshes cached weights. Deposits are blocked until it completes.
    /// @param provider Boost provider consumed during weight calculation.
    /// @param mode Provider aggregation mode.
    function addWeightBoostProvider(address provider, WeightBoostProviderMode mode) external;

    /// @notice Remove a weight boost provider.
    /// @dev Requests a full deposit info update that refreshes cached weights. Deposits are blocked until it completes.
    /// @param provider Boost provider to remove.
    function removeWeightBoostProvider(address provider) external;

    /// @notice Returns effective weight for the Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return weight Effective allocation weight.
    /// @dev Returns the cached effective weight.
    /// @dev Operators outside any group are expected to have zero cached weight.
    function getNodeOperatorWeight(uint256 nodeOperatorId) external view returns (uint256 weight);

    /// @notice Returns effective weight and external stake for the Node Operator.
    /// @param nodeOperatorId ID of the Node Operator.
    /// @return weight Effective allocation weight.
    /// @return externalStake External stake amount in wei.
    /// @dev Returns (0, 0) if the operator is not in a group.
    /// @dev During partial deposit info refreshes, cached weights may be updated only for a subset
    ///      of operators, so direct reads can transiently reflect mixed-state group totals.
    ///      Integrations that require a fully refreshed view should prefer the curated module getter.
    function getNodeOperatorWeightAndExternalStake(
        uint256 nodeOperatorId
    ) external view returns (uint256 weight, uint256 externalStake);

    /// @notice Returns allocation weights for the given Node Operators.
    /// @param nodeOperatorIds IDs of the Node Operators.
    /// @return operatorWeights Weights aligned with nodeOperatorIds.
    function getOperatorWeights(
        uint256[] calldata nodeOperatorIds
    ) external view returns (uint256[] memory operatorWeights);

    /// @notice Trigger the operator weight update routine in the registry.
    /// @dev No-op for operators outside any group.
    /// @param nodeOperatorId ID of the Node Operator to trigger the update for.
    function refreshOperatorWeight(uint256 nodeOperatorId) external;

    /// @notice Trigger the group weight update routine in the registry.
    /// @param groupId Operator group ID to trigger the update for.
    function refreshGroupWeights(uint256 groupId) external;

    /// @notice Notify the registry that a configured provider changed a Node Operator boost.
    /// @dev No-op for callers that are not registered providers and for
    ///      operators outside any group. A `PerNodeOperator` provider refreshes only the operator's
    ///      cached weight; a `MaxPerGroup` provider refreshes the whole group.
    /// @param nodeOperatorId ID of the Node Operator whose provider boost changed.
    function notifyWeightBoostChanged(uint256 nodeOperatorId) external;

    /// @notice Notify the registry that a configured provider changed global boost parameters.
    /// @dev Requests a full deposit info update when the sender is a registered provider; no-op otherwise.
    function notifyWeightBoostProviderConfigChanged() external;
}
