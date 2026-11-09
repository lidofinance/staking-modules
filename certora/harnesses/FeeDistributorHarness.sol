// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { FeeDistributor } from "../../src/FeeDistributor.sol";

/// @notice Read-only helpers for verifying the unchanged FeeDistributor code.
/// @dev No production method is overridden and no storage setter is exposed.
///      Constructor-disabled initializers are preserved. Transition rules start
///      from explicit arbitrary-state preconditions, not a claimed proxy init proof.
contract FeeDistributorHarness is FeeDistributor {
    constructor(address stETH, address accounting, address oracle) FeeDistributor(stETH, accounting, oracle) {}

    /// @notice Constructs an actual OpenZeppelin-compatible two-leaf root.
    /// @dev The CVL distribution rules cover exactly one proof sibling. The real
    ///      MerkleProof.verifyCalldata executes; no Merkle validity summary is used.
    function rootForOneSibling(
        uint256 nodeOperatorId,
        uint256 shares,
        bytes32 sibling
    ) external pure returns (bytes32) {
        bytes32 leaf = hashLeaf(nodeOperatorId, shares);
        return leaf < sibling ? keccak256(abi.encodePacked(leaf, sibling)) : keccak256(abi.encodePacked(sibling, leaf));
    }

    /// @notice Reads the stored tree CID length without copying its contents.
    function treeCidLength() external view returns (uint256) {
        return bytes(treeCid).length;
    }

    /// @notice Reads the stored log CID length without copying its contents.
    function logCidLength() external view returns (uint256) {
        return bytes(logCid).length;
    }

    /// @notice Exposes history scalar fields without copying the dynamic CID fields.
    function historyRefSlot(uint256 index) external view returns (uint256) {
        return _distributionDataHistory[index].refSlot;
    }

    /// @notice Exposes the root persisted in a history entry.
    function historyTreeRoot(uint256 index) external view returns (bytes32) {
        return _distributionDataHistory[index].treeRoot;
    }

    /// @notice Exposes the distributed amount persisted in a history entry.
    function historyDistributed(uint256 index) external view returns (uint256) {
        return _distributionDataHistory[index].distributed;
    }

    /// @notice Exposes the rebate persisted in a history entry.
    function historyRebate(uint256 index) external view returns (uint256) {
        return _distributionDataHistory[index].rebate;
    }

    /// @notice Reads a historical tree CID length without copying its contents.
    function historyTreeCidLength(uint256 index) external view returns (uint256) {
        return bytes(_distributionDataHistory[index].treeCid).length;
    }

    /// @notice Reads a historical log CID length without copying its contents.
    function historyLogCidLength(uint256 index) external view returns (uint256) {
        return bytes(_distributionDataHistory[index].logCid).length;
    }
}
