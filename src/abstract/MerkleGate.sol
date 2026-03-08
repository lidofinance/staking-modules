// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { AssetRecoverer } from "./AssetRecoverer.sol";
import { PausableWithRoles } from "./PausableWithRoles.sol";

import { IMerkleGate } from "../interfaces/IMerkleGate.sol";

/// @notice Shared Merkle-based gate logic for gated node-operator flows.
abstract contract MerkleGate is IMerkleGate, AccessControlEnumerableUpgradeable, PausableWithRoles, AssetRecoverer {
    bytes32 public constant SET_TREE_ROLE = keccak256("SET_TREE_ROLE");

    /// @notice Id of the bond curve to be assigned for eligible members.
    uint256 public curveId;

    /// @inheritdoc IMerkleGate
    bytes32 public treeRoot;

    /// @inheritdoc IMerkleGate
    string public treeCid;

    /// @dev Tracks whether an address already consumed its eligibility.
    mapping(address => bool) internal _consumedAddresses;

    /// @inheritdoc IMerkleGate
    function setTreeParams(bytes32 treeRoot_, string calldata treeCid_) external onlyRole(SET_TREE_ROLE) {
        _setTreeParams(treeRoot_, treeCid_);
    }

    /// @inheritdoc IMerkleGate
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IMerkleGate
    function initialize(
        uint256 curveId_,
        bytes32 treeRoot_,
        string calldata treeCid_,
        address admin
    ) public virtual onlyInitializing {
        if (admin == address(0)) revert ZeroAdminAddress();
        curveId = curveId_;
        _setTreeParams(treeRoot_, treeCid_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IMerkleGate
    function isConsumed(address member) public view returns (bool) {
        return _consumedAddresses[member];
    }

    /// @inheritdoc IMerkleGate
    function verifyProof(address member, bytes32[] calldata proof) public view returns (bool) {
        return MerkleProof.verifyCalldata(proof, treeRoot, hashLeaf(member));
    }

    /// @inheritdoc IMerkleGate
    function hashLeaf(address member) public pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(member))));
    }

    function _consume(bytes32[] calldata proof) internal {
        if (isConsumed(msg.sender)) revert AlreadyConsumed();
        if (!verifyProof(msg.sender, proof)) revert InvalidProof();

        _consumedAddresses[msg.sender] = true;
        emit Consumed(msg.sender);
    }

    function _setTreeParams(bytes32 treeRoot_, string calldata treeCid_) internal {
        if (treeRoot_ == bytes32(0)) revert InvalidTreeRoot();
        if (treeRoot_ == treeRoot) revert InvalidTreeRoot();
        if (bytes(treeCid_).length == 0) revert InvalidTreeCid();
        if (Strings.equal(treeCid_, treeCid)) revert InvalidTreeCid();

        treeRoot = treeRoot_;
        treeCid = treeCid_;

        emit TreeSet(treeRoot_, treeCid_);
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }

    function __checkRole(bytes32 role) internal view override {
        _checkRole(role);
    }
}
