// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

/// @title Merkle Gate Interface
/// @notice Common surface for gates that guard node operator creation via Merkle proofs.
interface IMerkleGate {
    /// @notice Emitted when a new Merkle tree is set
    /// @param treeRoot Root of the Merkle tree
    /// @param treeCid CID of the Merkle tree
    event TreeSet(bytes32 indexed treeRoot, string treeCid);

    /// @notice Emitted when a member consumes eligibility
    /// @param member Address that consumed eligibility
    event Consumed(address indexed member);

    /// Errors
    error InvalidProof();
    error AlreadyConsumed();
    error InvalidTreeRoot();
    error InvalidTreeCid();

    /// @return SET_TREE_ROLE role required to update tree parameters
    function SET_TREE_ROLE() external view returns (bytes32);

    /// @return treeRoot Current Merkle tree root
    function treeRoot() external view returns (bytes32);

    /// @return treeCid Current Merkle tree CID
    function treeCid() external view returns (string memory);

    /// @notice Update Merkle tree params
    /// @param _treeRoot New root
    /// @param _treeCid New CID
    function setTreeParams(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external;

    /// @notice Returns whether a member already consumed eligibility
    function isConsumed(address member) external view returns (bool);

    /// @notice Verify proof for a member against current tree
    function verifyProof(
        address member,
        bytes32[] calldata proof
    ) external view returns (bool);

    /// @notice Hash leaf encoding for addresses in the Merkle tree
    function hashLeaf(address member) external pure returns (bytes32);

    /// @notice Initialized version for upgradeable tooling
    function getInitializedVersion() external view returns (uint64);
}
