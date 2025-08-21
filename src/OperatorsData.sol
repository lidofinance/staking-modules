// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IOperatorsData, OperatorInfo } from "./interfaces/IOperatorsData.sol";
import { ICuratedModule } from "./interfaces/ICuratedModule.sol";

/// @notice Operators metadata storage
contract OperatorsData is AccessControl, IOperatorsData {
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    mapping(uint256 id => OperatorInfo) internal _operators;

    ICuratedModule public immutable MODULE;

    constructor(address module, address admin) {
        if (admin == address(0)) revert ZeroAdminAddress();
        if (module == address(0)) revert ZeroModuleAddress();
        MODULE = ICuratedModule(module);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IOperatorsData
    function set(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external onlyRole(SETTER_ROLE) {
        _setWithExistenceCheck(nodeOperatorId, name, description);
    }

    /// @inheritdoc IOperatorsData
    function setByOwner(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert NotOwner();
        _set(nodeOperatorId, name, description);
    }

    /// @inheritdoc IOperatorsData
    function get(
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        return _operators[nodeOperatorId];
    }

    function _setWithExistenceCheck(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) internal {
        if (!_exists(nodeOperatorId)) revert NodeOperatorDoesNotExist();
        _set(nodeOperatorId, name, description);
    }

    function _set(
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) internal {
        OperatorInfo storage info = _operators[nodeOperatorId];
        info.name = name;
        info.description = description;
        emit OperatorDataSet(nodeOperatorId, name, description);
    }

    function _exists(uint256 nodeOperatorId) internal view returns (bool) {
        return nodeOperatorId < MODULE.getNodeOperatorsCount();
    }
}
