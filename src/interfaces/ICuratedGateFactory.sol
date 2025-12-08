// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface ICuratedGateFactory {
    event CuratedGateCreated(address indexed gate);

    error ZeroImplementationAddress();

    /// @dev Address of the CuratedGate implementation to be used for the new instances
    /// @return address of the CuratedGate implementation
    function CURATED_GATE_IMPL() external view returns (address);

    /// @dev Creates a new CuratedGate instance behind the OssifiableProxy based on known implementation address
    /// @param curveId Id of the bond curve to be assigned for the eligible members
    /// @param treeRoot Root of the eligible members Merkle Tree
    /// @param treeCid CID of the eligible members Merkle Tree
    /// @param admin Address of the admin role
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance);
}
