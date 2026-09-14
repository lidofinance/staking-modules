// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";

import { CuratedMock } from "./mocks/CuratedMock.sol";
import { MetaRegistryMock } from "./mocks/MetaRegistryMock.sol";

/// @notice Mock wiring shared by the weight boost provider suites that drive a curated module and a
///         MetaRegistry stub. Deliberately dependency-free so suites can mix it into any base.
abstract contract CuratedProviderFixture {
    CuratedMock public module;
    MetaRegistryMock public metaRegistryMock;

    /// @dev Deploys a curated module mock wired to a MetaRegistry mock.
    function _deployModuleWithMetaRegistryMock(uint256 nodeOperatorsCount) internal {
        module = new CuratedMock();
        module.mock_setNodeOperatorsCount(nodeOperatorsCount);

        metaRegistryMock = new MetaRegistryMock();
        module.mock_setMetaRegistry(address(metaRegistryMock));
    }

    /// @dev Makes `owner` both manager and reward address of every operator in the mock.
    function _setNodeOperatorOwner(address owner) internal {
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: true
            })
        );
    }
}
