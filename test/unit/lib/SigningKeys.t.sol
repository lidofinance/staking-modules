// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test, stdError } from "forge-std/Test.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { Utilities } from "../../helpers/Utilities.sol";

// Wrap the library internal methods to make an actual call to them.
// Supposed to be used with `expectRevert` cheatcode and to pass
// calldata arguments.
contract Library {
    function saveKeysSigs(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount,
        bytes calldata pubkeys,
        bytes calldata signatures
    ) external returns (uint256) {
        return
            SigningKeys.saveKeysSigs(
                nodeOperatorId,
                startIndex,
                keysCount,
                pubkeys,
                signatures
            );
    }

    function removeKeysSigs(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount,
        uint256 totalKeysCount
    ) external returns (uint256) {
        return
            SigningKeys.removeKeysSigs(
                nodeOperatorId,
                startIndex,
                keysCount,
                totalKeysCount
            );
    }

    function loadKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external view returns (bytes memory pubkeys) {
        return SigningKeys.loadKeys(nodeOperatorId, startIndex, keysCount);
    }

    function loadKeysSigs(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount,
        uint256 bufOffset
    ) external view returns (bytes memory keys, bytes memory sigs) {
        (keys, sigs) = SigningKeys.initKeysSigsBuf(keysCount + bufOffset);
        SigningKeys.loadKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            keys,
            sigs,
            bufOffset
        );
    }
}

contract SigningKeysTestBase is Test, Utilities {
    using stdError for *;

    uint64 internal constant PUBKEY_LENGTH = 48;
    uint64 internal constant SIGNATURE_LENGTH = 96;

    Library signingKeys;

    function setUp() public {
        signingKeys = new Library();
    }
}

contract SigningKeysSaveTest is SigningKeysTestBase {
    function test_saveKeysSigs_HappyPath() public {
        uint256 keysCount = 1;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        vm.expectEmit(address(signingKeys));
        emit IStakingModule.SigningKeyAdded(nodeOperatorId, pubkeys);
        uint256 newKeysCount = signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        assertEq(newKeysCount, startIndex + keysCount);
        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys, pubkeys);
    }

    function test_saveKeysSigs_LastKeyForOperator() public {
        uint256 keysCount = 1;
        uint256 startIndex = type(uint32).max - 1;
        uint256 nodeOperatorId = 154;
        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        vm.expectEmit(address(signingKeys));
        emit IStakingModule.SigningKeyAdded(nodeOperatorId, pubkeys);
        uint256 newKeysCount = signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        assertEq(newKeysCount, startIndex + keysCount);
        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys, pubkeys);
    }

    function test_saveKeysSigs_revertWhen_zeroKeys() public {
        uint256 keysCount = 0;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );
    }

    function test_saveKeysSigs_revertWhen_tooManyKeys() public {
        uint256 keysCount = type(uint32).max;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        (bytes memory pubkeys, bytes memory signatures) = (
            new bytes(0),
            new bytes(0)
        );

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );
    }

    function test_saveKeysSigs_revertWhen_startIndexTooBig() public {
        (bytes memory pubkeys, bytes memory signatures) = (
            new bytes(0),
            new bytes(0)
        );

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.saveKeysSigs({
            nodeOperatorId: 154,
            startIndex: type(uint32).max,
            keysCount: 1,
            pubkeys: pubkeys,
            signatures: signatures
        });

        vm.expectRevert(stdError.arithmeticError);
        signingKeys.saveKeysSigs({
            nodeOperatorId: 154,
            startIndex: type(uint256).max,
            keysCount: 1,
            pubkeys: pubkeys,
            signatures: signatures
        });
    }

    function test_saveKeysSigs_revertWhen_invalidSigsLen() public {
        uint256 keysCount = 10;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (bytes memory pubkeys, ) = keysSignatures(keysCount, startIndex);
        vm.expectRevert(SigningKeys.InvalidLength.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            new bytes(0)
        );
    }

    function test_saveKeysSigs_revertWhen_invalidPubkeysLen() public {
        uint256 keysCount = 10;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (, bytes memory signatures) = keysSignatures(keysCount, startIndex);
        vm.expectRevert(SigningKeys.InvalidLength.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            new bytes(0),
            signatures
        );
    }

    function test_saveKeysSigs_revertWhen_pubkeysAndSignaturesUnaligned()
        public
    {
        uint256 nodeOperatorId = 154;
        uint256 startIndex = 12;

        (bytes memory pubkeys, ) = keysSignatures(10, startIndex);
        (, bytes memory signatures) = keysSignatures(11, startIndex);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            10,
            pubkeys,
            signatures
        );
    }

    function test_saveKeysSigs_revertWhen_EmptyKey() public {
        uint256 keysCount = 10;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (
            bytes memory pubkeys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, startIndex, 3);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );
    }

    function testFuzz_saveKeysSigs_HappyPath(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public {
        keysCount = uint32(bound(keysCount, 1, 100));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        uint256 newKeysCount = signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        assertEq(newKeysCount, startIndex + keysCount);
        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys, pubkeys);
    }

    function testFuzz_saveKeysSigs_revertWhen_EmptyKey(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount,
        uint8 offset
    ) public {
        keysCount = uint32(bound(keysCount, 1, 100));
        vm.assume(offset < keysCount);
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (
            bytes memory pubkeys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(
                keysCount,
                // Utilities helper accepts uint16 start indexes; fuzzed values are bounded by the helper,
                // so truncating to 16 bits is intentional.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint16(startIndex),
                offset
            );

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );
    }
}

contract SigningKeysRemoveTest is SigningKeysTestBase {
    function test_removeKeysSigs_HappyPath() public {
        uint256 nodeOperatorId = 154;

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(3);
        signingKeys.saveKeysSigs({
            nodeOperatorId: nodeOperatorId,
            startIndex: 0,
            keysCount: 3,
            pubkeys: pubkeys,
            signatures: signatures
        });

        bytes memory removedKey = slice(pubkeys, PUBKEY_LENGTH, PUBKEY_LENGTH);
        vm.expectEmit(address(signingKeys));
        emit IStakingModule.SigningKeyRemoved(nodeOperatorId, removedKey);
        uint256 newTotalKeysCount = signingKeys.removeKeysSigs({
            nodeOperatorId: nodeOperatorId,
            startIndex: 1,
            keysCount: 1,
            totalKeysCount: 3
        });

        assertEq(newTotalKeysCount, 2);

        bytes memory lastAddedKey = slice(
            pubkeys,
            PUBKEY_LENGTH * 2,
            PUBKEY_LENGTH
        );
        bytes memory keyInPlaceOfRemoved = signingKeys.loadKeys({
            nodeOperatorId: nodeOperatorId,
            startIndex: 1,
            keysCount: 1
        });

        assertEq(keyInPlaceOfRemoved, lastAddedKey);
    }

    function test_removeKeysSigs_noKeysAdded() public {
        uint256 keysCount = 10;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        vm.expectEmit(address(signingKeys));
        emit IStakingModule.SigningKeyRemoved(
            nodeOperatorId,
            new bytes(PUBKEY_LENGTH)
        );
        signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            startIndex + keysCount
        );
    }

    function test_removeKeysSigs_revertWhen_zeroKeys() public {
        uint256 keysCount = 1;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            0,
            keysCount + startIndex
        );
    }

    function test_removeKeysSigs_revertWhen_keysPlusStartHigherThanTotal()
        public
    {
        uint256 keysCount = 1;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            startIndex + keysCount - 1
        );
    }

    function test_removeKeysSigs_revertWhen_totalKeysTooHigh() public {
        uint256 keysCount = 1;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            uint256(type(uint32).max) + 1
        );
    }

    function testFuzz_removeKeysSigs_offsetRight(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount,
        uint8 offset
    ) public {
        keysCount = uint32(bound(keysCount, 1, 100));
        vm.assume(offset < keysCount);
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 totalKeysCount = signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        uint256 newTotalKeysCount = signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex + offset,
            keysCount - offset,
            totalKeysCount
        );

        assertEq(newTotalKeysCount, totalKeysCount - keysCount + offset);
    }

    function testFuzz_removeKeysSigs_offsetLeft(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount,
        uint8 offset
    ) public {
        startIndex = uint32(bound(startIndex, 0, 99));
        keysCount = uint32(bound(keysCount, 1, 100));
        vm.assume(offset < startIndex);
        vm.assume(offset < keysCount);
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 totalKeysCount = signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        uint256 newTotalKeysCount = signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex - offset,
            keysCount - offset,
            totalKeysCount
        );

        assertEq(newTotalKeysCount, totalKeysCount - keysCount + offset);
    }

    function testFuzz_removeKeysSigs_NoKeysAdded(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public {
        keysCount = uint32(bound(keysCount, 1, 200));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        uint256 totalKeysCount = startIndex + keysCount;

        uint256 newTotalKeysCount = signingKeys.removeKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            totalKeysCount
        );

        assertEq(newTotalKeysCount, totalKeysCount - keysCount);
    }
}

contract SigningKeysLoadTest is SigningKeysTestBase {
    using SigningKeys for bytes32;

    function test_getKeyOffset() public pure {
        assertEq(
            uint256(
                0xc7224de16f166822b4efb83b0e3edb78754345751aa6411448d7bf241a1dd403
            ),
            SigningKeys.SIGNING_KEYS_POSITION.getKeyOffset({
                nodeOperatorId: 1,
                keyIndex: 0
            })
        );
        assertEq(
            uint256(
                0xd5b4059fcaec08c6b5ebefcaa178a5297fb8f60f7a096c6362bda9f5de3b2b2d
            ),
            SigningKeys.SIGNING_KEYS_POSITION.getKeyOffset({
                nodeOperatorId: 2,
                keyIndex: 0
            })
        );
        assertEq(
            uint256(
                0x371c76b82d811a2203237a0d71bebb72f52de0f28f3c1f6efd70d326ffe58b66
            ),
            SigningKeys.SIGNING_KEYS_POSITION.getKeyOffset({
                nodeOperatorId: 2,
                keyIndex: 1
            })
        );
    }

    function test_loadKeys() public {
        uint256 keysCount = 10;
        uint256 startIndex = 2;
        uint256 nodeOperatorId = 154;
        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys, pubkeys);
    }

    function testFuzz_loadKeys(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public {
        keysCount = uint32(bound(keysCount, 1, 100));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys.length, keysCount * PUBKEY_LENGTH);
    }

    function testFuzz_loadKeys_FromEmptyStorage(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public view {
        keysCount = uint32(bound(keysCount, 1, 500));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        bytes memory loadedPubkeys = signingKeys.loadKeys(
            nodeOperatorId,
            startIndex,
            keysCount
        );

        assertEq(loadedPubkeys.length, keysCount * PUBKEY_LENGTH);
    }

    function test_loadKeysSigs() public {
        uint256 keysCount = 10;
        uint16 startIndex = 2;
        uint256 nodeOperatorId = 154;

        (bytes memory pubkeys, bytes memory signatures) = keysSignatures(
            keysCount,
            startIndex
        );
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            signatures
        );

        (bytes memory loadedKeys, bytes memory loadedSigs) = signingKeys
            .loadKeysSigs(nodeOperatorId, startIndex, keysCount, 0);

        assertEq(loadedKeys, pubkeys);
        assertEq(loadedSigs, signatures);
    }

    function testFuzz_loadKeysSigs(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public {
        keysCount = uint32(bound(keysCount, 1, 100));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory pubkeys, bytes memory sigs) = keysSignatures(
            keysCount,
            startIndex
        );
        signingKeys.saveKeysSigs(
            nodeOperatorId,
            startIndex,
            keysCount,
            pubkeys,
            sigs
        );

        (bytes memory loadedKeys, bytes memory loadedSigs) = signingKeys
            .loadKeysSigs(nodeOperatorId, startIndex, keysCount, 0);

        assertEq(loadedKeys.length, keysCount * PUBKEY_LENGTH);
        assertEq(loadedSigs.length, keysCount * SIGNATURE_LENGTH);
    }

    function testFuzz_loadKeysSigs_FromEmptyLocation(
        uint64 nodeOperatorId,
        uint32 startIndex,
        uint32 keysCount
    ) public view {
        keysCount = uint32(bound(keysCount, 1, 200));
        unchecked {
            vm.assume(startIndex + keysCount > startIndex);
        }

        (bytes memory loadedKeys, bytes memory loadedSigs) = signingKeys
            .loadKeysSigs(nodeOperatorId, startIndex, keysCount, 0);

        assertEq(loadedKeys.length, keysCount * PUBKEY_LENGTH);
        assertEq(loadedSigs.length, keysCount * SIGNATURE_LENGTH);
    }
}
