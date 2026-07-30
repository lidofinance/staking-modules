// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Node operator registry interface for legacy curated module.
interface INodeOperatorsRegistry {
    /// @notice Returns the node operator by id.
    /// @param _nodeOperatorId Node Operator id.
    /// @param _fullInfo If true, name will be returned as well.
    function getNodeOperator(
        uint256 _nodeOperatorId,
        bool _fullInfo
    )
        external
        view
        returns (
            bool active,
            string memory name,
            address rewardAddress,
            uint64 totalVettedValidators,
            uint64 totalExitedValidators,
            uint64 totalAddedValidators,
            uint64 totalDepositedValidators
        );

    /// @notice Returns total number of node operators
    function getNodeOperatorsCount() external view returns (uint256);
}
