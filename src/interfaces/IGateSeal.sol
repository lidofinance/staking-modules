// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IGateSeal {
    function get_sealing_committee() external view returns (address);

    function get_seal_duration_seconds() external view returns (uint256);

    function get_sealables() external view returns (address[] memory);

    function get_expiry_timestamp() external view returns (uint256);

    function is_expired() external view returns (bool);

    function seal(address[] memory _sealables) external;
}
