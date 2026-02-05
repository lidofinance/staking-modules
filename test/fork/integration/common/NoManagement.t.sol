// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ModuleTypeBase, CSMIntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract NoManagementBaseTest is ModuleTypeBase {
    address public nodeOperator;

    function setUp() public virtual {
        _setUpModule();
        nodeOperator = nextAddress("nodeOperator");
    }

    function _createNodeOperator(
        address manager,
        address reward,
        bool extendedPermissions
    ) internal returns (uint256 noId) {
        noId = integrationHelpers.addNodeOperatorWithManagement(
            nodeOperator,
            manager,
            reward,
            extendedPermissions,
            1
        );
    }
}

abstract contract NoAddressesBasicPermissionsTestBase is NoManagementBaseTest {
    bool internal immutable EXTENDED;

    constructor() {
        EXTENDED = _extended();
    }

    function _extended() internal pure virtual returns (bool) {
        return false;
    }

    function test_changeManagerAddresses() public {
        address newManager = nextAddress("newManager");

        uint256 noId = _createNodeOperator(
            nodeOperator,
            nodeOperator,
            EXTENDED
        );
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.proposeNodeOperatorManagerAddressChange");
        module.proposeNodeOperatorManagerAddressChange(noId, newManager);
        vm.stopSnapshotGas();

        vm.prank(newManager);
        vm.startSnapshotGas("module.confirmNodeOperatorManagerAddressChange");
        module.confirmNodeOperatorManagerAddressChange(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).managerAddress,
            newManager
        );
    }

    function test_changeRewardAddresses() public {
        address newReward = nextAddress("newReward");

        uint256 noId = _createNodeOperator(
            nodeOperator,
            nodeOperator,
            EXTENDED
        );
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.proposeNodeOperatorRewardAddressChange");
        module.proposeNodeOperatorRewardAddressChange(noId, newReward);
        vm.stopSnapshotGas();

        vm.prank(newReward);
        vm.startSnapshotGas("module.confirmNodeOperatorRewardAddressChange");
        module.confirmNodeOperatorRewardAddressChange(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).rewardAddress,
            newReward
        );
    }
}

abstract contract NoAddressesExtendedPermissionsTestBase is
    NoAddressesBasicPermissionsTestBase
{
    function _extended() internal pure override returns (bool) {
        return true;
    }
}

abstract contract NoAddressesPermissionsTestBase is NoManagementBaseTest {
    function test_resetManagerAddresses() public {
        address someManager = nextAddress("someManager");

        uint256 noId = _createNodeOperator(someManager, nodeOperator, false);

        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.resetNodeOperatorManagerAddress");
        module.resetNodeOperatorManagerAddress(noId);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).managerAddress,
            nodeOperator
        );
    }

    function test_changeRewardAddresses() public {
        address newReward = nextAddress("newReward");

        uint256 noId = _createNodeOperator(nodeOperator, nodeOperator, true);
        vm.prank(nodeOperator);
        vm.startSnapshotGas("module.changeNodeOperatorRewardAddress");
        module.changeNodeOperatorRewardAddress(noId, newReward);
        vm.stopSnapshotGas();

        assertEq(
            module.getNodeOperatorManagementProperties(noId).rewardAddress,
            newReward
        );
    }
}

contract NoAddressesBasicPermissionsTestCSM is
    NoAddressesBasicPermissionsTestBase,
    CSMIntegrationBase
{}

contract NoAddressesBasicPermissionsTestCurated is
    NoAddressesBasicPermissionsTestBase,
    CuratedIntegrationBase
{}

contract NoAddressesExtendedPermissionsTestCSM is
    NoAddressesExtendedPermissionsTestBase,
    CSMIntegrationBase
{}

contract NoAddressesExtendedPermissionsTestCurated is
    NoAddressesExtendedPermissionsTestBase,
    CuratedIntegrationBase
{}

contract NoAddressesPermissionsTestCSM is
    NoAddressesPermissionsTestBase,
    CSMIntegrationBase
{}

contract NoAddressesPermissionsTestCurated is
    NoAddressesPermissionsTestBase,
    CuratedIntegrationBase
{}
