// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "./helpers/Utilities.sol";

import { CSMMock } from "./helpers/mocks/CSMMock.sol";
import { OperatorsData } from "../src/OperatorsData.sol";
import { IOperatorsData, OperatorInfo } from "../src/interfaces/IOperatorsData.sol";
import { NodeOperatorManagementProperties } from "../src/interfaces/ICSModule.sol";

contract OperatorsDataTestBase is Test, Utilities {
    CSMMock public module;
    OperatorsData public data;

    address public admin;
    address public setter;
    address public nodeOperator;
    address public stranger;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        setter = nextAddress("SETTER");
        nodeOperator = nextAddress("OWNER_A");
        stranger = nextAddress("STRANGER");

        module = new CSMMock();
        module.mock_setNodeOperatorsCount(3);
        // Owner is determined by managementProperties: when extended=true -> manager is owner, else reward
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: true
            })
        );

        data = new OperatorsData(admin);
        vm.startPrank(admin);
        data.grantRole(data.SETTER_ROLE(), setter);
        vm.stopPrank();
    }
}

contract OperatorsDataTest_constructor is OperatorsDataTestBase {
    function test_constructor_HappyPath() public {
        OperatorsData d = new OperatorsData(admin);
        assertEq(d.hasRole(d.DEFAULT_ADMIN_ROLE(), admin), true);
    }

    function test_constructor_RevertWhen_ZeroAdmin() public {
        vm.expectRevert(IOperatorsData.ZeroAdminAddress.selector);
        new OperatorsData(address(0));
    }
}

contract OperatorsDataTest_set is OperatorsDataTestBase {
    function test_set() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(
            address(module),
            1,
            "Alpha",
            "The first"
        );
        data.set(address(module), 1, "Alpha", "The first");

        OperatorInfo memory info = data.get(address(module), 1);
        assertEq(info.name, "Alpha");
        assertEq(info.description, "The first");
    }

    function test_set_OverwriteAllowed() public {
        vm.startPrank(setter);
        data.set(address(module), 1, "Alpha", "v1");
        data.set(address(module), 1, "Alpha2", "v2");
        vm.stopPrank();

        OperatorInfo memory info = data.get(address(module), 1);
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "v2");
    }

    function test_set_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, data.SETTER_ROLE());
        vm.prank(stranger);
        data.set(address(module), 1, "Alpha", "Desc");
    }

    function test_set_RevertWhen_NodeOperatorDoesNotExist() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.NodeOperatorDoesNotExist.selector);
        data.set(address(module), 10, "X", "Y");
    }

    function test_set_RevertWhen_ZeroModule() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        data.set(address(0), 1, "Alpha", "Desc");
    }
}

contract OperatorsDataTest_setByOwner is OperatorsDataTestBase {
    function test_setByOwner() public {
        vm.prank(nodeOperator);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(
            address(module),
            2,
            "OwnerName",
            "OwnerDesc"
        );
        data.setByOwner(address(module), 2, "OwnerName", "OwnerDesc");

        OperatorInfo memory info = data.get(address(module), 2);
        assertEq(info.name, "OwnerName");
        assertEq(info.description, "OwnerDesc");
    }

    function test_setByOwner_RevertWhen_Restricted() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OwnerRestrictionUpdated(address(module), 2, true);
        data.setOwnerRestriction(address(module), 2, true);

        vm.prank(nodeOperator);
        vm.expectRevert(IOperatorsData.OwnerEditsRestricted.selector);
        data.setByOwner(address(module), 2, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IOperatorsData.NotOwner.selector);
        data.setByOwner(address(module), 2, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_NodeOperatorDoesNotExist() public {
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            })
        );
        vm.prank(nodeOperator);
        vm.expectRevert(IOperatorsData.NodeOperatorDoesNotExist.selector);
        data.setByOwner(address(module), 10, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_ZeroModule() public {
        vm.prank(nodeOperator);
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        data.setByOwner(address(0), 2, "Name", "Desc");
    }
}

contract OperatorsDataTest_get is OperatorsDataTestBase {
    function test_get_RevertWhen_ZeroModule() public {
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        data.get(address(0), 1);
    }
}

contract OperatorsDataTest_restrictions is OperatorsDataTestBase {
    function test_setOwnerRestriction() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OwnerRestrictionUpdated(address(module), 1, true);
        data.setOwnerRestriction(address(module), 1, true);

        assertTrue(data.isOwnerRestricted(address(module), 1));

        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OwnerRestrictionUpdated(address(module), 1, false);
        data.setOwnerRestriction(address(module), 1, false);

        assertFalse(data.isOwnerRestricted(address(module), 1));
    }

    function test_setOwnerRestriction_RevertWhen_NodeOperatorDoesNotExist()
        public
    {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.NodeOperatorDoesNotExist.selector);
        data.setOwnerRestriction(address(module), 10, true);
    }

    function test_setOwnerRestriction_RevertWhen_ZeroModule() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        data.setOwnerRestriction(address(0), 1, true);
    }

    function test_isOwnerRestricted_RevertWhen_ZeroModule() public {
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        data.isOwnerRestricted(address(0), 1);
    }
}
