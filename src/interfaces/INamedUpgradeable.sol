// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @title Named Upgradeable Interface
/// @notice Common surface for contracts with an upgrade-safe human-readable name.
interface INamedUpgradeable {
    /// @notice Emitted when the display name is set
    /// @param name Human-readable name
    event NameSet(string name);

    error InvalidName();

    /// @return name Human-readable name
    function name() external view returns (string memory);

    /// @notice Update the human-readable name
    /// @param name New name
    function setName(string calldata name) external;
}
