// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test, Vm } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { MetaOperatorRegistry } from "src/MetaOperatorRegistry.sol";
import { IMetaOperatorRegistry, OperatorInfo } from "src/interfaces/IMetaOperatorRegistry.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IStakingRouter } from "src/interfaces/IStakingRouter.sol";

import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { NodeOperatorRegistryMock } from "../helpers/mocks/NodeOperatorRegistryMock.sol";
import { StakingRouterMock } from "../helpers/mocks/StakingRouterMock.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract MetaOperatorRegistryForTest is MetaOperatorRegistry {
    constructor(
        address module,
        address stakingRouter
    ) MetaOperatorRegistry(module, stakingRouter) {}

    function mock_setModuleAddress(uint256 moduleId, address module) external {
        _modules[moduleId] = module;
    }
}

contract MetaOperatorRegistryTestBase is Test, Utilities, Fixtures {
    CSMMock public module;
    StakingRouterMock public stakingRouter;
    MetaOperatorRegistryForTest public registry;

    address public admin;
    address public metadataAdmin;
    address public groupManager;
    address public nodeOperatorOwner;
    address public stranger;

    OperatorInfo internal emptyOperatorInfo;

    uint256 internal constant MODULE_ID = 1;
    uint256 internal constant EXTERNAL_MODULE_ID = MODULE_ID + 1;
    uint256 internal constant CREATE_GROUP_SENTINEL = type(uint256).max;
    uint256 internal constant CURVE_WEIGHT = 10000;
    uint16 internal constant MAX_BP = 10000;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        metadataAdmin = nextAddress("METADATA_ADMIN");
        groupManager = nextAddress("GROUP_MANAGER");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        stranger = nextAddress("STRANGER");

        module = new CSMMock();
        module.mock_setNodeOperatorsCount(3);
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperatorOwner,
                rewardAddress: nodeOperatorOwner,
                extendedManagerPermissions: true
            })
        );
        stakingRouter = new StakingRouterMock();
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        stakingRouter.setModules(modules);

        registry = new MetaOperatorRegistryForTest(
            address(module),
            address(stakingRouter)
        );
        _enableInitializers(address(registry));
        registry.initialize(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.SET_OPERATOR_INFO_ROLE(), metadataAdmin);
        registry.grantRole(
            registry.MANAGE_OPERATOR_GROUPS_ROLE(),
            groupManager
        );
        vm.stopPrank();
    }
}

contract MetaOperatorRegistryTestGroupsBase is MetaOperatorRegistryTestBase {
    NodeOperatorRegistryMock public externalModule;

    function setUp() public virtual override {
        super.setUp();

        externalModule = new NodeOperatorRegistryMock();
        externalModule.mock_setNodeOperatorsCount(2);
        stakingRouter.addModule(EXTERNAL_MODULE_ID, address(externalModule));
    }

    function _norData(
        uint8 moduleId_,
        uint64 nodeOperatorId_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), moduleId_, nodeOperatorId_);
    }

    function _externalOperator(
        bytes memory data
    ) internal pure returns (IMetaOperatorRegistry.ExternalOperator memory op) {
        op = IMetaOperatorRegistry.ExternalOperator({ data: data });
    }

    function _extOperatorsArr0()
        internal
        pure
        returns (IMetaOperatorRegistry.ExternalOperator[] memory ops)
    {}

    function _extOperatorsArr1(
        bytes memory data
    )
        internal
        pure
        returns (IMetaOperatorRegistry.ExternalOperator[] memory ops)
    {
        ops = new IMetaOperatorRegistry.ExternalOperator[](1);
        ops[0] = _externalOperator(data);
    }

    function _mockBondCurveWeightHook() internal {
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                ICuratedModule.onBondCurveWeightUpdated.selector
            ),
            ""
        );
    }

    function _setBondCurveWeight(uint256 curveId, uint256 weight) internal {
        _mockBondCurveWeightHook();
        vm.prank(groupManager);
        registry.setBondCurveWeight(curveId, weight);
    }

    function _createGroup(
        IMetaOperatorRegistry.SubNodeOperator[] memory subNodeOperators,
        IMetaOperatorRegistry.ExternalOperator[] memory externalOperators
    ) internal {
        registry.createOrUpdateOperatorGroup(
            CREATE_GROUP_SENTINEL,
            IMetaOperatorRegistry.OperatorGroup({
                subNodeOperators: subNodeOperators,
                externalOperators: externalOperators
            })
        );
    }

    function _updateGroup(
        uint256 groupId,
        IMetaOperatorRegistry.SubNodeOperator[] memory subNodeOperators,
        IMetaOperatorRegistry.ExternalOperator[] memory externalOperators
    ) internal {
        registry.createOrUpdateOperatorGroup(
            groupId,
            IMetaOperatorRegistry.OperatorGroup({
                subNodeOperators: subNodeOperators,
                externalOperators: externalOperators
            })
        );
    }

    function _setExternalNodeOperator(
        uint256 nodeOperatorId,
        uint64 exitedValidators,
        uint64 depositedValidators
    ) internal {
        NodeOperatorRegistryMock.NodeOperatorData memory data;

        data.active = true;
        data.totalExitedValidators = exitedValidators;
        data.totalDepositedValidators = depositedValidators;

        externalModule.mock_setNodeOperator(nodeOperatorId, data);
    }

    function _createDefaultGroupWithExternal(
        uint64 subNodeOperatorId,
        uint16 share,
        uint64 externalNodeOperatorId
    ) internal returns (bytes memory externalData) {
        externalData = _norData(
            uint8(EXTERNAL_MODULE_ID),
            externalNodeOperatorId
        );
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(externalData);

        vm.prank(groupManager);
        _createGroup(
            _subOperatorsArr1(subNodeOperatorId, share),
            externalOperators
        );
    }

    function _subOperatorsArr0()
        internal
        pure
        returns (IMetaOperatorRegistry.SubNodeOperator[] memory ops)
    {}

    function _subOperatorsArr1(
        uint64 nodeOperatorId,
        uint16 share
    )
        internal
        pure
        returns (IMetaOperatorRegistry.SubNodeOperator[] memory ops)
    {
        ops = new IMetaOperatorRegistry.SubNodeOperator[](1);
        ops[0] = IMetaOperatorRegistry.SubNodeOperator({
            nodeOperatorId: nodeOperatorId,
            share: share
        });
    }

    function _subOperatorsArr2(
        IMetaOperatorRegistry.SubNodeOperator memory op0,
        IMetaOperatorRegistry.SubNodeOperator memory op1
    )
        internal
        pure
        returns (IMetaOperatorRegistry.SubNodeOperator[] memory ops)
    {
        ops = new IMetaOperatorRegistry.SubNodeOperator[](2);
        ops[0] = op0;
        ops[1] = op1;
    }
}

contract MetaOperatorRegistryTestConstructor is MetaOperatorRegistryTestBase {
    function test_constructor_SetsImmutables() public {
        MetaOperatorRegistry d = new MetaOperatorRegistry(
            address(module),
            address(stakingRouter)
        );
        assertEq(address(d.STAKING_ROUTER()), address(stakingRouter));
        assertEq(address(d.MODULE()), address(module));
        assertEq(address(d.ACCOUNTING()), address(module.ACCOUNTING()));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IMetaOperatorRegistry.ZeroModuleAddress.selector);
        new MetaOperatorRegistry(address(0), address(stakingRouter));
    }

    function test_constructor_RevertWhen_ZeroStakingRouter() public {
        vm.expectRevert(
            IMetaOperatorRegistry.ZeroStakingRouterAddress.selector
        );
        new MetaOperatorRegistry(address(module), address(0));
    }
}

contract MetaOperatorRegistryTestInitialize is MetaOperatorRegistryTestBase {
    function test_initialize_SetsAdmin() public {
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

contract MetaOperatorRegistryTestSetMetadataAsAdmin is
    MetaOperatorRegistryTestBase
{
    function test_setOperatorMetadataAsAdmin() public {
        uint256 nodeOperatorId = 0;

        OperatorInfo memory exp = OperatorInfo({
            name: "Alpha",
            description: "The first",
            ownerEditsRestricted: false
        });

        vm.prank(metadataAdmin);
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorDataSet(
            MODULE_ID,
            nodeOperatorId,
            exp.name,
            exp.description,
            false
        );
        registry.setOperatorMetadataAsAdmin(MODULE_ID, nodeOperatorId, exp);

        OperatorInfo memory got = registry.getOperatorMetadata(
            MODULE_ID,
            nodeOperatorId
        );
        assertEq(got.name, exp.name);
        assertEq(got.description, exp.description);
        assertEq(got.ownerEditsRestricted, exp.ownerEditsRestricted);
    }

    function test_setMetadataAsAdmin_OverwriteAllowed() public {
        uint256 nodeOperatorId = 0;

        OperatorInfo memory infoV1 = OperatorInfo({
            name: "Alpha",
            description: "v1",
            ownerEditsRestricted: false
        });
        OperatorInfo memory infoV2 = OperatorInfo({
            name: "Omega",
            description: "v2",
            ownerEditsRestricted: true
        });

        vm.startPrank(metadataAdmin);
        registry.setOperatorMetadataAsAdmin(MODULE_ID, nodeOperatorId, infoV1);
        registry.setOperatorMetadataAsAdmin(MODULE_ID, nodeOperatorId, infoV2);
        vm.stopPrank();

        OperatorInfo memory got = registry.getOperatorMetadata(
            MODULE_ID,
            nodeOperatorId
        );

        assertEq(got.name, infoV2.name);
        assertEq(got.description, infoV2.description);
        assertEq(got.ownerEditsRestricted, infoV2.ownerEditsRestricted);
    }

    function test_setOperatorMetadataAsAdmin_RevertWhen_NoRole() public {
        uint256 nodeOperatorId = 0;

        expectRoleRevert(stranger, registry.SET_OPERATOR_INFO_ROLE());
        vm.prank(stranger);
        registry.setOperatorMetadataAsAdmin(
            MODULE_ID,
            nodeOperatorId,
            emptyOperatorInfo
        );
    }

    function test_setOperatorMetadataAsAdmin_RevertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.prank(metadataAdmin);
        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        registry.setOperatorMetadataAsAdmin(
            MODULE_ID,
            nonExistentNoId,
            emptyOperatorInfo
        );
    }

    function test_setOperatorMetadataAsAdmin_RevertWhen_UnregisteredModule()
        public
    {
        uint256 nodeOperatorId = 0;

        vm.prank(metadataAdmin);
        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        registry.setOperatorMetadataAsAdmin(
            MODULE_ID + 1,
            nodeOperatorId,
            emptyOperatorInfo
        );
    }
}

contract MetaOperatorRegistryTestSetMetadataAsOwner is
    MetaOperatorRegistryTestBase
{
    function test_setOperatorMetadataAsOwner() public {
        uint256 nodeOperatorId = 0;

        OperatorInfo memory exp = OperatorInfo({
            name: "Alpha",
            description: "The first",
            ownerEditsRestricted: false
        });

        vm.prank(nodeOperatorOwner);
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorDataSet(
            MODULE_ID,
            nodeOperatorId,
            exp.name,
            exp.description,
            exp.ownerEditsRestricted
        );
        registry.setOperatorMetadataAsOwner(
            MODULE_ID,
            nodeOperatorId,
            exp.name,
            exp.description
        );

        OperatorInfo memory got = registry.getOperatorMetadata(
            MODULE_ID,
            nodeOperatorId
        );
        assertEq(got.name, exp.name);
        assertEq(got.description, exp.description);
        assertEq(got.ownerEditsRestricted, exp.ownerEditsRestricted);
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_Restricted() public {
        uint256 nodeOperatorId = 0;

        vm.prank(metadataAdmin);
        registry.setOperatorMetadataAsAdmin(
            MODULE_ID,
            nodeOperatorId,
            OperatorInfo({
                name: "",
                description: "",
                ownerEditsRestricted: true
            })
        );

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IMetaOperatorRegistry.OwnerEditsRestricted.selector);
        registry.setOperatorMetadataAsOwner(
            MODULE_ID,
            nodeOperatorId,
            "Name",
            "Desc"
        );
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_NotOwner() public {
        uint256 nodeOperatorId = 0;

        vm.prank(stranger);
        vm.expectRevert(IMetaOperatorRegistry.SenderIsNotEligible.selector);
        registry.setOperatorMetadataAsOwner(
            MODULE_ID,
            nodeOperatorId,
            "Name",
            "Desc"
        );
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        registry.setOperatorMetadataAsOwner(
            MODULE_ID,
            nonExistentNoId,
            "Name",
            "Desc"
        );
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_UnregisteredModule()
        public
    {
        uint256 nodeOperatorId = 0;
        uint256 nonExistentModuleId = stakingRouter.getStakingModulesCount() +
            1;

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        registry.setOperatorMetadataAsOwner(
            nonExistentModuleId,
            nodeOperatorId,
            "Name",
            "Desc"
        );
    }
}

contract MetaOperatorRegistryTestGetMetadata is MetaOperatorRegistryTestBase {
    function test_getOperatorMetadata_ReturnsEmptyWhenUnset() public {
        uint256 nodeOperatorId = 0;

        OperatorInfo memory got = registry.getOperatorMetadata(
            MODULE_ID,
            nodeOperatorId
        );

        assertEq(got.name, emptyOperatorInfo.name);
        assertEq(got.description, emptyOperatorInfo.description);
        assertEq(
            got.ownerEditsRestricted,
            emptyOperatorInfo.ownerEditsRestricted
        );
    }
}

contract MetaOperatorRegistryTestGroupsCreate is
    MetaOperatorRegistryTestGroupsBase
{
    function test_createGroup_CreatesGroup() public {
        IMetaOperatorRegistry.SubNodeOperator memory op0 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaOperatorRegistry.SubNodeOperator memory op1 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 1, share: 4000 });
        bytes memory externalData = _norData(uint8(EXTERNAL_MODULE_ID), 0);

        vm.expectEmit(address(registry));
        uint256 newGroupId = registry.getOperatorGroupsCount();
        emit IMetaOperatorRegistry.OperatorGroupCreated(newGroupId);

        vm.prank(groupManager);
        _createGroup(
            _subOperatorsArr2(op0, op1),
            _extOperatorsArr1(externalData)
        );

        assertEq(registry.getOperatorGroupsCount(), 1);
        (bool isInGroup0, uint256 groupId0) = registry
            .getNodeOperatorGroupMembership(op0.nodeOperatorId);
        assertTrue(isInGroup0);
        assertEq(groupId0, newGroupId);

        (bool isInGroup1, uint256 groupId1) = registry
            .getNodeOperatorGroupMembership(op1.nodeOperatorId);
        assertTrue(isInGroup1);
        assertEq(groupId1, newGroupId);

        (bool isInExternalGroup, uint256 externalGroupId) = registry
            .getExternalOperatorGroupMembership(externalData);
        assertTrue(isInExternalGroup);
        assertEq(externalGroupId, newGroupId);

        IMetaOperatorRegistry.OperatorGroup memory stored = registry
            .getOperatorGroup(newGroupId);
        assertEq(stored.subNodeOperators.length, 2);
        assertEq(stored.externalOperators.length, 1);
        assertEq(stored.externalOperators[0].data, externalData);
    }

    function test_createGroup_NoExternalOperators() public {
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        IMetaOperatorRegistry.OperatorGroup memory stored = registry
            .getOperatorGroup(0);
        assertEq(stored.externalOperators.length, 0);
    }

    function test_createGroup_RevertWhen_NotRole() public {
        expectRoleRevert(stranger, registry.MANAGE_OPERATOR_GROUPS_ROLE());
        vm.prank(stranger);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_EmptyGroup() public {
        vm.expectRevert(IMetaOperatorRegistry.InvalidOperatorGroup.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr0(), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_ExternalOnlyGroupOnCreate() public {
        vm.expectRevert(IMetaOperatorRegistry.InvalidOperatorGroup.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr0(), _extOperatorsArr1(hex""));
    }

    function test_createGroup_RevertWhen_SharesNotMaxBP() public {
        IMetaOperatorRegistry.SubNodeOperator memory op0 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaOperatorRegistry.SubNodeOperator memory op1 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 1, share: 3000 });

        vm.expectRevert(
            IMetaOperatorRegistry.InvalidSubNodeOperatorShares.selector
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op0, op1), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_SubOperatorDoesNotExist() public {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        vm.prank(groupManager);
        _createGroup(
            _subOperatorsArr1(uint64(nonExistentNoId), MAX_BP),
            _extOperatorsArr0()
        );
    }

    function test_createGroup_RevertWhen_SubOperatorDuplicatedInGroup() public {
        IMetaOperatorRegistry.SubNodeOperator memory op = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 0, share: 5000 });
        vm.expectRevert(
            abi.encodeWithSelector(
                IMetaOperatorRegistry.NodeOperatorAlreadyInGroup.selector,
                op.nodeOperatorId
            )
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op, op), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_SubOperatorAlreadyInAnotherGroup()
        public
    {
        uint64 nodeOperatorId = 0;

        vm.prank(groupManager);
        _createGroup(
            _subOperatorsArr1(nodeOperatorId, MAX_BP),
            _extOperatorsArr0()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMetaOperatorRegistry.NodeOperatorAlreadyInGroup.selector,
                nodeOperatorId
            )
        );
        vm.prank(groupManager);
        _createGroup(
            _subOperatorsArr1(nodeOperatorId, MAX_BP),
            _extOperatorsArr0()
        );
    }

    function test_createGroup_RevertWhen_ExternalOperatorDuplicatedInGroup()
        public
    {
        externalModule.mock_setNodeOperatorsCount(1);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = new IMetaOperatorRegistry.ExternalOperator[](
                2
            );
        IMetaOperatorRegistry.ExternalOperator memory op = _externalOperator(
            _norData(uint8(EXTERNAL_MODULE_ID), 0)
        );

        externalOperators[0] = op;
        externalOperators[1] = op;

        vm.expectRevert(
            IMetaOperatorRegistry.AlreadyUsedAsExternalOperator.selector
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalOperatorAlreadyUsedInAnotherGroup()
        public
    {
        externalModule.mock_setNodeOperatorsCount(2);
        uint64 subOp1Id = 0;
        uint64 subOp2Id = 1;

        uint64 extOpId = 0;

        bytes memory extOpData = _createDefaultGroupWithExternal(
            subOp1Id,
            MAX_BP,
            extOpId
        );

        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(extOpData);

        vm.expectRevert(
            IMetaOperatorRegistry.AlreadyUsedAsExternalOperator.selector
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(subOp2Id, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalOperatorTypeUnsupported()
        public
    {
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                abi.encodePacked(uint8(1), uint8(EXTERNAL_MODULE_ID), uint64(0))
            );
        vm.expectRevert(
            IMetaOperatorRegistry.UnsupportedExternalOperatorType.selector
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalModuleDoesNotExist() public {
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID + 1), 0)
            );

        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalNodeOperatorDoesNotExist()
        public
    {
        uint256 nonExistentNoId = externalModule.getNodeOperatorsCount();
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID), uint64(nonExistentNoId))
            );

        vm.startPrank(groupManager);
        vm.expectRevert(
            IMetaOperatorRegistry.NodeOperatorDoesNotExist.selector
        );
        _createGroup(
            _subOperatorsArr1(uint64(nonExistentNoId), MAX_BP),
            externalOperators
        );
        vm.stopPrank();
    }
}

contract MetaOperatorRegistryTestGroupsUpdate is
    MetaOperatorRegistryTestGroupsBase
{
    function test_updateGroup_OnlySubOperators() public {
        uint256 newGroupId = registry.getOperatorGroupsCount();
        _createDefaultGroupWithExternal(0, MAX_BP, 0);

        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.OperatorGroupUpdated(newGroupId);

        vm.prank(groupManager);
        _updateGroup(
            newGroupId,
            _subOperatorsArr1(1, MAX_BP),
            _extOperatorsArr0()
        );

        IMetaOperatorRegistry.OperatorGroup memory groupInfo = registry
            .getOperatorGroup(newGroupId);
        assertEq(groupInfo.subNodeOperators.length, 1);
        assertEq(groupInfo.subNodeOperators[0].nodeOperatorId, 1);
        assertEq(groupInfo.subNodeOperators[0].share, MAX_BP);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_updateGroup_OnlyExternalOperators() public {
        externalModule.mock_setNodeOperatorsCount(2);
        uint256 newGroupId = registry.getOperatorGroupsCount();

        bytes memory initialExternal = _createDefaultGroupWithExternal(
            0,
            MAX_BP,
            0
        );

        bytes memory updatedExternal = _norData(uint8(EXTERNAL_MODULE_ID), 1);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(updatedExternal);

        vm.prank(groupManager);
        _updateGroup(
            newGroupId,
            _subOperatorsArr1(0, MAX_BP),
            externalOperators
        );

        IMetaOperatorRegistry.OperatorGroup memory groupInfo = registry
            .getOperatorGroup(newGroupId);
        assertEq(groupInfo.externalOperators.length, 1);
        assertEq(groupInfo.externalOperators[0].data, updatedExternal);

        (bool wasInGroup, uint256 oldGroupId) = registry
            .getExternalOperatorGroupMembership(initialExternal);
        assertFalse(wasInGroup);
        assertEq(oldGroupId, 0);

        (bool isInGroup, uint256 groupId) = registry
            .getExternalOperatorGroupMembership(updatedExternal);
        assertTrue(isInGroup);
        assertEq(groupId, newGroupId);
    }

    function test_updateGroup_ToEmptyGroup() public {
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.prank(groupManager);
        _updateGroup(0, _subOperatorsArr0(), _extOperatorsArr0());

        IMetaOperatorRegistry.OperatorGroup memory groupInfo = registry
            .getOperatorGroup(0);
        assertEq(groupInfo.subNodeOperators.length, 0);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_updateGroup_RemovesMemberships() public {
        externalModule.mock_setNodeOperatorsCount(1);
        bytes memory externalData = _createDefaultGroupWithExternal({
            subNodeOperatorId: 0,
            share: MAX_BP,
            externalNodeOperatorId: 0
        });

        vm.prank(groupManager);
        _updateGroup(0, _subOperatorsArr0(), _extOperatorsArr0());

        (bool isInGroup, uint256 groupId) = registry
            .getNodeOperatorGroupMembership(0);
        assertFalse(isInGroup);
        assertEq(groupId, 0);

        (bool isInExternalGroup, uint256 externalGroupId) = registry
            .getExternalOperatorGroupMembership(externalData);
        assertFalse(isInExternalGroup);
        assertEq(externalGroupId, 0);
    }

    function test_updateGroup_RevertWhen_GroupIdInvalid() public {
        vm.startPrank(groupManager);
        vm.expectRevert(IMetaOperatorRegistry.InvalidOperatorGroupId.selector);
        _updateGroup(1, _subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());
        vm.stopPrank();
    }

    function test_updateGroup_RevertWhen_SubOperatorsEmptyButExternalNotEmpty()
        public
    {
        externalModule.mock_setNodeOperatorsCount(1);

        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID), 0)
            );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.startPrank(groupManager);
        vm.expectRevert(IMetaOperatorRegistry.InvalidOperatorGroup.selector);
        _updateGroup(0, _subOperatorsArr0(), externalOperators);
        vm.stopPrank();
    }

    function test_updateGroup_RevertWhen_SubOperatorAlreadyInAnotherGroup()
        public
    {
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        vm.startPrank(groupManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMetaOperatorRegistry.NodeOperatorAlreadyInGroup.selector,
                uint256(1)
            )
        );
        _updateGroup(0, _subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());
        vm.stopPrank();
    }
}

contract MetaOperatorRegistryTestGroupsGetters is
    MetaOperatorRegistryTestGroupsBase
{
    function test_getOperatorGroup_ReturnsGroup() public {
        IMetaOperatorRegistry.SubNodeOperator memory op0 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 0, share: 7000 });
        IMetaOperatorRegistry.SubNodeOperator memory op1 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 1, share: 3000 });
        IMetaOperatorRegistry.SubNodeOperator[]
            memory subOperators = _subOperatorsArr2(op0, op1);
        bytes memory externalData = _norData(uint8(EXTERNAL_MODULE_ID), 0);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(externalData);

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        IMetaOperatorRegistry.OperatorGroup memory stored = registry
            .getOperatorGroup(0);
        assertEq(stored.subNodeOperators.length, 2);
        assertEq(stored.subNodeOperators[0].nodeOperatorId, 0);
        assertEq(stored.subNodeOperators[0].share, 7000);
        assertEq(stored.subNodeOperators[1].nodeOperatorId, 1);
        assertEq(stored.subNodeOperators[1].share, 3000);
        assertEq(stored.externalOperators.length, 1);
        assertEq(stored.externalOperators[0].data, externalData);
    }

    function test_getOperatorGroup_RevertWhen_InvalidGroupId() public {
        vm.expectRevert(IMetaOperatorRegistry.InvalidOperatorGroupId.selector);
        registry.getOperatorGroup(0);
    }

    function test_getOperatorGroupsCount_ReturnsCount() public {
        assertEq(registry.getOperatorGroupsCount(), 0);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        assertEq(registry.getOperatorGroupsCount(), 1);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        assertEq(registry.getOperatorGroupsCount(), 2);
    }

    function test_getNodeOperatorGroupMembership_ReturnsFalseWhenDoesNotExist()
        public
    {
        uint256 nonExistentGroupId = registry.getOperatorGroupsCount();
        (bool isInGroup, uint256 groupId) = registry
            .getNodeOperatorGroupMembership(nonExistentGroupId);
        assertFalse(isInGroup);
        assertEq(groupId, 0);
    }

    function test_getExternalOperatorGroupMembership_ReturnsFalseWhenDoesNotExist()
        public
    {
        uint256 nonExistentNoId = externalModule.getNodeOperatorsCount();
        (bool isInGroup, uint256 groupId) = registry
            .getExternalOperatorGroupMembership(
                _norData(uint8(EXTERNAL_MODULE_ID), uint64(nonExistentNoId))
            );
        assertFalse(isInGroup);
        assertEq(groupId, 0);
    }

    function test_membership_ReturnsFalseAfterUpdateToEmpty() public {
        externalModule.mock_setNodeOperatorsCount(1);

        bytes memory externalData = _norData(uint8(EXTERNAL_MODULE_ID), 0);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(externalData);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);

        vm.prank(groupManager);
        _updateGroup(0, _subOperatorsArr0(), _extOperatorsArr0());

        (bool isInGroup, uint256 groupId) = registry
            .getNodeOperatorGroupMembership(0);
        assertFalse(isInGroup);
        assertEq(groupId, 0);

        (bool isInExternalGroup, uint256 externalGroupId) = registry
            .getExternalOperatorGroupMembership(externalData);
        assertFalse(isInExternalGroup);
        assertEq(externalGroupId, 0);
    }
}

contract MetaOperatorRegistryTestWeights is MetaOperatorRegistryTestGroupsBase {
    function test_getNodeOperatorWeightAndExternalStake_ReturnsZeroWhenNotInGroup()
        public
    {
        (uint256 weight, uint256 externalStake) = registry
            .getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, 0);
        assertEq(externalStake, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_ReturnsZeroWhenWeightZero()
        public
    {
        uint64 noId = 0;
        uint256 bondCurveId = module.ACCOUNTING().getBondCurveId(noId);
        assertEq(registry.getBondCurveWeight(bondCurveId), 0);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(noId, MAX_BP), _extOperatorsArr0());

        (uint256 weight, uint256 externalStake) = registry
            .getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, 0);
        assertEq(externalStake, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_ReturnsWeightNoExternalStake()
        public
    {
        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaOperatorRegistry.SubNodeOperator[]
            memory subOperators = new IMetaOperatorRegistry.SubNodeOperator[](
                3
            );
        subOperators[0] = IMetaOperatorRegistry.SubNodeOperator({
            nodeOperatorId: 0,
            share: 7000
        });
        subOperators[1] = IMetaOperatorRegistry.SubNodeOperator({
            nodeOperatorId: 1,
            share: 3000
        });
        subOperators[2] = IMetaOperatorRegistry.SubNodeOperator({
            nodeOperatorId: 2,
            share: 0
        });

        vm.prank(groupManager);
        _createGroup(subOperators, _extOperatorsArr0());

        (uint256 weight0, uint256 externalStake0) = registry
            .getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight0, 7000);
        assertEq(externalStake0, 0);

        (uint256 weight2, uint256 externalStake2) = registry
            .getNodeOperatorWeightAndExternalStake(2);
        assertEq(weight2, 0);
        assertEq(externalStake2, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_RevertWhen_ModuleNotCached()
        public
    {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 1, 2);

        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaOperatorRegistry.SubNodeOperator[]
            memory subOperators = _subOperatorsArr1(0, MAX_BP);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID), 0)
            );

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        registry.mock_setModuleAddress(EXTERNAL_MODULE_ID, address(0));
        vm.expectRevert(IMetaOperatorRegistry.UnknownModule.selector);
        registry.getNodeOperatorWeightAndExternalStake(0);
    }

    function test_getNodeOperatorWeightAndExternalStake_DistributesExternalStake()
        public
    {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 2, 10);

        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaOperatorRegistry.SubNodeOperator memory op0 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 0, share: 5000 });
        IMetaOperatorRegistry.SubNodeOperator memory op1 = IMetaOperatorRegistry
            .SubNodeOperator({ nodeOperatorId: 1, share: 5000 });
        IMetaOperatorRegistry.SubNodeOperator[]
            memory subOperators = _subOperatorsArr2(op0, op1);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID), 0)
            );

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        (uint256 weight0, uint256 externalStake0) = registry
            .getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight0, 5000);
        assertEq(externalStake0, 128 ether);

        (uint256 weight1, uint256 externalStake1) = registry
            .getNodeOperatorWeightAndExternalStake(1);
        assertEq(weight1, 5000);
        assertEq(externalStake1, 128 ether);
    }

    function test_getNodeOperatorWeightAndExternalStake_SkipsZeroActiveValidators()
        public
    {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 10, 10);

        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaOperatorRegistry.SubNodeOperator[]
            memory subOperators = _subOperatorsArr1(0, MAX_BP);
        IMetaOperatorRegistry.ExternalOperator[]
            memory externalOperators = _extOperatorsArr1(
                _norData(uint8(EXTERNAL_MODULE_ID), 0)
            );

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        (uint256 weight, uint256 externalStake) = registry
            .getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, CURVE_WEIGHT);
        assertEq(externalStake, 0);
    }
}

contract MetaOperatorRegistryTestBondCurve is
    MetaOperatorRegistryTestGroupsBase
{
    function test_getBondCurveWeight_ReturnsValue() public {
        assertEq(registry.getBondCurveWeight(0), 0);

        _mockBondCurveWeightHook();
        vm.prank(groupManager);
        registry.setBondCurveWeight(0, 123);

        assertEq(registry.getBondCurveWeight(0), 123);
    }

    function test_setBondCurveWeight_EmitsAndCallsHook() public {
        // TODO: Replace mockCall with a real module hook expectation.
        _mockBondCurveWeightHook();
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICuratedModule.onBondCurveWeightUpdated.selector
            )
        );
        vm.expectEmit(address(registry));
        emit IMetaOperatorRegistry.BondCurveWeightSet(0, 123);

        vm.prank(groupManager);
        registry.setBondCurveWeight(0, 123);
    }

    function test_setBondCurveWeight_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, registry.MANAGE_OPERATOR_GROUPS_ROLE());
        vm.prank(stranger);
        registry.setBondCurveWeight(0, 123);
    }

    function test_setBondCurveWeight_RevertWhen_SameWeight() public {
        {
            _mockBondCurveWeightHook();
            vm.prank(groupManager);
            registry.setBondCurveWeight(0, 123);
        }

        vm.prank(groupManager);
        vm.expectRevert(IMetaOperatorRegistry.SameBondCurveWeight.selector);
        registry.setBondCurveWeight(0, 123);
    }

    function test_onNodeOperatorWeightUpdated_RevertWhen_NotInGroup() public {
        vm.expectRevert(IMetaOperatorRegistry.NodeOperatorNotInGroup.selector);
        registry.onNodeOperatorWeightUpdated(0);
    }
}
