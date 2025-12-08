// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { CommonBase, Vm } from "forge-std/Base.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @author madlabman
contract Utilities is CommonBase {
    using Strings for uint256;

    bytes constant BASE58ALPHABET =
        bytes("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz");

    bytes32 internal seed = keccak256("seed sEed seEd");

    error FreeMemoryPointerOverflowed();
    error ZeroSlotIsNotZero();

    function nextAddress() internal returns (address) {
        bytes32 buf = keccak256(abi.encodePacked(seed));
        address a = address(uint160(uint256(buf)));
        seed = buf;
        return a;
    }

    function nextAddress(string memory label) internal returns (address) {
        address a = nextAddress();
        vm.label(a, label);
        return a;
    }

    function keysSignatures(
        uint256 keysCount
    ) public pure returns (bytes memory, bytes memory) {
        return keysSignatures(keysCount, 0);
    }

    function keysSignatures(
        uint256 keysCount,
        uint256 startIndex
    ) public pure returns (bytes memory, bytes memory) {
        bytes memory keys;
        bytes memory signatures;
        for (uint256 i = startIndex; i < startIndex + keysCount; i++) {
            bytes memory index = abi.encodePacked(i + 1);
            bytes memory key = bytes.concat(
                new bytes(48 - index.length),
                index
            );
            bytes memory sign = bytes.concat(
                new bytes(96 - index.length),
                index
            );
            keys = bytes.concat(keys, key);
            signatures = bytes.concat(signatures, sign);
        }
        return (keys, signatures);
    }

    function keysSignaturesWithZeroKey(
        uint256 keysCount,
        uint16 startIndex
    ) public pure returns (bytes memory, bytes memory) {
        return keysSignaturesWithZeroKey(keysCount, startIndex, 0);
    }

    function keysSignaturesWithZeroKey(
        uint256 keysCount,
        uint16 startIndex,
        uint16 zeroKeyIndex
    ) public pure returns (bytes memory, bytes memory) {
        bytes memory keys;
        bytes memory signatures;
        for (uint256 i = startIndex; i < startIndex + keysCount; i++) {
            bytes memory index = abi.encodePacked(i + 1);
            bytes memory key = bytes.concat(
                new bytes(48 - index.length),
                index
            );
            if (i == uint32(startIndex) + uint32(zeroKeyIndex)) {
                key = new bytes(48);
            }
            bytes memory sign = bytes.concat(
                new bytes(96 - index.length),
                index
            );
            keys = bytes.concat(keys, key);
            signatures = bytes.concat(signatures, sign);
        }
        return (keys, signatures);
    }

    function _encodeNodeOperatorId(
        uint256 noId
    ) internal pure returns (bytes memory) {
        // Node operator ids are sequential and bounded (< 2^32), so squeezing into 64 bits matches production encoding.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes.concat(bytes8(uint64(noId)));
    }

    function _encodeNodeOperatorPair(
        uint256 firstNoId,
        uint256 secondNoId
    ) internal pure returns (bytes memory) {
        // Both ids share the same bound, letting us pack them into 16 bytes.
        // forge-lint: disable-next-item(unsafe-typecast)
        return
            bytes.concat(bytes8(uint64(firstNoId)), bytes8(uint64(secondNoId)));
    }

    function _encodeUint128Value(
        uint256 value
    ) internal pure returns (bytes memory) {
        // Test amounts are tiny (< 2 ether or a handful of keys) and trivially fit in 128 bits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes.concat(bytes16(uint128(value)));
    }

    function randomBytes(uint256 length) public returns (bytes memory b) {
        b = new bytes(length);

        for (;;) {
            bytes32 buf = keccak256(abi.encodePacked(seed));
            seed = buf;

            for (uint256 i = 0; i < 32; i++) {
                if (length == 0) {
                    return b;
                }
                length--;
                b[length] = buf[i];
            }
        }
    }

    function someBytes32() public returns (bytes32) {
        bytes32 buf = keccak256(abi.encodePacked(seed));
        seed = buf;
        return buf;
    }

    function someCIDv0() public returns (string memory result) {
        bytes memory CIDSeed = randomBytes(46);

        CIDSeed[0] = "Q";
        CIDSeed[1] = "m";

        for (uint256 i = 2; i < CIDSeed.length; ++i) {
            uint256 symIndex = uint8(CIDSeed[i]) % 58;
            CIDSeed[i] = BASE58ALPHABET[symIndex];
        }

        result = string(CIDSeed);
    }

    function checkChainId(uint256 chainId) public view {
        if (chainId != block.chainid) {
            revert("wrong chain id");
        }
    }

    function expectNoCall(address where, bytes memory data) internal {
        vm.expectCall(where, data, 0);
    }

    function expectRoleRevert(address account, bytes32 neededRole) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                account,
                neededRole
            )
        );
    }

    /// @dev It's super annoying to make a memory array all the time without an array literal, so the function pretends
    /// to provide the familiar syntax. By overloading the function, we can have a different number of arguments.
    function UintArr() public pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function UintArr(uint256 e0) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = e0;
        return arr;
    }

    function UintArr(
        uint256 e0,
        uint256 e1
    ) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = e0;
        arr[1] = e1;
        return arr;
    }

    function UintArr(
        uint256 e0,
        uint256 e1,
        uint256 e2
    ) public pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = e0;
        arr[1] = e1;
        arr[2] = e2;
        return arr;
    }

    function slice(
        bytes memory subject,
        uint256 offset,
        uint256 length
    ) public pure returns (bytes memory result) {
        result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = subject[offset + i];
        }
    }

    function shuffle(uint256[] memory arr) public {
        if (arr.length < 2) return;

        for (uint256 i = arr.length - 1; i > 0; i--) {
            uint256 j = uint256(someBytes32()) % (i + 1);
            (arr[i], arr[j]) = (arr[j], arr[i]);
        }
    }

    /// See https://github.com/Vectorized/solady - MIT licensed.
    /// @dev Fills the memory with junk, for more robust testing of inline assembly
    /// which reads/write to the memory.
    function _brutalizeMemory() private view {
        // To prevent a solidity 0.8.13 bug.
        // See: https://blog.soliditylang.org/2022/06/15/inline-assembly-memory-side-effects-bug
        // Basically, we need to access a solidity variable from the assembly to
        // tell the compiler that this assembly block is not in isolation.
        uint256 zero;
        assembly ("memory-safe") {
            let offset := mload(0x40) // Start the offset at the free memory pointer.
            calldatacopy(offset, zero, calldatasize())

            // Fill the 64 bytes of scratch space with garbage.
            mstore(zero, add(caller(), gas()))
            mstore(0x20, keccak256(offset, calldatasize()))
            mstore(zero, keccak256(zero, 0x40))

            let r0 := mload(zero)
            let r1 := mload(0x20)

            let cSize := add(codesize(), iszero(codesize()))
            if iszero(lt(cSize, 32)) {
                cSize := sub(cSize, and(mload(0x02), 0x1f))
            }
            let start := mod(mload(0x10), cSize)
            let size := mul(sub(cSize, start), gt(cSize, start))
            let times := div(0x7ffff, cSize)
            if iszero(lt(times, 128)) {
                times := 128
            }

            // Occasionally offset the offset by a pseudorandom large amount.
            // Can't be too large, or we will easily get out-of-gas errors.
            offset := add(offset, mul(iszero(and(r1, 0xf)), and(r0, 0xfffff)))

            // Fill the free memory with garbage.
            // prettier-ignore
            for { let w := not(0) } 1 {} {
                mstore(offset, r0)
                mstore(add(offset, 0x20), r1)
                offset := add(offset, 0x40)
                // We use codecopy instead of the identity precompile
                // to avoid polluting the `forge test -vvvv` output with tons of junk.
                codecopy(offset, start, size)
                codecopy(add(offset, size), 0, start)
                offset := add(offset, cSize)
                times := add(times, w) // `sub(times, 1)`.
                if iszero(times) { break }
            }
        }
    }

    /// See https://github.com/Vectorized/solady - MIT licensed.
    /// @dev Check if the free memory pointer and the zero slot are not contaminated.
    /// Useful for cases where these slots are used for temporary storage.
    function _checkMemory() internal pure {
        bool zeroSlotIsNotZero;
        bool freeMemoryPointerOverflowed;
        assembly ("memory-safe") {
            // Write ones to the free memory, to make subsequent checks fail if
            // insufficient memory is allocated.
            mstore(mload(0x40), not(0))
            // Test at a lower, but reasonable limit for more safety room.
            if gt(mload(0x40), 0xffffffff) {
                freeMemoryPointerOverflowed := 1
            }
            // Check the value of the zero slot.
            zeroSlotIsNotZero := mload(0x60)
        }
        if (freeMemoryPointerOverflowed) {
            revert FreeMemoryPointerOverflowed();
        }

        if (zeroSlotIsNotZero) {
            revert ZeroSlotIsNotZero();
        }
    }

    /// See https://github.com/Vectorized/solady - MIT licensed.
    /// @dev Fills the memory with junk, for more robust testing of inline assembly
    /// which reads/write to the memory.
    modifier brutalizeMemory() {
        _brutalizeMemory();
        _;
        _checkMemory();
    }
}

function hasLog(Vm.Log[] memory self, bytes32 topic) pure returns (bool) {
    for (uint256 i = 0; i < self.length; ++i) {
        if (self[i].topics[0] == topic) {
            return true;
        }
    }

    return false;
}
