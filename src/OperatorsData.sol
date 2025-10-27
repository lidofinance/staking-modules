// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IOperatorsData, OperatorInfo } from "./interfaces/IOperatorsData.sol";
import { INodeOperatorOwner } from "./interfaces/INodeOperatorOwner.sol";

/// @notice Operators metadata storage
contract OperatorsData is AccessControl, IOperatorsData {
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    mapping(address module => mapping(uint256 id => OperatorInfo))
        internal _operators;
    mapping(address module => mapping(uint256 id => bool))
        internal _ownerRestrictions;

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IOperatorsData
    function set(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external onlyRole(SETTER_ROLE) {
        _setWithExistenceCheck(module, nodeOperatorId, name, description);
    }

    /// @inheritdoc IOperatorsData
    function setByOwner(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        if (module == address(0)) revert ZeroModuleAddress();
        address owner = INodeOperatorOwner(module).getNodeOperatorOwner(
            nodeOperatorId
        );
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert NotOwner();
        if (_ownerRestrictions[module][nodeOperatorId])
            revert OwnerEditsRestricted();
        _set(module, nodeOperatorId, name, description);
    }

    /// @inheritdoc IOperatorsData
    function get(
        address module,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        if (module == address(0)) revert ZeroModuleAddress();
        return _operators[module][nodeOperatorId];
    }

    /// @inheritdoc IOperatorsData
    function setOwnerRestriction(
        address module,
        uint256 nodeOperatorId,
        bool restricted
    ) external onlyRole(SETTER_ROLE) {
        _setRestriction(module, nodeOperatorId, restricted);
    }

    /// @inheritdoc IOperatorsData
    function isOwnerRestricted(
        address module,
        uint256 nodeOperatorId
    ) external view returns (bool) {
        if (module == address(0)) revert ZeroModuleAddress();
        return _ownerRestrictions[module][nodeOperatorId];
    }

    function _setWithExistenceCheck(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) internal {
        if (!_exists(module, nodeOperatorId)) revert NodeOperatorDoesNotExist();
        _set(module, nodeOperatorId, name, description);
    }

    function _set(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) internal {
        if (module == address(0)) revert ZeroModuleAddress();
        OperatorInfo storage info = _operators[module][nodeOperatorId];
        info.name = name;
        info.description = description;
        emit OperatorDataSet(module, nodeOperatorId, name, description);
    }

    function _exists(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (bool) {
        if (module == address(0)) revert ZeroModuleAddress();
        return
            nodeOperatorId < INodeOperatorOwner(module).getNodeOperatorsCount();
    }

    function _setRestriction(
        address module,
        uint256 nodeOperatorId,
        bool restricted
    ) internal {
        if (!_exists(module, nodeOperatorId)) revert NodeOperatorDoesNotExist();
        _ownerRestrictions[module][nodeOperatorId] = restricted;
        emit OwnerRestrictionUpdated(module, nodeOperatorId, restricted);
    }
}
