// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { GIndex, toGIndex, IndexOutOfRange, fls, staticListNodeGIndex, progressiveListNodeGIndex } from "src/lib/GIndex.sol";

// Wrap the library internal methods to make an actual call to them.
// Supposed to be used with `expectRevert` cheatcode.
contract Library {
    function concat(GIndex lhs, GIndex rhs) external pure returns (GIndex) {
        return lhs.concat(rhs);
    }

    function staticListNodeGIndex(uint256 i, uint256 depth) external pure returns (GIndex) {
        return staticListNodeGIndex(i, depth);
    }

    function progressiveListNodeGIndex(uint256 i) external pure returns (GIndex) {
        return progressiveListNodeGIndex(i);
    }
}

contract GIndexTest is Test {
    using Strings for uint256;

    uint256 internal constant LARGEST_PROGRESSIVE_LIST_IDX = ((4 ** 84 - 1) * 4) / 3;

    GIndex internal ZERO = toGIndex(0);
    GIndex internal ROOT = toGIndex(1);
    GIndex internal MAX = toGIndex(type(uint256).max);

    Library internal lib;

    function setUp() public {
        lib = new Library();
    }

    function test_isRootTrue() public view {
        assertTrue(ROOT.isRoot(), "ROOT is not root gindex");
    }

    function test_isRootFalse() public pure {
        GIndex gI;

        gI = toGIndex(0);
        assertFalse(gI.isRoot(), "Expected toGIndex(0).isRoot() to be false");

        gI = toGIndex(42);
        assertFalse(gI.isRoot(), "Expected toGIndex(42).isRoot() to be false");

        gI = toGIndex(2048);
        assertFalse(gI.isRoot(), "Expected toGIndex(2048).isRoot() to be false");

        gI = toGIndex(type(uint256).max);
        assertFalse(gI.isRoot(), "Expected toGIndex(uint256.max).isRoot() to be false");
    }

    function test_concat() public view {
        assertEq(toGIndex(2).concat(toGIndex(3)).unwrap(), 5);
        assertEq(toGIndex(31).concat(toGIndex(3)).unwrap(), 63);
        assertEq(toGIndex(31).concat(toGIndex(6)).unwrap(), 126);
        assertEq(ROOT.concat(toGIndex(2)).concat(toGIndex(5)).concat(toGIndex(9)).unwrap(), 73);

        assertEq(ROOT.concat(MAX).unwrap(), MAX.unwrap());
    }

    function test_concat_RevertsIfZeroGIndex() public {
        vm.expectRevert(IndexOutOfRange.selector);
        lib.concat(ZERO, toGIndex(1024));

        vm.expectRevert(IndexOutOfRange.selector);
        lib.concat(toGIndex(1024), ZERO);
    }

    function test_concat_BigIndicesBorderCases() public view {
        lib.concat(toGIndex(2 ** 9), toGIndex(2 ** 246));
        lib.concat(toGIndex(2 ** 55), toGIndex(2 ** 200));
        lib.concat(toGIndex(2 ** 199), toGIndex(2 ** 56));
    }

    function test_concat_RevertsIfTooBigIndices() public {
        vm.expectRevert(IndexOutOfRange.selector);
        lib.concat(MAX, MAX);

        vm.expectRevert(IndexOutOfRange.selector);
        lib.concat(toGIndex(2 ** 56), toGIndex(2 ** 200));

        vm.expectRevert(IndexOutOfRange.selector);
        lib.concat(toGIndex(2 ** 200), toGIndex(2 ** 56));
    }

    function testFuzz_concat_WithRoot(GIndex rhs) public view {
        vm.assume(rhs.unwrap() > 0);
        assertEq(ROOT.concat(rhs).unwrap(), rhs.unwrap(), "`concat` with a root should return right-hand side value");
    }

    function test_fls() public {
        for (uint256 i = 1; i < 255; i++) {
            uint256 n;

            n = (1 << i) - 1;
            assertEq(fls(n), i - 1, string.concat("fls(", n.toString(), ")"));

            n = (1 << i);
            assertEq(fls(n), i, string.concat("fls(", n.toString(), ")"));

            n = (1 << i) + 1;
            assertEq(fls(n), i, string.concat("fls(", n.toString(), ")"));
        }

        assertEq(fls(0), 256, "fls(0)");
        assertEq(fls(3), 1, "fls(3)"); // 0011
        assertEq(fls(7), 2, "fls(7)"); // 0101
        assertEq(fls(10), 3, "fls(10)"); // 1010
        assertEq(fls(300), 8, "fls(300)"); // 0001 0010 1100

        vm.startSnapshotGas("GIndex.fls");
        fls(31337);
        vm.stopSnapshotGas();
    }

    function test_staticListNodeGIndex() public {
        assertEq(staticListNodeGIndex(0, 40).unwrap(), 0x020000000000);
        assertEq(staticListNodeGIndex(12345678, 40).unwrap(), 0x020000bc614e);
        assertEq(staticListNodeGIndex((1 << 40) - 1, 40).unwrap(), 0x02ffffffffff);
    }

    function testFuzz_staticListNodeGIndex(uint256 i) public {
        uint256 depth = uint256(fls(i) & type(uint8).max) + 1;
        vm.assume(depth < 255);

        string[] memory cmd = new string[](5);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/ssz/static_list_gindex.mjs";
        cmd[3] = i.toString();
        cmd[4] = (1 << depth).toString();
        bytes memory res = vm.ffi(cmd);
        uint256 expected = abi.decode(res, (uint256));

        assertEq(staticListNodeGIndex(i, uint8(depth)).unwrap(), expected);
    }

    function test_progressiveListNodeGIndex() public {
        vm.startSnapshotGas("GIndex.progressiveListNodeGIndex");
        assertEq(progressiveListNodeGIndex(0).unwrap(), 0x4);
        vm.stopSnapshotGas();

        assertEq(progressiveListNodeGIndex(1).unwrap(), 0x28);
        assertEq(progressiveListNodeGIndex(2).unwrap(), 0x29);
        assertEq(progressiveListNodeGIndex(4).unwrap(), 0x2b);
        assertEq(progressiveListNodeGIndex(5).unwrap(), 0x160);
        assertEq(progressiveListNodeGIndex(128).unwrap(), 0x5e2b);
        assertEq(progressiveListNodeGIndex(12345678).unwrap(), 0x5ffe670bf9);
        assertEq(progressiveListNodeGIndex((1 << 40) - 1).unwrap(), 0x5ffffeaaaaaaaaaa);
        assertEq(
            progressiveListNodeGIndex(((4 ** 84 - 1) * 4) / 3).unwrap(),
            0x5ffffffffffffffffffffeffffffffffffffffffffffffffffffffffffffffff
        );
    }

    function testFuzz_progressiveListNodeGIndex(uint256 i) public {
        vm.assume(i < 1 << 166);

        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/ssz/progressive_list_gindex.mjs";
        cmd[3] = i.toString();
        bytes memory res = vm.ffi(cmd);
        uint256 expected = abi.decode(res, (uint256));

        assertEq(progressiveListNodeGIndex(i).unwrap(), expected);
    }

    function test_staticListNodeGIndex_RevertsWhenTooDeep() public {
        vm.expectRevert(IndexOutOfRange.selector);
        lib.staticListNodeGIndex(0, 255);
    }

    function testFuzz_staticListNodeGIndex_RevertsWhenIndexTooLargeForDepth(uint8 d) public {
        vm.assume(d < 255);

        vm.expectRevert(IndexOutOfRange.selector);
        lib.staticListNodeGIndex(1 << (d + 1), d);
    }

    function test_progressiveListNodeGIndex_RevertsWhenIndexTooLarge() public {
        vm.expectRevert(IndexOutOfRange.selector);
        lib.progressiveListNodeGIndex(LARGEST_PROGRESSIVE_LIST_IDX + 1);
    }
}
