// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { OperatorsData } from "src/OperatorsData.sol";
import { IOperatorsData, OperatorInfo } from "src/interfaces/IOperatorsData.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";

import { CSMMock, NodeOperatorOwnerNo165Mock } from "../helpers/mocks/CSMMock.sol";
import { StakingRouterMock } from "../helpers/mocks/StakingRouterMock.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract OperatorsDataTestBase is Test, Utilities, Fixtures {
    CSMMock public module;
    StakingRouterMock public stakingRouter;
    OperatorsData public data;

    address public admin;
    address public setter;
    address public nodeOperator;
    address public stranger;
    uint256 public moduleId;
    uint256 public nodeOperatorId;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        setter = nextAddress("SETTER");
        nodeOperator = nextAddress("OWNER_A");
        stranger = nextAddress("STRANGER");
        moduleId = 1;
        nodeOperatorId = 0;

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
        stakingRouter = new StakingRouterMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        stakingRouter.setModules(modules);

        data = new OperatorsData(address(stakingRouter));
        _enableInitializers(address(data));
        data.initialize(admin);
        vm.startPrank(admin);
        data.grantRole(data.SETTER_ROLE(), setter);
        vm.stopPrank();
    }
}

contract OperatorsDataTest_constructor is OperatorsDataTestBase {
    function test_constructor_HappyPath() public {
        OperatorsData d = new OperatorsData(address(stakingRouter));
        assertEq(address(d.STAKING_ROUTER()), address(stakingRouter));
    }

    function test_constructor_RevertWhen_ZeroStakingRouter() public {
        vm.expectRevert(IOperatorsData.ZeroStakingRouterAddress.selector);
        new OperatorsData(address(0));
    }
}

contract OperatorsDataTest_initialize is OperatorsDataTestBase {
    function test_initialize_HappyPath() public {
        OperatorsData d = new OperatorsData(address(stakingRouter));
        _enableInitializers(address(d));
        d.initialize(admin);
        assertTrue(d.hasRole(d.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        OperatorsData d = new OperatorsData(address(stakingRouter));
        _enableInitializers(address(d));
        vm.expectRevert(IOperatorsData.ZeroAdminAddress.selector);
        d.initialize(address(0));
    }

    function test_initialize_cachesModuleAddresses() public {
        OperatorsData d = new OperatorsData(address(stakingRouter));
        _enableInitializers(address(d));

        vm.expectEmit(address(d));
        emit IOperatorsData.ModuleAddressCached(moduleId, address(module));
        d.initialize(admin);
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        OperatorsData d = new OperatorsData(address(stakingRouter));
        _enableInitializers(address(d));
        d.initialize(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        d.initialize(admin);
    }
}

contract OperatorsDataTest_set is OperatorsDataTestBase {
    function test_set() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(
            moduleId,
            address(module),
            nodeOperatorId,
            "Alpha",
            "The first",
            false
        );
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "The first",
                ownerEditsRestricted: false
            })
        );

        OperatorInfo memory info = data.get(moduleId, nodeOperatorId);
        assertEq(info.name, "Alpha");
        assertEq(info.description, "The first");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_set_OverwriteAllowed() public {
        vm.startPrank(setter);
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "v1",
                ownerEditsRestricted: false
            })
        );
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha2",
                description: "v2",
                ownerEditsRestricted: true
            })
        );
        vm.stopPrank();

        OperatorInfo memory info = data.get(moduleId, nodeOperatorId);
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "v2");
        assertTrue(info.ownerEditsRestricted);
    }

    function test_set_cacheModuleAddress() public {
        CSMMock newModule = new CSMMock();
        newModule.mock_setNodeOperatorsCount(3);
        stakingRouter.addModule(moduleId + 1, address(newModule));

        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.ModuleAddressCached(
            moduleId + 1,
            address(newModule)
        );
        data.set(
            moduleId + 1,
            nodeOperatorId,
            OperatorInfo({
                name: "Beta",
                description: "Second",
                ownerEditsRestricted: true
            })
        );

        OperatorInfo memory info = data.get(moduleId + 1, nodeOperatorId);
        assertEq(info.name, "Beta");
        assertEq(info.description, "Second");
        assertTrue(info.ownerEditsRestricted);
    }

    function test_set_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, data.SETTER_ROLE());
        vm.prank(stranger);
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: false
            })
        );
    }

    function test_set_RevertWhen_NodeOperatorDoesNotExist() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.NodeOperatorDoesNotExist.selector);
        data.set(
            moduleId,
            10,
            OperatorInfo({
                name: "X",
                description: "Y",
                ownerEditsRestricted: false
            })
        );
    }

    function test_set_RevertWhen_UnregisteredModule() public {
        vm.prank(setter);
        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        data.set(
            moduleId + 1,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: false
            })
        );
    }

    function test_set_RevertWhen_ZeroModule() public {
        vm.prank(setter);
        vm.expectRevert(IOperatorsData.ZeroModuleId.selector);
        data.set(
            0,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: false
            })
        );
    }
}

contract OperatorsDataTest_setByOwner is OperatorsDataTestBase {
    function test_setByOwner() public {
        vm.prank(nodeOperator);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(
            moduleId,
            address(module),
            nodeOperatorId,
            "OwnerName",
            "OwnerDesc",
            false
        );
        data.setByOwner(moduleId, nodeOperatorId, "OwnerName", "OwnerDesc");

        OperatorInfo memory info = data.get(moduleId, nodeOperatorId);
        assertEq(info.name, "OwnerName");
        assertEq(info.description, "OwnerDesc");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_setByOwner_cacheModuleAddress() public {
        CSMMock newModule = new CSMMock();
        newModule.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: true
            })
        );
        stakingRouter.addModule(moduleId + 1, address(newModule));

        vm.expectEmit(address(data));
        emit IOperatorsData.ModuleAddressCached(
            moduleId + 1,
            address(newModule)
        );
        vm.prank(nodeOperator);
        data.setByOwner(moduleId + 1, nodeOperatorId, "OwnerName", "OwnerDesc");

        OperatorInfo memory info = data.get(moduleId + 1, nodeOperatorId);
        assertEq(info.name, "OwnerName");
        assertEq(info.description, "OwnerDesc");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_setByOwner_RevertWhen_Restricted() public {
        vm.prank(setter);
        vm.expectEmit(address(data));
        emit IOperatorsData.OperatorDataSet(
            moduleId,
            address(module),
            nodeOperatorId,
            "",
            "",
            true
        );
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "",
                description: "",
                ownerEditsRestricted: true
            })
        );

        vm.prank(nodeOperator);
        vm.expectRevert(IOperatorsData.OwnerEditsRestricted.selector);
        data.setByOwner(moduleId, nodeOperatorId, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IOperatorsData.SenderIsNotEligible.selector);
        data.setByOwner(moduleId, nodeOperatorId, "Name", "Desc");
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
        data.setByOwner(moduleId, 10, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_ZeroModule() public {
        vm.prank(nodeOperator);
        vm.expectRevert(IOperatorsData.ZeroModuleId.selector);
        data.setByOwner(0, nodeOperatorId, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_UnregisteredModule() public {
        vm.prank(nodeOperator);
        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        data.setByOwner(moduleId + 1, nodeOperatorId, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_ModuleMissingINodeOperatorOwnerInterface()
        public
    {
        NodeOperatorOwnerNo165Mock moduleNo165 = new NodeOperatorOwnerNo165Mock(
            nodeOperator
        );
        stakingRouter.addModule(moduleId + 1, address(moduleNo165));

        vm.prank(setter);
        vm.expectRevert(
            IOperatorsData
                .ModuleDoesNotSupportNodeOperatorOwnerInterface
                .selector
        );
        data.setByOwner(moduleId + 1, nodeOperatorId, "Alpha", "Desc");
    }
}

contract OperatorsDataTest_get is OperatorsDataTestBase {
    function test_get_RevertWhen_ZeroModule() public {
        vm.expectRevert(IOperatorsData.ZeroModuleId.selector);
        data.get(0, nodeOperatorId);
    }

    function test_get_HappyPath_NoDataYet() public {
        OperatorInfo memory info = data.get(moduleId, nodeOperatorId);
        assertEq(info.name, "");
        assertEq(info.description, "");
        assertFalse(info.ownerEditsRestricted);
    }
}

contract OperatorsDataTest_restrictions is OperatorsDataTestBase {
    function test_set_updatesOwnerRestriction() public {
        vm.prank(setter);
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: true
            })
        );

        assertTrue(data.isOwnerEditsRestricted(moduleId, nodeOperatorId));
        OperatorInfo memory info = data.get(moduleId, nodeOperatorId);
        assertTrue(info.ownerEditsRestricted);

        vm.prank(setter);
        data.set(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha2",
                description: "Desc2",
                ownerEditsRestricted: false
            })
        );

        assertFalse(data.isOwnerEditsRestricted(moduleId, nodeOperatorId));
        info = data.get(moduleId, nodeOperatorId);
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "Desc2");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_isOwnerEditsRestricted_DefaultFalse() public {
        assertFalse(data.isOwnerEditsRestricted(moduleId, nodeOperatorId));
    }

    function test_isOwnerEditsRestricted_RevertWhen_ZeroModule() public {
        vm.expectRevert(IOperatorsData.ZeroModuleId.selector);
        data.isOwnerEditsRestricted(0, nodeOperatorId);
    }

    function test_isOwnerEditsRestricted_RevertWhen_UnknownModule() public {
        vm.expectRevert(IOperatorsData.UnknownModule.selector);
        data.isOwnerEditsRestricted(moduleId + 1, nodeOperatorId);
    }
}
