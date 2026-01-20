// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

library PackedPubkeys {
    uint64 internal constant PUBKEY_LENGTH = 48;

    function at(
        bytes calldata self,
        uint256 keyIndex
    ) internal pure returns (bytes memory key) {
        key = new bytes(PUBKEY_LENGTH);

        assembly ("memory-safe") {
            let p := mul(PUBKEY_LENGTH, keyIndex)
            if gt(add(p, PUBKEY_LENGTH), self.length) {
                // Equal to `revert Panic(0x32)`, where 0x32 is the standard code for "Out of bounds" error in Solidity.
                mstore(0x00, 0x4e487b71) // `Panic(uint256)`.
                mstore(0x20, 0x32) // 0x32 = Out of bounds.
                revert(0x1c, 0x24)
            }

            p := add(self.offset, p)
            // evmcodes: for out of bound bytes, 0s will be copied.
            calldatacopy(add(key, 0x20), p, PUBKEY_LENGTH)
        }
    }

    function count(bytes calldata self) internal pure returns (uint256) {
        return self.length / PUBKEY_LENGTH;
    }
}
