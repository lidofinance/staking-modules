// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
// Backported from lidofinance/core except for removed functions
// Source: https://github.com/lidofinance/core/blob/0d4231ee8a5289248e49e96747d6b95fa5b0afcc/test/0.8.9/unstructuredStorage.t.sol
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { UnstructuredStorage } from "src/lib/UnstructuredStorage.sol";

contract ExposedUnstructuredStorageTest is Test {
    ExposedUnstructuredStorage public unstructuredStorage;

    function setUp() public {
        unstructuredStorage = new ExposedUnstructuredStorage();
    }

    function test_getStorageAddress_Uninitialized() public view {
        bytes32 position = keccak256("FOO");
        assertEq(unstructuredStorage.getStorageAddress(position), address(0));
    }

    /**
     * https://book.getfoundry.sh/reference/config/inline-test-config#in-line-fuzz-configs
     * forge-config: default.fuzz.runs = 2048
     * forge-config: default.fuzz.max-test-rejects = 0
     */
    function testFuzz_getStorageAddress_Uninitialized(
        bytes32 position
    ) public view {
        assertEq(unstructuredStorage.getStorageAddress(position), address(0));
    }

    function test_getStorageUint256_Uninitialized() public view {
        bytes32 position = keccak256("FOO");
        uint256 data;
        assertEq(unstructuredStorage.getStorageUint256(position), data);
    }

    /**
     * https://book.getfoundry.sh/reference/config/inline-test-config#in-line-fuzz-configs
     * forge-config: default.fuzz.runs = 2048
     * forge-config: default.fuzz.max-test-rejects = 0
     */
    function testFuzz_getStorageUint256_Uninitialized(
        bytes32 position
    ) public view {
        uint256 data;
        assertEq(unstructuredStorage.getStorageUint256(position), data);
    }

    function test_setStorageAddress() public {
        bytes32 position = keccak256("FOO");
        address data = vm.addr(1);

        assertEq(unstructuredStorage.getStorageAddress(position), address(0));
        unstructuredStorage.setStorageAddress(position, data);
        assertEq(unstructuredStorage.getStorageAddress(position), data);
    }

    /**
     * https://book.getfoundry.sh/reference/config/inline-test-config#in-line-fuzz-configs
     * forge-config: default.fuzz.runs = 2048
     * forge-config: default.fuzz.max-test-rejects = 0
     */
    function testFuzz_setStorageAddress(address data, bytes32 position) public {
        assertEq(unstructuredStorage.getStorageAddress(position), address(0));
        unstructuredStorage.setStorageAddress(position, data);
        assertEq(unstructuredStorage.getStorageAddress(position), data);
    }

    function test_setStorageUint256() public {
        bytes32 position = keccak256("FOO");
        uint256 data = 1;
        uint256 unInitializedData;

        assertEq(
            unstructuredStorage.getStorageUint256(position),
            unInitializedData
        );
        unstructuredStorage.setStorageUint256(position, data);
        assertEq(unstructuredStorage.getStorageUint256(position), data);
    }

    /**
     * https://book.getfoundry.sh/reference/config/inline-test-config#in-line-fuzz-configs
     * forge-config: default.fuzz.runs = 2048
     * forge-config: default.fuzz.max-test-rejects = 0
     */
    function testFuzz_setStorageUint256(uint256 data, bytes32 position) public {
        uint256 unInitializedData;

        assertEq(
            unstructuredStorage.getStorageUint256(position),
            unInitializedData
        );
        unstructuredStorage.setStorageUint256(position, data);
        assertEq(unstructuredStorage.getStorageUint256(position), data);
    }
}

contract ExposedUnstructuredStorage {
    function getStorageAddress(bytes32 position) public view returns (address) {
        return UnstructuredStorage.getStorageAddress(position);
    }

    function getStorageUint256(bytes32 position) public view returns (uint256) {
        return UnstructuredStorage.getStorageUint256(position);
    }

    function setStorageAddress(bytes32 position, address data) public {
        return UnstructuredStorage.setStorageAddress(position, data);
    }

    function setStorageUint256(bytes32 position, uint256 data) public {
        return UnstructuredStorage.setStorageUint256(position, data);
    }
}
