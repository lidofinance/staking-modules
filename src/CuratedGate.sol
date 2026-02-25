// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICuratedModule } from "./interfaces/ICuratedModule.sol";
import { ICuratedGate } from "./interfaces/ICuratedGate.sol";
import { NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IMetaRegistry, OperatorMetadata } from "./interfaces/IMetaRegistry.sol";
import { IAccounting } from "./interfaces/IAccounting.sol";
import { IMerkleGate } from "./interfaces/IMerkleGate.sol";
import { MerkleGate } from "./abstract/MerkleGate.sol";

/// @notice Merkle gate for Curated Module
contract CuratedGate is ICuratedGate, MerkleGate {
    /// @inheritdoc ICuratedGate
    ICuratedModule public immutable MODULE;

    /// @inheritdoc ICuratedGate
    IAccounting public immutable ACCOUNTING;

    /// @notice Cached default bond curve id from Accounting.
    uint256 public immutable DEFAULT_BOND_CURVE_ID;

    /// @inheritdoc ICuratedGate
    IMetaRegistry public immutable META_REGISTRY;

    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();

        MODULE = ICuratedModule(module);
        ACCOUNTING = MODULE.ACCOUNTING();
        DEFAULT_BOND_CURVE_ID = ACCOUNTING.DEFAULT_BOND_CURVE_ID();
        META_REGISTRY = MODULE.META_REGISTRY();

        _disableInitializers();
    }

    /// @inheritdoc MerkleGate
    function initialize(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) public override(IMerkleGate, MerkleGate) initializer {
        super.initialize(curveId, treeRoot, treeCid, admin);
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
        NodeOperatorManagementProperties memory props = NodeOperatorManagementProperties({
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
        if (curveId != DEFAULT_BOND_CURVE_ID) ACCOUNTING.setBondCurve(nodeOperatorId, curveId);

        // Persist metadata in separate storage
        OperatorMetadata memory metadata = OperatorMetadata({
            name: name,
            description: description,
            ownerEditsRestricted: false
        });

        META_REGISTRY.setOperatorMetadataAsAdmin(nodeOperatorId, metadata);
    }
}
