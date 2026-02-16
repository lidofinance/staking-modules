// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

library KeyPointerLib {
    function keyPointer(uint256 nodeOperatorId, bytes calldata publicKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(nodeOperatorId, publicKey));
    }

    function keyPointer(uint256 nodeOperatorId, uint256 keyIndex) internal pure returns (uint256) {
        return (nodeOperatorId << 128) | keyIndex;
    }
}
