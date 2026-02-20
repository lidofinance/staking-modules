// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IPausableWithRoles {
    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    /// @notice Resumes the contract functions that were previously paused.
    /// @dev Can only be called by an account with the RESUME_ROLE.
    function resume() external;

    /// @notice Pauses the contract functions for a specified duration.
    /// @param duration The duration (in seconds) for which the contract functions should be paused.
    /// @dev Can only be called by an account with the PAUSE_ROLE.
    function pauseFor(uint256 duration) external;
}
