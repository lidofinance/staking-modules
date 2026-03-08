// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { SlotDerivation } from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import { TransientSlot } from "@openzeppelin/contracts/utils/TransientSlot.sol";

type TransientUintUintMap is bytes32;

using TransientUintUintMapLib for TransientUintUintMap global;

library TransientUintUintMapLib {
    using SlotDerivation for bytes32;
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.Uint256Slot;

    // SlotDerivation.erc7201Slot("TransientUintUintMap")
    bytes32 private constant ANCHOR = 0x6e38e7eaa4307e6ee6c66720337876ca65012869fbef035f57219354c1728400;

    function create() internal returns (TransientUintUintMap self) {
        // `ANCHOR` slot in the transient storage tracks the base of the last created object.
        // The next base is derived as a mapping slot from `ANCHOR` keyed by `prev`.
        TransientSlot.Uint256Slot anchor = ANCHOR.asUint256();
        uint256 prev = anchor.tload();
        self = TransientUintUintMap.wrap(ANCHOR.deriveMapping(prev));
        anchor.tstore(uint256(TransientUintUintMap.unwrap(self)));
    }

    function add(TransientUintUintMap self, uint256 key, uint256 value) internal {
        TransientSlot.Uint256Slot slot = _slot(self, key).asUint256();
        // NOTE: Here's no overflow check.
        unchecked {
            slot.tstore(slot.tload() + value);
        }
    }

    function set(TransientUintUintMap self, uint256 key, uint256 value) internal {
        _slot(self, key).asUint256().tstore(value);
    }

    function get(TransientUintUintMap self, uint256 key) internal view returns (uint256) {
        return _slot(self, key).asUint256().tload();
    }

    function load(bytes32 tslot) internal pure returns (TransientUintUintMap) {
        return TransientUintUintMap.wrap(tslot);
    }

    function _slot(TransientUintUintMap self, uint256 key) internal pure returns (bytes32) {
        // Derives a transient storage slot following Solidity mapping layout.
        return TransientUintUintMap.unwrap(self).deriveMapping(key);
    }
}
