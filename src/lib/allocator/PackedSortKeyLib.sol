// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

/// @notice Packed sort key used for ordering operators by imbalance.
/// @dev Layout:
///      - high 224 bits: imbalance
///      - low 32 bits: reversed index (`INDEX_MASK - idx`) so lower original index wins ties.
///      Assumes `idx <= type(uint32).max`.
type PackedSortKey is uint256;

/// @notice Helper functions to pack and unpack `PackedSortKey`.
library PackedSortKeyLib {
    uint256 internal constant INDEX_BITS = 32;
    uint256 internal constant INDEX_MASK = type(uint32).max;

    /// @notice Packs imbalance and index into a single sortable key.
    /// @dev Sorting packed keys in descending order produces:
    ///      - imbalance descending
    ///      - index ascending on equal imbalance.
    /// @param imbalance Operator imbalance value.
    /// @param idx Operator index in the source arrays.
    /// @return key Packed key.
    function pack(uint256 imbalance, uint256 idx) internal pure returns (PackedSortKey key) {
        key = PackedSortKey.wrap((imbalance << INDEX_BITS) | (INDEX_MASK - idx));
    }

    /// @notice Unpacks the original operator index from a packed key.
    /// @param key Packed key.
    /// @return idx Original operator index.
    function unpackIndex(PackedSortKey key) internal pure returns (uint256 idx) {
        idx = INDEX_MASK - (PackedSortKey.unwrap(key) & INDEX_MASK);
    }

    /// @notice Unpacks imbalance from a packed key.
    /// @param key Packed key.
    /// @return imbalance Imbalance value.
    function unpackImbalance(PackedSortKey key) internal pure returns (uint256 imbalance) {
        imbalance = PackedSortKey.unwrap(key) >> INDEX_BITS;
    }

    /// @notice Reinterprets a packed key array as uint256[].
    /// @dev `PackedSortKey` wraps `uint256`, so both arrays have identical in-memory layout.
    ///      Useful for passing keys to helpers that accept `uint256[]` (e.g. `Arrays.sort`).
    /// @param keys Packed key array.
    /// @return out Same array viewed as uint256[].
    function asUint256Array(PackedSortKey[] memory keys) internal pure returns (uint256[] memory out) {
        assembly ("memory-safe") {
            out := keys
        }
    }
}
