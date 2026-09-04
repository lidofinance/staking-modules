// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Snapshot delegation registry interface used by token lock vaults.
interface ISnapshotDelegation {
    /// @notice Set msg.sender's Snapshot delegate for a space.
    /// @param id Snapshot space ID. Zero ID means all spaces.
    /// @param delegate Address to assign as delegate.
    function setDelegate(bytes32 id, address delegate) external;

    /// @notice Clear msg.sender's Snapshot delegate for a space.
    /// @param id Snapshot space ID. Zero ID means all spaces.
    function clearDelegate(bytes32 id) external;
}
