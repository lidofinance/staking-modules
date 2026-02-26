// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IMerkleGate } from "./interfaces/IMerkleGate.sol";
import { IVettedGate } from "./interfaces/IVettedGate.sol";
import { MerkleGate } from "./abstract/MerkleGate.sol";

/// @notice Merkle gate for vetted/community members.
contract VettedGate is IVettedGate, MerkleGate {
    /// @dev Address of the Staking Module.
    IBaseModule public immutable MODULE;

    /// @dev Address of the Accounting.
    IAccounting public immutable ACCOUNTING;

    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();

        MODULE = IBaseModule(module);
        ACCOUNTING = IAccounting(MODULE.ACCOUNTING());

        _disableInitializers();
    }

    /// @inheritdoc MerkleGate
    function initialize(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) public override(IMerkleGate, MerkleGate) initializer {
        if (curveId == ACCOUNTING.DEFAULT_BOND_CURVE_ID()) revert InvalidCurveId();
        super.initialize(curveId, treeRoot, treeCid, admin);
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        bytes32[] calldata proof,
        address referrer
    ) external payable whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysETH{ value: msg.value }({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures
        });
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorStETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        bytes32[] calldata proof,
        address referrer
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysStETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });
    }

    /// @inheritdoc IVettedGate
    function addNodeOperatorWstETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        bytes32[] calldata proof,
        address referrer
    ) external whenResumed returns (uint256 nodeOperatorId) {
        _consume(proof);

        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });
        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
        MODULE.addValidatorKeysWstETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });
    }

    /// @inheritdoc IVettedGate
    function claimBondCurve(uint256 nodeOperatorId, bytes32[] calldata proof) external whenResumed {
        _onlyNodeOperatorOwner(nodeOperatorId);

        _consume(proof);

        ACCOUNTING.setBondCurve(nodeOperatorId, curveId);
    }

    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert NotAllowedToClaim();
    }
}
