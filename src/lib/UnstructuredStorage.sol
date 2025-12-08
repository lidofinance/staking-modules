/*
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.31;

/**
 * @notice Aragon Unstructured Storage library
 */
library UnstructuredStorage {
    function setStorageAddress(bytes32 position, address data) internal {
        assembly {
            sstore(position, data)
        }
    }

    function setStorageUint256(bytes32 position, uint256 data) internal {
        assembly {
            sstore(position, data)
        }
    }

    function getStorageAddress(
        bytes32 position
    ) internal view returns (address data) {
        assembly {
            data := sload(position)
        }
    }

    function getStorageUint256(
        bytes32 position
    ) internal view returns (uint256 data) {
        assembly {
            data := sload(position)
        }
    }
}
