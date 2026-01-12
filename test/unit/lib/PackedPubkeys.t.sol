// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test, stdError } from "forge-std/Test.sol";

import { PackedPubkeys } from "src/lib/PackedPubkeys.sol";

import { Utilities } from "../../helpers/Utilities.sol";

contract Library {
    using PackedPubkeys for bytes;

    function at(
        bytes calldata keys,
        uint256 keyIndex
    ) external returns (bytes memory) {
        return keys.at(keyIndex);
    }
}

contract PackedPubkeysTest is Test, Utilities {
    Library internal lib;

    function setUp() public {
        lib = new Library();
    }

    function test_at() public {
        bytes memory key0 = randomBytes(48);
        bytes memory key1 = randomBytes(48);
        bytes memory key2 = randomBytes(48);

        bytes memory keys = bytes.concat(key0, key1, key2);

        assertEq(lib.at(keys, 0), key0);
        assertEq(lib.at(keys, 1), key1);
        assertEq(lib.at(keys, 2), key2);
    }

    function test_at_RevertWhenNotEnoughBytes() public {
        vm.expectRevert(stdError.indexOOBError);
        lib.at(randomBytes(0), 0);

        vm.expectRevert(stdError.indexOOBError);
        lib.at(randomBytes(47), 0);

        vm.expectRevert(stdError.indexOOBError);
        lib.at(randomBytes(48), 1);

        vm.expectRevert(stdError.indexOOBError);
        lib.at(randomBytes(95), 1);
    }
}
