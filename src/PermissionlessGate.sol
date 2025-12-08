// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { AssetRecoverer } from "./abstract/AssetRecoverer.sol";

import { IAccounting } from "./interfaces/IAccounting.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "./interfaces/IBaseModule.sol";
import { IPermissionlessGate } from "./interfaces/IPermissionlessGate.sol";

/// @title PermissionlessGate
/// @notice Contract for adding new Node Operators without any restrictions
contract PermissionlessGate is
    IPermissionlessGate,
    AccessControlEnumerable,
    AssetRecoverer
{
    bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE");

    /// @dev Curve ID is the default bond curve ID from the accounting contract
    ///      This immutable variable is kept here for consistency with the other gates
    uint256 public immutable CURVE_ID;

    /// @dev Address of the Staking Module
    IBaseModule public immutable MODULE;

    constructor(address module, address admin) {
        if (module == address(0)) {
            revert ZeroModuleAddress();
        }
        if (admin == address(0)) {
            revert ZeroAdminAddress();
        }

        MODULE = IBaseModule(module);
        CURVE_ID = MODULE.ACCOUNTING().DEFAULT_BOND_CURVE_ID();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IPermissionlessGate
    function addNodeOperatorETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        address referrer
    ) external payable returns (uint256 nodeOperatorId) {
        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });

        MODULE.addValidatorKeysETH{ value: msg.value }({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures
        });
    }

    /// @inheritdoc IPermissionlessGate
    function addNodeOperatorStETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        address referrer
    ) external returns (uint256 nodeOperatorId) {
        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });

        MODULE.addValidatorKeysStETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });
    }

    /// @inheritdoc IPermissionlessGate
    function addNodeOperatorWstETH(
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures,
        NodeOperatorManagementProperties calldata managementProperties,
        IAccounting.PermitInput calldata permit,
        address referrer
    ) external returns (uint256 nodeOperatorId) {
        nodeOperatorId = MODULE.createNodeOperator({
            from: msg.sender,
            managementProperties: managementProperties,
            referrer: referrer
        });

        MODULE.addValidatorKeysWstETH({
            from: msg.sender,
            nodeOperatorId: nodeOperatorId,
            keysCount: keysCount,
            publicKeys: publicKeys,
            signatures: signatures,
            permit: permit
        });
    }

    function _onlyRecoverer() internal view override {
        _checkRole(RECOVERER_ROLE);
    }
}
