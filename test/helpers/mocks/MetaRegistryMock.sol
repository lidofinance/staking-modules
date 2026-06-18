// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry, OperatorMetadata } from "src/interfaces/IMetaRegistry.sol";

contract MetaRegistryMock {
    uint256 public refreshOperatorWeightCallCount;
    uint256 public lastRefreshedOperatorId;

    function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external {
        emit IMetaRegistry.OperatorMetadataSet({ nodeOperatorId: nodeOperatorId, metadata: metadata });
    }

    function refreshOperatorWeight(uint256 nodeOperatorId) external {
        refreshOperatorWeightCallCount++;
        lastRefreshedOperatorId = nodeOperatorId;
    }
}
