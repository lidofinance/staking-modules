// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry, OperatorMetadata } from "src/interfaces/IMetaRegistry.sol";

contract MetaRegistryMock {
    uint256 public notifyWeightBoostChangedCallCount;
    uint256 public lastChangedBoostOperatorId;
    uint256 public notifyWeightBoostProviderConfigChangedCallCount;

    function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external {
        emit IMetaRegistry.OperatorMetadataSet({ nodeOperatorId: nodeOperatorId, metadata: metadata });
    }

    function notifyWeightBoostChanged(uint256 nodeOperatorId) external {
        notifyWeightBoostChangedCallCount++;
        lastChangedBoostOperatorId = nodeOperatorId;
    }

    function notifyWeightBoostProviderConfigChanged() external {
        notifyWeightBoostProviderConfigChangedCallCount++;
    }
}
