// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "src/lib/TransientUintUintMapLib.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Utilities } from "../../helpers/Utilities.sol";

contract TransientUintUintMapLibTest is Test, Utilities {
    using Strings for uint256;

    function testFuzz_dictAddAndGetValue(
        uint256 k,
        uint256 v,
        uint256 s
    ) public brutalizeMemory {
        // There's no overflow check in the `add` function.
        unchecked {
            vm.assume(v + s > v);
        }

        uint256 sum = v + s;
        uint256 r;

        TransientUintUintMap dict = TransientUintUintMapLib.create();

        // Adding to the same key should increment the value.
        dict.add(k, v);
        dict.add(k, s);
        r = dict.get(k);
        assertEq(
            r,
            sum,
            string.concat("expected=", sum.toString(), " actual=", r.toString())
        );

        // Consequent read of the same key should return the same value.
        r = dict.get(k);
        assertEq(
            r,
            sum,
            string.concat("expected=", sum.toString(), " actual=", r.toString())
        );
    }

    function testFuzz_dictSetAndGetValue(
        uint256 k,
        uint256 v
    ) public brutalizeMemory {
        uint256 r;

        TransientUintUintMap dict = TransientUintUintMapLib.create();

        dict.set(k, v);
        r = dict.get(k);
        assertEq(
            r,
            v,
            string.concat("expected=", v.toString(), " actual=", r.toString())
        );

        // Consequent read of the same key should return the same value.
        r = dict.get(k);
        assertEq(
            r,
            v,
            string.concat("expected=", v.toString(), " actual=", r.toString())
        );
    }

    function testFuzz_noIntersections(
        uint256 a,
        uint256 b
    ) public brutalizeMemory {
        vm.assume(a != b);

        TransientUintUintMap dict1 = TransientUintUintMapLib.create();
        TransientUintUintMap dict2 = TransientUintUintMapLib.create();

        uint256 r;

        dict1.add(a, 1);
        dict2.add(b, 1);

        r = dict1.get(b);
        assertEq(r, 0, string.concat("expected=0 actual=", r.toString()));
        r = dict2.get(a);
        assertEq(r, 0, string.concat("expected=0 actual=", r.toString()));
    }

    function testFuzz_load(uint256 k, uint256 v) public brutalizeMemory {
        TransientUintUintMap dict1 = TransientUintUintMapLib.create();
        dict1.set(k, v);

        bytes32 tslot;
        assembly ("memory-safe") {
            tslot := dict1
        }
        TransientUintUintMap dict2 = TransientUintUintMapLib.load(tslot);

        uint256 r;

        r = dict1.get(k);
        assertEq(
            r,
            v,
            string.concat("expected=", v.toString(), " actual=", r.toString())
        );

        r = dict2.get(k);
        assertEq(
            r,
            v,
            string.concat("expected=", v.toString(), " actual=", r.toString())
        );
    }
}
