// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry } from "../interfaces/IMetaRegistry.sol";

library ExternalOperatorLib {
    uint256 public constant ENTRY_LEN_NOR = 10; // 1 + 1 + 8 (format tag, uint8 moduleId, uint64 nodeOperatorId)
    bytes1 private constant ENTRY_TAG = 0x00;

    error InvalidExternalOperatorDataEntry();

    function uniqueKey(IMetaRegistry.ExternalOperator memory self) internal pure returns (bytes32) {
        // NOTE: As long the first byte is dedicated to the format tag, the simple hashing is enough.
        return keccak256(self.data);
    }

    function decode(IMetaRegistry.ExternalOperator memory self) internal pure returns (uint8 moduleId, uint64 noId) {
        bytes memory data = self.data;
        if (data.length != ENTRY_LEN_NOR || data[0] != ENTRY_TAG) revert InvalidExternalOperatorDataEntry();

        moduleId = uint8(data[1]);
        assembly ("memory-safe") {
            mstore(0, 0) // Clean the first 32 bytes of the scratch buffer.
            mcopy(24, add(data, 34), 8) // Copy 8 bytes from the data, skipping the first 2 bytes to correct offset.
            noId := mload(0) // The last 8 bytes hold the operator ID.
        }
    }
}
