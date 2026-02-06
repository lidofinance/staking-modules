// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

library ExternalOperatorLib {
    enum OperatorType {
        NOR
    }

    uint256 public constant ENTRY_LEN_NOR = 10; // 1 + 1 + 8 (enum OperatorType, uint8 moduleId, uint64 nodeOperatorId)

    error InvalidExternalOperatorDataEntry();

    function uniqueKey(bytes memory data) internal pure returns (bytes32) {
        // NOTE: As long the first byte is dedicated to the operator type, the simple hashing is enough.
        return keccak256(data);
    }

    function unpackEntry(
        bytes memory data
    ) internal pure returns (uint8 moduleId_, uint64 noId_) {
        // NOTE: Type guard for now; replace with a proper switch for more types.
        if (!isNOR(data)) {
            revert InvalidExternalOperatorDataEntry();
        }

        moduleId_ = _moduleIdNOR(data);
        noId_ = _noIdNOR(data);
    }

    function isNOR(bytes memory data) internal pure returns (bool) {
        if (data.length != ENTRY_LEN_NOR) {
            return false;
        }

        return data[0] == bytes1(uint8(OperatorType.NOR));
    }

    function _noIdNOR(bytes memory data) private pure returns (uint64 ret) {
        assembly ("memory-safe") {
            mstore(0, 0) // Clean the first 32 bytes of the scratch buffer.
            mcopy(24, add(data, 34), 8) // Copy 8 bytes from the data, skipping the first 2 bytes to correct offset.
            ret := mload(0)
        }
    }

    function _moduleIdNOR(bytes memory data) private pure returns (uint8) {
        return uint8(data[1]);
    }
}
