// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

/// @notice Stores Node Operator metadata
struct OperatorInfo {
    string name;
    string description;
    bool ownerEditsRestricted;
}

/// @title Operators Data Interface
interface IOperatorsData {
    /// @notice Emitted when metadata is set for a Node Operator
    /// @param nodeOperatorId Id of the Node Operator
    /// @param name Display name
    /// @param description Long description
    /// @param ownerEditsRestricted Whether owner updates are restricted
    event OperatorDataSet(
        uint256 indexed moduleId,
        address module,
        uint256 indexed nodeOperatorId,
        string name,
        string description,
        bool ownerEditsRestricted
    );

    /// @notice Emitted when a module address is cached
    /// @param moduleId Module id
    /// @param moduleAddress Module address
    event ModuleAddressCached(uint256 indexed moduleId, address moduleAddress);

    error ZeroAdminAddress();
    error ZeroModuleId();
    error ZeroStakingRouterAddress();
    error NodeOperatorDoesNotExist();
    error SenderIsNotEligible();
    error OwnerEditsRestricted();
    error UnknownModule();
    error ModuleDoesNotSupportNodeOperatorOwnerInterface();

    /// @return Role id allowed to set metadata
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Set or update metadata for a Node Operator (callable by SETTER_ROLE)
    /// @param moduleId Module id
    /// @param nodeOperatorId Node Operator id
    /// @param info Metadata payload to persist
    function set(
        uint256 moduleId,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external;

    /// @notice Set or update metadata by the Node Operator owner
    /// @param moduleId Module id
    /// @param nodeOperatorId Node Operator id
    /// @param name Display name
    /// @param description Long description
    /// @dev Reverts if module does not support INodeOperatorOwner interface
    function setByOwner(
        uint256 moduleId,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Get metadata for a Node Operator
    /// @param moduleId Module id
    /// @param nodeOperatorId Node Operator id
    /// @return info Stored metadata struct
    function get(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info);

    /// @notice Check if owner metadata updates are restricted
    /// @param moduleId Module id
    /// @param nodeOperatorId Node Operator id
    function isOwnerEditsRestricted(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (bool);
}
