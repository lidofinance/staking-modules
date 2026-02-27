// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { PausableUntil } from "../lib/utils/PausableUntil.sol";

import { IPausableWithRoles } from "../interfaces/IPausableWithRoles.sol";

/// @title PausableWithRoles
/// @dev Abstract contract providing mechanisms for pausing and resuming contract functions based on roles.
/// @notice Functions can be paused and resumed only by the authorized roles
abstract contract PausableWithRoles is IPausableWithRoles, PausableUntil {
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");

    /// @inheritdoc IPausableWithRoles
    function resume() external {
        __checkRole(RESUME_ROLE);
        _resume();
    }

    /// @inheritdoc IPausableWithRoles
    function pauseFor(uint256 duration) external {
        __checkRole(PAUSE_ROLE);
        _pauseFor(duration);
    }

    /// @dev Internal function to check if the caller has the required role.
    /// @param role The role to check against the caller's permissions.
    function __checkRole(bytes32 role) internal view virtual;
}
