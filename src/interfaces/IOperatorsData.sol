// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

/// @notice Stores Node Operator metadata
struct OperatorInfo {
    string name;
    string description;
    bool ownerRestricted;
}

/// @title Operators Data Interface
interface IOperatorsData {
    /// @notice Emitted when metadata is set for a Node Operator
    /// @param nodeOperatorId Id of the Node Operator
    /// @param name Display name
    /// @param description Long description
    /// @param ownerRestricted Whether owner updates are restricted
    event OperatorDataSet(
        address indexed module,
        uint256 indexed nodeOperatorId,
        string name,
        string description,
        bool ownerRestricted
    );

    error ZeroAdminAddress();
    error ZeroModuleAddress();
    error ZeroStakingRouterAddress();
    error NodeOperatorDoesNotExist();
    error NotOwner();
    error OwnerEditsRestricted();
    error UnknownModule();

    /// @return Role id allowed to set metadata
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Set or update metadata for a Node Operator (callable by SETTER_ROLE)
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    /// @param info Metadata payload to persist
    function set(
        address module,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external;

    /// @notice Set or update metadata by the Node Operator owner
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    /// @param name Display name
    /// @param description Long description
    function setByOwner(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Get metadata for a Node Operator
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    /// @return info Stored metadata struct
    function get(
        address module,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info);

    /// @notice Check if owner metadata updates are restricted
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    function isOwnerRestricted(
        address module,
        uint256 nodeOperatorId
    ) external view returns (bool);
}
