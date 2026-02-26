// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

interface IMerkleGateFactory {
    event MerkleGateCreated(address indexed gate, address indexed admin, uint256 curveId);

    error ZeroImplementationAddress();

    /// @dev Address of the gate implementation used for new instances.
    function GATE_IMPL() external view returns (address);

    /// @notice Creates a new gate proxy for the predefined implementation and initializes it.
    /// @param curveId Bond curve id to assign to eligible members.
    /// @param treeRoot Initial Merkle tree root.
    /// @param treeCid Initial Merkle tree CID.
    /// @param admin Address of the proxy admin and DEFAULT_ADMIN_ROLE holder.
    /// @return instance Address of the created proxy instance.
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance);
}
