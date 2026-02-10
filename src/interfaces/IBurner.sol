// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IBurner {
    function REQUEST_BURN_SHARES_ROLE() external view returns (bytes32);

    function REQUEST_BURN_MY_STETH_ROLE() external view returns (bytes32);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function requestBurnMyShares(uint256 _sharesAmountToBurn) external;
}
