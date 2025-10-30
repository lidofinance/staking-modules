// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IOperatorsData, OperatorInfo } from "./interfaces/IOperatorsData.sol";
import { INodeOperatorOwner } from "./interfaces/INodeOperatorOwner.sol";
import { IStakingRouter } from "./interfaces/IStakingRouter.sol";

/// @notice Operators metadata storage
contract OperatorsData is
    Initializable,
    AccessControlUpgradeable,
    IOperatorsData
{
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    mapping(address module => mapping(uint256 id => OperatorInfo))
        internal _operators;
    mapping(address module => bool) internal _knownModules;

    IStakingRouter public immutable STAKING_ROUTER;

    constructor(address stakingRouter) {
        if (stakingRouter == address(0)) revert ZeroStakingRouterAddress();
        STAKING_ROUTER = IStakingRouter(payable(stakingRouter));
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IOperatorsData
    function set(
        address module,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external onlyRole(SETTER_ROLE) {
        _ensureKnownModule(module);
        if (!_exists(module, nodeOperatorId)) revert NodeOperatorDoesNotExist();

        OperatorInfo storage stored = _operators[module][nodeOperatorId];
        stored.name = info.name;
        stored.description = info.description;
        stored.ownerRestricted = info.ownerRestricted;

        emit OperatorDataSet({
            module: module,
            nodeOperatorId: nodeOperatorId,
            name: stored.name,
            description: stored.description,
            ownerRestricted: stored.ownerRestricted
        });
    }

    /// @inheritdoc IOperatorsData
    function setByOwner(
        address module,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        _ensureKnownModule(module);
        address owner = INodeOperatorOwner(module).getNodeOperatorOwner(
            nodeOperatorId
        );
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert NotOwner();
        OperatorInfo storage stored = _operators[module][nodeOperatorId];
        if (stored.ownerRestricted) revert OwnerEditsRestricted();

        stored.name = name;
        stored.description = description;

        emit OperatorDataSet({
            module: module,
            nodeOperatorId: nodeOperatorId,
            name: stored.name,
            description: stored.description,
            ownerRestricted: stored.ownerRestricted
        });
    }

    /// @inheritdoc IOperatorsData
    function get(
        address module,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        _checkModule(module);
        return _operators[module][nodeOperatorId];
    }

    /// @inheritdoc IOperatorsData
    function isOwnerRestricted(
        address module,
        uint256 nodeOperatorId
    ) external view returns (bool) {
        _checkModule(module);
        return _operators[module][nodeOperatorId].ownerRestricted;
    }

    function _ensureKnownModule(address module) internal {
        _checkModule(module);
        if (!_knownModules[module]) {
            _knownModules[module] = true;
        }
    }

    function _exists(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (bool) {
        if (module == address(0)) revert ZeroModuleAddress();
        return
            nodeOperatorId < INodeOperatorOwner(module).getNodeOperatorsCount();
    }

    function _checkModule(address module) internal view {
        if (module == address(0)) revert ZeroModuleAddress();
        if (_knownModules[module]) return;
        if (!_moduleExists(module)) revert UnknownModule();
    }

    function _moduleExists(address module) internal view returns (bool) {
        IStakingRouter.StakingModule[] memory modules = STAKING_ROUTER
            .getStakingModules();
        uint256 length = modules.length;
        for (uint256 i = 0; i < length; ++i) {
            if (modules[i].stakingModuleAddress == module) {
                return true;
            }
        }
        return false;
    }
}
