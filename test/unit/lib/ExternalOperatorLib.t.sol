// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { ExternalOperatorLib, OperatorType } from "src/lib/ExternalOperatorLib.sol";

contract Library {
    using ExternalOperatorLib for IMetaRegistry.ExternalOperator;

    function uniqueKey(IMetaRegistry.ExternalOperator calldata op) external pure returns (bytes32) {
        return op.uniqueKey();
    }

    function tryGetExtOpType(IMetaRegistry.ExternalOperator calldata op) external pure returns (OperatorType) {
        return op.tryGetExtOpType();
    }

    function unpackEntryTypeNOR(IMetaRegistry.ExternalOperator calldata op) external pure returns (uint8, uint64) {
        return op.unpackEntryTypeNOR();
    }
}

contract ExternalOperatorLibTest is Test {
    using ExternalOperatorLib for IMetaRegistry.ExternalOperator;

    Library lib;

    function setUp() public {
        lib = new Library();
    }

    function testFuzz_uniqueKey(bytes calldata data) public view {
        assertEq(lib.uniqueKey(IMetaRegistry.ExternalOperator(data)), keccak256(data));
    }

    function testFuzz_uniqueKey_differentNOREntries(
        uint8 moduleIdA,
        uint64 noIdA,
        uint8 moduleIdB,
        uint64 noIdB
    ) public view {
        vm.assume(moduleIdA != moduleIdB || noIdA != noIdB);
        assertTrue(lib.uniqueKey(norEntry(moduleIdA, noIdA)) != lib.uniqueKey(norEntry(moduleIdB, noIdB)));
    }

    function testFuzz_unpackEntryTypeNOR(uint8 moduleId, uint64 noId) public view {
        (uint8 m, uint64 n) = lib.unpackEntryTypeNOR(norEntry(moduleId, noId));
        assertEq(m, moduleId);
        assertEq(n, noId);
    }

    function test_tryGetExtOpType() public view {
        assertEq(uint8(lib.tryGetExtOpType(norEntry(1, 0))), uint8(OperatorType.NOR));
    }

    function test_tryGetExtOpType_revertWhen_wrongType() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.tryGetExtOpType(IMetaRegistry.ExternalOperator(abi.encode(type(OperatorType).max)));
    }

    function test_tryGetExtOpType_revertWhen_tooShort() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.tryGetExtOpType(IMetaRegistry.ExternalOperator(new bytes(ExternalOperatorLib.ENTRY_LEN_NOR - 1)));
    }

    function test_tryGetExtOpType_revertWhen_tooLong() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.tryGetExtOpType(IMetaRegistry.ExternalOperator(new bytes(ExternalOperatorLib.ENTRY_LEN_NOR + 1)));
    }

    function test_tryGetExtOpType_revertWhen_empty() public {
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        lib.tryGetExtOpType(IMetaRegistry.ExternalOperator(""));
    }

    function norEntry(uint8 moduleId, uint64 noId) internal pure returns (IMetaRegistry.ExternalOperator memory) {
        return IMetaRegistry.ExternalOperator(abi.encodePacked(uint8(OperatorType.NOR), moduleId, noId));
    }
}
