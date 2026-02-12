// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry, OperatorMetadata } from "src/interfaces/IMetaRegistry.sol";

contract MetaRegistryMock {
    function setOperatorMetadataAsAdmin(uint256 nodeOperatorId, OperatorMetadata calldata metadata) external {
        emit IMetaRegistry.OperatorMetadataSet({ nodeOperatorId: nodeOperatorId, metadata: metadata });
    }
}
