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
        uint256 indexed nodeOperatorId,
        string name,
        string description
    );

    error ZeroAdminAddress();
    error ZeroModuleAddress();
    error NodeOperatorDoesNotExist();
    error NotOwner();

    /// @return Role id allowed to set metadata
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Set or update metadata for a Node Operator (callable by SETTER_ROLE)
    /// @param nodeOperatorId Node Operator id
    /// @param name Display name
    /// @param description Long description
    function set(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Set or update metadata by the Node Operator owner
    /// @param nodeOperatorId Node Operator id
    /// @param name Display name
    /// @param description Long description
    function setByOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external;

    /// @notice Get metadata for a Node Operator
    /// @param nodeOperatorId Node Operator id
    /// @return info Stored metadata struct
    function get(
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info);
}
