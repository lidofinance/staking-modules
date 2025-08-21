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

        data = new OperatorsData(address(module), admin);
        vm.startPrank(admin);
        data.grantRole(data.SETTER_ROLE(), setter);
        vm.stopPrank();
    }
}

contract OperatorsDataTest_constructor is OperatorsDataTestBase {
    function test_constructor_HappyPath() public {
        OperatorsData d = new OperatorsData(address(module), admin);

        assertEq(address(d.MODULE()), address(module));
        assertEq(d.hasRole(d.DEFAULT_ADMIN_ROLE(), admin), true);
    }

    function test_constructor_RevertWhen_ZeroAdmin() public {
        vm.expectRevert(IOperatorsData.ZeroAdminAddress.selector);
        new OperatorsData(address(module), address(0));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IOperatorsData.ZeroModuleAddress.selector);
        new OperatorsData(address(0), admin);
    }
}

contract OperatorsDataTest_set is OperatorsDataTestBase {
    function test_set() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(1, "Alpha", "The first");
        data.set(1, "Alpha", "The first");

        OperatorInfo memory info = data.get(1);
        assertEq(info.name, "Alpha");
        assertEq(info.description, "The first");
    }

    function test_set_OverwriteAllowed() public {
        vm.startPrank(setter);
        data.set(1, "Alpha", "v1");
        data.set(1, "Alpha2", "v2");
        vm.stopPrank();

        OperatorInfo memory info = data.get(1);
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "v2");
    }

    function test_set_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, data.SETTER_ROLE());
        vm.prank(stranger);
        data.set(1, "Alpha", "Desc");
    }

    function test_set_RevertWhen_NodeOperatorDoesNotExist() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.NodeOperatorDoesNotExist.selector);
        data.set(10, "X", "Y");
    }
}

contract OperatorsDataTest_setByOwner is OperatorsDataTestBase {
    function test_setByOwner() public {
        vm.prank(nodeOperator);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(2, "OwnerName", "OwnerDesc");
        data.setByOwner(2, "OwnerName", "OwnerDesc");

        OperatorInfo memory info = data.get(2);
        assertEq(info.name, "OwnerName");
        assertEq(info.description, "OwnerDesc");
    }

    function test_setByOwner_RevertWhen_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IOperatorsData.NotOwner.selector);
        data.setByOwner(2, "Name", "Desc");
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
        data.setByOwner(10, "Name", "Desc");
    }
}
