// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { ExternalOperatorLib } from "src/lib/ExternalOperatorLib.sol";

contract Library {
    using ExternalOperatorLib for IMetaRegistry.ExternalOperator;

    function uniqueKey(IMetaRegistry.ExternalOperator calldata op) external pure returns (bytes32) {
        return op.uniqueKey();
    }

    function decode(IMetaRegistry.ExternalOperator calldata op) external pure returns (uint8, uint64) {
        return op.decode();
    }
}

contract ExternalOperatorLibTest is Test {
    Library lib;

    function setUp() public {
        lib = new Library();
    }

    function testFuzz_uniqueKey(bytes calldata data) public view {
        assertEq(lib.uniqueKey(IMetaRegistry.ExternalOperator(data)), keccak256(data));
    }

    function testFuzz_uniqueKey_differentEntries(
        uint8 moduleIdA,
        uint64 noIdA,
        uint8 moduleIdB,
        uint64 noIdB
    ) public view {
        vm.assume(moduleIdA != moduleIdB || noIdA != noIdB);
        assertTrue(lib.uniqueKey(entry(moduleIdA, noIdA)) != lib.uniqueKey(entry(moduleIdB, noIdB)));
    }

    function testFuzz_decode(uint8 moduleId, uint64 noId) public view {
        (uint8 m, uint64 n) = lib.decode(entry(moduleId, noId));
        assertEq(m, moduleId);
        assertEq(n, noId);
    }

    function test_decode() public view {
        (uint8 moduleId, uint64 noId) = lib.decode(IMetaRegistry.ExternalOperator(hex"0001000000000000002a"));
        assertEq(moduleId, 1);
        assertEq(noId, 42);
    }

    function test_decode_revertWhen_wrongTag() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.decode(IMetaRegistry.ExternalOperator(hex"0101000000000000002a"));
    }

    function test_decode_revertWhen_tooShort() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.decode(IMetaRegistry.ExternalOperator(new bytes(ExternalOperatorLib.ENTRY_LEN_NOR - 1)));
    }

    function test_decode_revertWhen_tooLong() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.decode(IMetaRegistry.ExternalOperator(new bytes(ExternalOperatorLib.ENTRY_LEN_NOR + 1)));
    }

    function test_decode_revertWhen_empty() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.decode(IMetaRegistry.ExternalOperator(""));
    }

    function entry(uint8 moduleId, uint64 noId) internal pure returns (IMetaRegistry.ExternalOperator memory) {
        return IMetaRegistry.ExternalOperator(abi.encodePacked(uint8(0), moduleId, noId));
    }
}
