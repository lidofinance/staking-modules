// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { IOperatorsData, OperatorInfo } from "./interfaces/IOperatorsData.sol";
import { INodeOperatorOwner } from "./interfaces/INodeOperatorOwner.sol";
import { IStakingRouter } from "./interfaces/IStakingRouter.sol";
import { IStakingModule } from "./interfaces/IStakingModule.sol";

/// @notice Operators metadata storage
contract OperatorsData is
    Initializable,
    AccessControlUpgradeable,
    IOperatorsData
{
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    mapping(uint256 moduleId => mapping(uint256 id => OperatorInfo))
        internal _operators;
    mapping(uint256 moduleId => address moduleAddress)
        internal _moduleAddresses;

    IStakingRouter public immutable STAKING_ROUTER;

    constructor(address stakingRouter) {
        if (stakingRouter == address(0)) revert ZeroStakingRouterAddress();
        STAKING_ROUTER = IStakingRouter(payable(stakingRouter));
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAdminAddress();
        __AccessControl_init();

        _cacheModuleAddresses();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IOperatorsData
    function set(
        uint256 moduleId,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external onlyRole(SETTER_ROLE) {
        address module = _resolveModuleAddress(moduleId);
        if (!_nodeOperatorExists(module, nodeOperatorId)) {
            revert NodeOperatorDoesNotExist();
        }

        OperatorInfo storage stored = _operators[moduleId][nodeOperatorId];
        stored.name = info.name;
        stored.description = info.description;
        stored.ownerRestricted = info.ownerRestricted;

        emit OperatorDataSet({
            moduleId: moduleId,
            module: module,
            nodeOperatorId: nodeOperatorId,
            name: stored.name,
            description: stored.description,
            ownerRestricted: stored.ownerRestricted
        });
    }

    /// @inheritdoc IOperatorsData
    function setByOwner(
        uint256 moduleId,
        uint256 nodeOperatorId,
        string calldata name,
        string calldata description
    ) external {
        address module = _resolveModuleAddress(moduleId);
        address owner = _owner(module, nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert NotOwner();

        OperatorInfo storage stored = _operators[moduleId][nodeOperatorId];
        if (stored.ownerRestricted) revert OwnerEditsRestricted();

        stored.name = name;
        stored.description = description;

        emit OperatorDataSet({
            moduleId: moduleId,
            module: module,
            nodeOperatorId: nodeOperatorId,
            name: stored.name,
            description: stored.description,
            ownerRestricted: stored.ownerRestricted
        });
    }

    /// @inheritdoc IOperatorsData
    function get(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (OperatorInfo memory info) {
        if (moduleId == 0) revert ZeroModuleId();
        if (_moduleAddresses[moduleId] == address(0)) revert UnknownModule();

        return _operators[moduleId][nodeOperatorId];
    }

    /// @inheritdoc IOperatorsData
    function isOwnerRestricted(
        uint256 moduleId,
        uint256 nodeOperatorId
    ) external view returns (bool) {
        if (moduleId == 0) revert ZeroModuleId();
        if (_moduleAddresses[moduleId] == address(0)) revert UnknownModule();

        return _operators[moduleId][nodeOperatorId].ownerRestricted;
    }

    function _nodeOperatorExists(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (bool) {
        return nodeOperatorId < IStakingModule(module).getNodeOperatorsCount();
    }

    function _owner(
        address module,
        uint256 nodeOperatorId
    ) internal view returns (address) {
        _validateModuleInterface(module);
        return INodeOperatorOwner(module).getNodeOperatorOwner(nodeOperatorId);
    }

    function _resolveModuleAddress(
        uint256 moduleId
    ) internal returns (address module) {
        if (moduleId == 0) revert ZeroModuleId();
        module = _moduleAddresses[moduleId];
        if (module == address(0)) {
            // Revert expected from staking router if module is unknown
            module = STAKING_ROUTER
                .getStakingModule(moduleId)
                .stakingModuleAddress;
            _moduleAddresses[moduleId] = module;
            emit ModuleAddressCached(moduleId, module);
        }
    }

    function _cacheModuleAddresses() internal {
        IStakingRouter.StakingModule[] memory modules = STAKING_ROUTER
            .getStakingModules();
        uint256 length = modules.length;
        for (uint256 i = 0; i < length; ++i) {
            IStakingRouter.StakingModule memory module = modules[i];
            _moduleAddresses[module.id] = module.stakingModuleAddress;
            emit ModuleAddressCached(module.id, module.stakingModuleAddress);
        }
    }

    function _validateModuleInterface(address module) internal view {
        if (
            !ERC165Checker.supportsInterface(
                module,
                type(INodeOperatorOwner).interfaceId
            )
        ) {
            revert ModuleDoesNotSupportNodeOperatorOwnerInterface();
        }
    }
}
