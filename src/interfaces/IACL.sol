// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IACL {
    function grantPermission(
        address _entity,
        address _app,
        bytes32 _role
    ) external;

    function getPermissionManager(
        address _app,
        bytes32 _role
    ) external view returns (address);
}
