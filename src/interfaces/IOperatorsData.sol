// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

/// @title Operators Data Interface
/// @notice Stores Node Operator name and description metadata
struct OperatorInfo {
    string name;
    string description;
}

interface IOperatorsData {
    /// @notice Emitted when metadata is set for a Node Operator
    /// @param nodeOperatorId Id of the Node Operator
    /// @param name Display name
    /// @param description Long description
    event OperatorDataSet(
        address indexed module,
        uint256 indexed nodeOperatorId,
        string name,
        string description
    );

    event OwnerRestrictionUpdated(
        address indexed module,
        uint256 indexed nodeOperatorId,
        bool restricted
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
    /// @param name Display name
    /// @param description Long description
    function set(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
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

    /// @notice Restrict or allow owner metadata updates
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    /// @param restricted Whether owner updates are blocked
    function setOwnerRestriction(
        address module,
        uint256 nodeOperatorId,
        bool restricted
    ) external;

    /// @notice Check if owner metadata updates are restricted
    /// @param module Module address
    /// @param nodeOperatorId Node Operator id
    function isOwnerRestricted(
        address module,
        uint256 nodeOperatorId
    ) external view returns (bool);
}
