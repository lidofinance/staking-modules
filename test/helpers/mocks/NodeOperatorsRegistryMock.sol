// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { INodeOperatorsRegistry } from "src/interfaces/INodeOperatorsRegistry.sol";

contract NodeOperatorsRegistryMock is INodeOperatorsRegistry {
    struct NodeOperatorData {
        bool active;
        string name;
        address rewardAddress;
        uint64 totalVettedValidators;
        uint64 totalExitedValidators;
        uint64 totalAddedValidators;
        uint64 totalDepositedValidators;
    }

    uint256 internal nodeOperatorsCount;
    mapping(uint256 => NodeOperatorData) internal nodeOperators;

    function mock_setNodeOperatorsCount(uint256 count) external {
        nodeOperatorsCount = count;
    }

    function mock_setNodeOperator(uint256 nodeOperatorId, NodeOperatorData calldata data) external {
        nodeOperators[nodeOperatorId] = data;
    }

    function getNodeOperatorsCount() external view returns (uint256) {
        return nodeOperatorsCount;
    }

    function getNodeOperator(
        uint256 nodeOperatorId,
        bool
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
        )
    {
        NodeOperatorData storage data = nodeOperators[nodeOperatorId];
        active = data.active;
        name = data.name;
        rewardAddress = data.rewardAddress;
        totalVettedValidators = data.totalVettedValidators;
        totalExitedValidators = data.totalExitedValidators;
        totalAddedValidators = data.totalAddedValidators;
        totalDepositedValidators = data.totalDepositedValidators;
    }
}
