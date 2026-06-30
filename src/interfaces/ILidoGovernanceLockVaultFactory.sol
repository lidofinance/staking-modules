// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IERC20LockVaultFactory } from "./IERC20LockVaultFactory.sol";

/// @notice Factory and runtime governance config for Lido governance lock vaults.
interface ILidoGovernanceLockVaultFactory is IERC20LockVaultFactory {
    event SnapshotDelegationSet(address snapshotDelegation);

    error SameSnapshotDelegation();

    /// @notice Lido Aragon Voting contract used by created vaults.
    function VOTING_CONTRACT() external view returns (address);

    /// @notice Snapshot delegation registry used by created vaults.
    function snapshotDelegation() external view returns (address);

    /// @notice Set Snapshot delegation registry used by all created vaults.
    /// @param snapshotDelegation New Snapshot delegation registry.
    function setSnapshotDelegation(address snapshotDelegation) external;
}
