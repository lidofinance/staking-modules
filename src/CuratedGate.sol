// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";
import { PausableUntil } from "./lib/utils/PausableUntil.sol";

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { IMerkleGate } from "./interfaces/IMerkleGate.sol";
import { ICuratedGate } from "./interfaces/ICuratedGate.sol";
import { NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IOperatorsData, OperatorInfo } from "./interfaces/IOperatorsData.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";

/// @notice Merkle gate for Curated Module v2
contract CuratedGate is
    ICuratedGate,
    AccessControlEnumerableUpgradeable,
    PausableUntil,
    AssetRecoverer
{
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");
    bytes32 public constant SET_TREE_ROLE = keccak256("SET_TREE_ROLE");

    /// @inheritdoc ICuratedGate
    ICuratedModule public immutable MODULE;

    /// @inheritdoc ICuratedGate
    uint256 public immutable MODULE_ID;

    /// @inheritdoc ICuratedGate
    IAccounting public immutable ACCOUNTING;

    /// @inheritdoc ICuratedGate
    IOperatorsData public immutable OPERATORS_DATA;

    /// @inheritdoc IMerkleGate
    bytes32 public treeRoot;

    /// @inheritdoc IMerkleGate
    string public treeCid;

    /// @inheritdoc ICuratedGate
    uint256 public curveId;

    bool internal _defaultCurveSet;

    /// @dev Tracks whether an address already consumed its eligibility
    mapping(address => bool) internal _consumedAddresses;

    constructor(address module, uint256 moduleId, address operatorsData) {
        if (module == address(0)) revert ZeroModuleAddress();
        if (moduleId == 0) revert ZeroModuleId();
        if (operatorsData == address(0)) revert ZeroOperatorsDataAddress();
        MODULE = ICuratedModule(module);
        MODULE_ID = moduleId;
        ACCOUNTING = MODULE.ACCOUNTING();
        OPERATORS_DATA = IOperatorsData(operatorsData);
        _disableInitializers();
    }

    function initialize(
        uint256 _curveId,
        bytes32 _treeRoot,
        string calldata _treeCid,
        address admin
    ) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();

        __AccessControlEnumerable_init();
        curveId = _curveId;
        if (_curveId == ACCOUNTING.DEFAULT_BOND_CURVE_ID()) {
            _defaultCurveSet = true;
        }
        _setTreeParams(_treeRoot, _treeCid);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc ICuratedGate
    function resume() external onlyRole(RESUME_ROLE) {
        _resume();
    }

    /// @inheritdoc ICuratedGate
    function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE) {
        _pauseFor(duration);
    }

    /// @inheritdoc ICuratedGate
    function createNodeOperator(
        string calldata name,
        string calldata description,
        address managerAddress,
        address rewardAddress,
        bytes32[] calldata proof
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        // Enforce extendedManagerPermissions = true; accept manager/reward from args
        NodeOperatorManagementProperties
            memory props = NodeOperatorManagementProperties({
                managerAddress: managerAddress,
                rewardAddress: rewardAddress,
                extendedManagerPermissions: true
            });

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: props,
            referrer: address(0)
        });

        // Apply instance-specific custom curve
        if (!_defaultCurveSet) {
            ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        }

        // Persist metadata in separate storage
        OperatorInfo memory metadata = OperatorInfo({
            name: name,
            description: description,
            ownerEditsRestricted: false
        });

        OPERATORS_DATA.set(MODULE_ID, nodeOperatorId, metadata);
    }

    /// @inheritdoc IMerkleGate
    function setTreeParams(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) external onlyRole(SET_TREE_ROLE) {
        _setTreeParams(_treeRoot, _treeCid);
    }

    /// @inheritdoc IMerkleGate
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IMerkleGate
    function isConsumed(address member) public view returns (bool) {
        return _consumedAddresses[member];
    }

    /// @inheritdoc IMerkleGate
    function verifyProof(
        address member,
        bytes32[] calldata proof
    ) public view returns (bool) {
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

    function _setTreeParams(
        bytes32 _treeRoot,
        string calldata _treeCid
    ) internal {
        if (_treeRoot == bytes32(0)) revert InvalidTreeRoot();
        if (_treeRoot == treeRoot) revert InvalidTreeRoot();
        if (bytes(_treeCid).length == 0) revert InvalidTreeCid();
        if (keccak256(bytes(_treeCid)) == keccak256(bytes(treeCid)))
            revert InvalidTreeCid();
        treeRoot = _treeRoot;
        treeCid = _treeCid;
        emit TreeSet(_treeRoot, _treeCid);
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }
}
