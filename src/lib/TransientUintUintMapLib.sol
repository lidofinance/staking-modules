// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

type TransientUintUintMap is uint256;

using TransientUintUintMapLib for TransientUintUintMap global;

library TransientUintUintMapLib {
    function create() internal returns (TransientUintUintMap self) {
        // keccak256(abi.encode(uint256(keccak256("TransientUintUintMap")) - 1)) & ~bytes32(uint256(0xff))
        uint256 anchor = 0x6e38e7eaa4307e6ee6c66720337876ca65012869fbef035f57219354c1728400;

        // `anchor` slot in the transient storage tracks the "address" of the last created object.
        // The next address is being computed as keccak256(`anchor` . `prev`).
        assembly ("memory-safe") {
            let prev := tload(anchor)
            mstore(0x00, anchor)
            mstore(0x20, prev)
            self := keccak256(0x00, 0x40)
            tstore(anchor, self)
        }
    }

    function add(
        TransientUintUintMap self,
        uint256 key,
        uint256 value
    ) internal {
        uint256 slot = _slot(self, key);
        assembly ("memory-safe") {
            let v := tload(slot)
            // NOTE: Here's no overflow check.
            v := add(v, value)
            tstore(slot, v)
        }
    }

    function set(
        TransientUintUintMap self,
        uint256 key,
        uint256 value
    ) internal {
        uint256 slot = _slot(self, key);
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    function get(
        TransientUintUintMap self,
        uint256 key
    ) internal view returns (uint256 v) {
        uint256 slot = _slot(self, key);
        assembly ("memory-safe") {
            v := tload(slot)
        }
    }

    function load(
        bytes32 tslot
    ) internal pure returns (TransientUintUintMap self) {
        assembly ("memory-safe") {
            self := tslot
        }
    }

    function _slot(
        TransientUintUintMap self,
        uint256 key
    ) internal pure returns (uint256 slot) {
        // Compute an address in the transient storage in the same manner it works for storage mappings.
        // `slot` = keccak256(`self` . `key`)
        assembly ("memory-safe") {
            mstore(0x00, self)
            mstore(0x20, key)
            slot := keccak256(0x00, 0x40)
        }
    }
}
