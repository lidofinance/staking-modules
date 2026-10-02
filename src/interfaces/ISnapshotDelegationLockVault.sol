// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Optional Snapshot delegation capability for an ERC20 lock vault.
interface ISnapshotDelegationLockVault {
    error ZeroSnapshotDelegationAddress();

    /// @notice Snapshot delegation registry used by this vault.
    function snapshotDelegation() external view returns (address);

    /// @notice Assign a Snapshot delegate from the vault address for all spaces.
    /// @param snapshotDelegate Address to assign as delegate.
    function assignSnapshotDelegate(address snapshotDelegate) external;

    /// @notice Remove the current Snapshot delegate from the vault address for all spaces.
    function unassignSnapshotDelegate() external;
}
