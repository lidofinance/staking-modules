// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Arrays } from "@openzeppelin/contracts/utils/Arrays.sol";
import { Comparators } from "@openzeppelin/contracts/utils/Comparators.sol";

import { PackedSortKey, PackedSortKeyLib } from "src/lib/allocator/PackedSortKeyLib.sol";

contract PackedSortKeyLibTest is Test {
    using PackedSortKeyLib for PackedSortKey;

    function test_packUnpack_RoundTrip() public pure {
        uint256 imbalance = 123_456_789 ether;
        uint256 idx = 777;

        PackedSortKey key = PackedSortKeyLib.pack(imbalance, idx);

        assertEq(key.unpackImbalance(), imbalance);
        assertEq(key.unpackIndex(), idx);
    }

    function test_ordering_EqualImbalanceLowerIndexWins() public pure {
        uint256 imbalance = 42 ether;

        PackedSortKey k0 = PackedSortKeyLib.pack(imbalance, 0);
        PackedSortKey k1 = PackedSortKeyLib.pack(imbalance, 1);

        assertGt(PackedSortKey.unwrap(k0), PackedSortKey.unwrap(k1));
    }

    function test_ordering_HigherImbalanceWins() public pure {
        PackedSortKey lowImbalance = PackedSortKeyLib.pack(1 ether, type(uint32).max);
        PackedSortKey highImbalance = PackedSortKeyLib.pack(2 ether, 0);

        assertGt(PackedSortKey.unwrap(highImbalance), PackedSortKey.unwrap(lowImbalance));
    }

    function test_asUint256Array_CastAndSortReflectOnPackedArray() public pure {
        PackedSortKey[] memory keys = new PackedSortKey[](3);
        keys[0] = PackedSortKeyLib.pack(1 ether, 2);
        keys[1] = PackedSortKeyLib.pack(3 ether, 1);
        keys[2] = PackedSortKeyLib.pack(2 ether, 0);

        uint256[] memory raw = PackedSortKeyLib.asUint256Array(keys);
        assertEq(raw.length, 3);
        assertEq(raw[0], PackedSortKey.unwrap(keys[0]));
        assertEq(raw[1], PackedSortKey.unwrap(keys[1]));
        assertEq(raw[2], PackedSortKey.unwrap(keys[2]));

        Arrays.sort(raw, Comparators.gt);

        // Verify sorting through uint256[] view updates original PackedSortKey[] view.
        assertEq(keys[0].unpackImbalance(), 3 ether);
        assertEq(keys[0].unpackIndex(), 1);
        assertEq(keys[1].unpackImbalance(), 2 ether);
        assertEq(keys[1].unpackIndex(), 0);
        assertEq(keys[2].unpackImbalance(), 1 ether);
        assertEq(keys[2].unpackIndex(), 2);
    }
}
