// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { MetaOperatorRegistry } from "src/MetaOperatorRegistry.sol";
import { IMetaOperatorRegistry, OperatorInfo } from "src/interfaces/IMetaOperatorRegistry.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";

import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { StakingRouterMock } from "../helpers/mocks/StakingRouterMock.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract MetaOperatorRegistryTestBase is Test, Utilities, Fixtures {
    CSMMock public module;
    StakingRouterMock public stakingRouter;
    MetaOperatorRegistry public registry;

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

        registry = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(registry));
        registry.initialize(admin);
        vm.startPrank(admin);
        registry.grantRole(registry.SET_OPERATOR_INFO_ROLE(), setter);
        vm.stopPrank();
    }
}

contract MetaOperatorRegistryTest_constructor is MetaOperatorRegistryTestBase {
    function test_constructor_HappyPath() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        assertEq(address(d.STAKING_ROUTER()), address(stakingRouter));
    }

    function test_constructor_RevertWhen_ZeroStakingRouter() public {
        vm.expectRevert(
            IMetaOperatorRegistry.ZeroStakingRouterAddress.selector
        );
        new MetaOperatorRegistry(address(module), address(0));
    }
}

contract MetaOperatorRegistryTest_initialize is MetaOperatorRegistryTestBase {
    function test_initialize_HappyPath() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(d));
        d.initialize(admin);
        assertTrue(d.hasRole(d.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(d));
        vm.expectRevert(IMetaOperatorRegistry.ZeroAdminAddress.selector);
        d.initialize(address(0));
    }

    function test_initialize_allowsMetadataLookup() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(d));
        d.initialize(admin);

        OperatorInfo memory info = d.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
        assertEq(info.name, "");
        assertEq(info.description, "");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(d));
        d.initialize(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        d.initialize(admin);
    }
}

contract MetaOperatorRegistryTest_set is MetaOperatorRegistryTestBase {
    function test_set() public {
        vm.prank(setter);
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorDataSet(
            moduleId,
            nodeOperatorId,
            "Alpha",
            "The first",
            false
        );
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "The first",
                ownerEditsRestricted: false
            })
        );

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
        assertEq(info.name, "Alpha");
        assertEq(info.description, "The first");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_set_OverwriteAllowed() public {
        vm.startPrank(setter);
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "v1",
                ownerEditsRestricted: false
            })
        );
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha2",
                description: "v2",
                ownerEditsRestricted: true
            })
        );
        vm.stopPrank();

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "v2");
        assertTrue(info.ownerEditsRestricted);
    }

    function test_set_cacheModuleAddress() public {
        CSMMock newModule = new CSMMock();
        newModule.mock_setNodeOperatorsCount(3);
        stakingRouter.addModule(moduleId + 1, address(newModule));

        vm.prank(setter);
        registry.setOperatorMetadataAsAdmin(
            moduleId + 1,
            nodeOperatorId,
            OperatorInfo({
                name: "Beta",
                description: "Second",
                ownerEditsRestricted: true
            })
        );

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId + 1,
            nodeOperatorId
        );
        assertEq(info.name, "Beta");
        assertEq(info.description, "Second");
        assertTrue(info.ownerEditsRestricted);
    }

    function test_set_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, registry.SET_OPERATOR_INFO_ROLE());
        vm.prank(stranger);
        registry.setOperatorMetadataAsAdmin(
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
        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        registry.setOperatorMetadataAsAdmin(
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
        registry.setOperatorMetadataAsAdmin(
            moduleId + 1,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: false
            })
        );
    }
}

contract MetaOperatorRegistryTest_setByOwner is MetaOperatorRegistryTestBase {
    function test_setByOwner() public {
        vm.prank(nodeOperator);
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorDataSet(
            moduleId,
            nodeOperatorId,
            "OwnerName",
            "OwnerDesc",
            false
        );
        registry.setOperatorMetadataAsOwner(
            moduleId,
            nodeOperatorId,
            "OwnerName",
            "OwnerDesc"
        );

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
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

        vm.prank(nodeOperator);
        registry.setOperatorMetadataAsOwner(
            moduleId + 1,
            nodeOperatorId,
            "OwnerName",
            "OwnerDesc"
        );

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId + 1,
            nodeOperatorId
        );
        assertEq(info.name, "OwnerName");
        assertEq(info.description, "OwnerDesc");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_setByOwner_RevertWhen_Restricted() public {
        vm.prank(setter);
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorDataSet(
            moduleId,
            nodeOperatorId,
            "",
            "",
            true
        );
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "",
                description: "",
                ownerEditsRestricted: true
            })
        );

        vm.prank(nodeOperator);
        vm.expectRevert(IMetaOperatorRegistry.OwnerEditsRestricted.selector);
        registry.setOperatorMetadataAsOwner(
            moduleId,
            nodeOperatorId,
            "Name",
            "Desc"
        );
    }

    function test_setByOwner_RevertWhen_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(IMetaOperatorRegistry.SenderIsNotEligible.selector);
        registry.setOperatorMetadataAsOwner(
            moduleId,
            nodeOperatorId,
            "Name",
            "Desc"
        );
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
        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        registry.setOperatorMetadataAsOwner(moduleId, 10, "Name", "Desc");
    }

    function test_setByOwner_RevertWhen_UnregisteredModule() public {
        vm.prank(nodeOperator);
        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        registry.setOperatorMetadataAsOwner(
            moduleId + 1,
            nodeOperatorId,
            "Name",
            "Desc"
        );
    }
}

contract MetaOperatorRegistryTest_get is MetaOperatorRegistryTestBase {
    function test_get_HappyPath_NoDataYet() public {
        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
        assertEq(info.name, "");
        assertEq(info.description, "");
        assertFalse(info.ownerEditsRestricted);
    }

    function test_get_AllowsZeroModuleId() public {
        OperatorInfo memory info = registry.getOperatorMetadata(
            0,
            nodeOperatorId
        );
        assertEq(info.name, "");
        assertEq(info.description, "");
        assertFalse(info.ownerEditsRestricted);
    }
}

contract MetaOperatorRegistryTest_restrictions is MetaOperatorRegistryTestBase {
    function test_set_updatesOwnerRestriction() public {
        vm.prank(setter);
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha",
                description: "Desc",
                ownerEditsRestricted: true
            })
        );

        OperatorInfo memory info = registry.getOperatorMetadata(
            moduleId,
            nodeOperatorId
        );
        assertTrue(info.ownerEditsRestricted);

        vm.prank(setter);
        registry.setOperatorMetadataAsAdmin(
            moduleId,
            nodeOperatorId,
            OperatorInfo({
                name: "Alpha2",
                description: "Desc2",
                ownerEditsRestricted: false
            })
        );

        info = registry.getOperatorMetadata(moduleId, nodeOperatorId);
        assertEq(info.name, "Alpha2");
        assertEq(info.description, "Desc2");
        assertFalse(info.ownerEditsRestricted);
    }
}
