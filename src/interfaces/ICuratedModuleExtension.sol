// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { ICuratedModule } from "./ICuratedModule.sol";
import { IOperatorsData } from "./IOperatorsData.sol";
import { ICSAccounting } from "./ICSAccounting.sol";

/// @title Curated Module Extension Interface
/// @notice Allows eligible addresses to create Node Operators and store metadata.
interface ICuratedModuleExtension {
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
    error InvalidCurveId();
    error ZeroModuleAddress();
    error ZeroOperatorsDataAddress();
    error ZeroAdminAddress();

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    function SET_TREE_ROLE() external view returns (bytes32);

    /// @return MODULE Curated module reference
    function MODULE() external view returns (ICuratedModule);

    /// @return ACCOUNTING Accounting reference
    function ACCOUNTING() external view returns (ICSAccounting);

    /// @return OPERATORS_DATA Operators metadata storage reference
    function OPERATORS_DATA() external view returns (IOperatorsData);

    /// @return curveId Instance-specific custom curve id
    function curveId() external view returns (uint256);

    /// @return treeRoot Current Merkle tree root
    function treeRoot() external view returns (bytes32);

    /// @return treeCid Current Merkle tree CID
    function treeCid() external view returns (string memory);

    /// @notice Pause the extension for a given duration
    /// @param duration Duration in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Resume the extension
    function resume() external;

    /// @notice Create an empty Node Operator for the caller if eligible.
    ///         Stores provided name/description in OperatorsData. Marks caller as consumed.
    /// @param name Display name of the Node Operator
    /// @param description Description of the Node Operator
    /// @param managerAddress Address to set as manager; if zero, defaults will be used by the module
    /// @param rewardAddress Address to set as rewards receiver; if zero, defaults will be used by the module
    /// @param proof Merkle proof for the caller address
    /// @return nodeOperatorId Newly created Node Operator id
    function createNodeOperator(
        string calldata name,
        string calldata description,
        address managerAddress,
        address rewardAddress,
        bytes32[] calldata proof
    ) external returns (uint256 nodeOperatorId);

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
