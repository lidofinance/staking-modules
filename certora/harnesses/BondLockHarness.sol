// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BondLock } from "../../src/abstract/BondLock.sol";

/// @notice Verification-only entrypoints for the production BondLock implementation.
/// @dev These entrypoints deliberately omit Accounting's authorization and settlement logic.
///      There are no arbitrary storage setters. Each transition calls the original implementation.
contract BondLockHarness is BondLock(1, type(uint64).max) {
    /// @notice Initialize the production lock period.
    function initialize(uint256 period) external initializer {
        __BondLock_init(period);
    }

    /// @notice Exercise the production period update independently of caller authorization.
    function setPeriod(uint256 period) external {
        _setBondLockPeriod(period);
    }

    /// @notice Exercise creation, extension, and replacement of a lock.
    function lock(uint256 nodeOperatorId, uint256 amount) external {
        _lock(nodeOperatorId, amount);
    }

    /// @notice Exercise partial or full unlock without changing the nonce.
    function unlock(uint256 nodeOperatorId, uint256 amount) external {
        _unlock(nodeOperatorId, amount);
    }

    /// @notice Exercise removal of an expired lock.
    function unlockExpired(uint256 nodeOperatorId) external {
        _unlockExpiredLock(nodeOperatorId);
    }

    /// @notice Expose the original struct getter as a scalar for CVL rules.
    function lockUntil(uint256 nodeOperatorId) external view returns (uint256) {
        return this.getLockedBondInfo(nodeOperatorId).until;
    }
}
