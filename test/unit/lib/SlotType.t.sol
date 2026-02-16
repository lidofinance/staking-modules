// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Slot } from "src/lib/Types.sol";

contract SlotTypeFuzzTest is Test {
    function testFuzz_unwrap(uint64 v) public pure {
        assertEq(Slot.wrap(v).unwrap(), v);
    }

    function testFuzz_gt(uint64 a, uint64 b) public pure {
        assertEq(Slot.wrap(a) > Slot.wrap(b), a > b);
    }

    function testFuzz_lt(uint64 a, uint64 b) public pure {
        assertEq(Slot.wrap(a) < Slot.wrap(b), a < b);
    }

    function testFuzz_lte(uint64 a, uint64 b) public pure {
        assertEq(Slot.wrap(a) <= Slot.wrap(b), a <= b);
    }
}
