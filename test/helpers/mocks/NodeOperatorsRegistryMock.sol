// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

contract NodeOperatorsRegistryMock {
    struct NodeOperatorData {
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
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

    function getNodeOperatorSummary(
        uint256 nodeOperatorId
    ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        NodeOperatorData storage data = nodeOperators[nodeOperatorId];
        return (0, 0, 0, 0, 0, data.totalExitedValidators, data.totalDepositedValidators, 0);
    }
}
