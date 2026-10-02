// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { IBaseWeightBoostProvider } from "../interfaces/IBaseWeightBoostProvider.sol";
import { ICuratedModule } from "../interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "../interfaces/IMetaRegistry.sol";

/// @notice Module wiring, admin role and Node Operator checks shared by the weight boost providers.
abstract contract BaseWeightBoostProvider is IBaseWeightBoostProvider, AccessControlEnumerableUpgradeable {
    ICuratedModule public immutable MODULE;
    IMetaRegistry public immutable META_REGISTRY;

    constructor(address module) {
        if (module == address(0)) revert ZeroModuleAddress();
        MODULE = ICuratedModule(module);
        META_REGISTRY = IMetaRegistry(address(MODULE.META_REGISTRY()));

        _disableInitializers();
    }

    /// @inheritdoc IBaseWeightBoostProvider
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function _initialize(address admin) internal onlyInitializing {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @dev Reverts unless the Node Operator exists and the caller owns it.
    function _onlyNodeOperatorOwner(uint256 nodeOperatorId) internal view {
        address owner = MODULE.getNodeOperatorOwner(nodeOperatorId);
        if (owner == address(0)) revert NodeOperatorDoesNotExist();
        if (owner != msg.sender) revert SenderIsNotNodeOperatorOwner();
    }

    /// @dev Ids are sequential, so an id below the operators count exists.
    function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view {
        if (nodeOperatorId >= MODULE.getNodeOperatorsCount()) revert NodeOperatorDoesNotExist();
    }
}
