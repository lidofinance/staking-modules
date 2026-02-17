// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IMerkleGateFactory {
    event MerkleGateCreated(address indexed gate, address indexed implementation, address indexed admin);

    error ZeroImplementationAddress();

    /// @dev Address of the gate implementation used for new instances.
    function GATE_IMPL() external view returns (address);

    /// @notice Creates a new gate proxy for the predefined implementation.
    /// @param initCalldata Initialization calldata delegated in proxy constructor.
    /// @param admin Address of the proxy admin.
    /// @return instance Address of the created proxy instance.
    function create(bytes calldata initCalldata, address admin) external returns (address instance);
}
