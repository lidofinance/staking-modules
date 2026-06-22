// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

interface IPausableWithRoles {
    function PAUSE_ROLE() external view returns (bytes32);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
}
