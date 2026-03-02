// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test, Vm } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { MetaRegistry } from "src/MetaRegistry.sol";
import { IMetaRegistry, OperatorMetadata } from "src/interfaces/IMetaRegistry.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IStakingRouter } from "src/interfaces/IStakingRouter.sol";
import { ExternalOperatorLib } from "src/lib/ExternalOperatorLib.sol";

import { CuratedMock } from "../helpers/mocks/CuratedMock.sol";
import { NodeOperatorsRegistryMock } from "../helpers/mocks/NodeOperatorsRegistryMock.sol";
import { StakingRouterMock } from "../helpers/mocks/StakingRouterMock.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract MetaRegistryForTest is MetaRegistry {
    constructor(address module) MetaRegistry(module) {}

    function mock_setModuleAddressInCache(uint256 moduleId, address moduleAddress) external {
        _storage().moduleAddressCache[moduleId] = moduleAddress;
    }

    function mock_getModuleAddressInCache(uint256 moduleId) external view returns (address moduleAddress) {
        moduleAddress = _storage().moduleAddressCache[moduleId];
    }
}

contract MetaRegistryTestBase is Test, Utilities, Fixtures {
    CuratedMock public module;
    StakingRouterMock public stakingRouter;
    MetaRegistryForTest public registry;

    address public admin;
    address public metadataAdmin;
    address public groupManager;
    address public bondCurveWeightManager;
    address public nodeOperatorOwner;
    address public stranger;

    OperatorMetadata internal emptyOperatorMetadata;

    uint8 internal constant MODULE_ID = 1;
    uint8 internal constant EXTERNAL_MODULE_ID = MODULE_ID + 1;
    uint256 internal constant NO_GROUP_ID = 0;
    uint256 internal constant CURVE_WEIGHT = 10000;
    uint16 internal constant MAX_BP = 10000;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        metadataAdmin = nextAddress("METADATA_ADMIN");
        groupManager = nextAddress("GROUP_MANAGER");
        bondCurveWeightManager = nextAddress("BOND_CURVE_WEIGHT_MANAGER");
        nodeOperatorOwner = nextAddress("NODE_OPERATOR_OWNER");
        stranger = nextAddress("STRANGER");

        module = new CuratedMock();
        module.mock_setNodeOperatorsCount(3);
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: nodeOperatorOwner,
                rewardAddress: nodeOperatorOwner,
                extendedManagerPermissions: true
            })
        );
        stakingRouter = StakingRouterMock(module.LIDO_LOCATOR().stakingRouter());
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        stakingRouter.setModules(modules);

        registry = new MetaRegistryForTest(address(module));
        _enableInitializers(address(registry));
        registry.initialize(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.SET_OPERATOR_INFO_ROLE(), metadataAdmin);
        registry.grantRole(registry.MANAGE_OPERATOR_GROUPS_ROLE(), groupManager);
        registry.grantRole(registry.SET_BOND_CURVE_WEIGHT_ROLE(), bondCurveWeightManager);
        vm.stopPrank();
    }
}

contract MetaRegistryTestGroupsBase is MetaRegistryTestBase {
    NodeOperatorsRegistryMock public externalModule;

    function setUp() public virtual override {
        super.setUp();

        externalModule = new NodeOperatorsRegistryMock();
        externalModule.mock_setNodeOperatorsCount(2);
        stakingRouter.addModule(EXTERNAL_MODULE_ID, address(externalModule));
    }

    function _norData(uint8 moduleId_, uint64 nodeOperatorId_) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), moduleId_, nodeOperatorId_);
    }

    function _externalOperator(bytes memory data) internal pure returns (IMetaRegistry.ExternalOperator memory op) {
        op = IMetaRegistry.ExternalOperator({ data: data });
    }

    function _extOperatorsArr0() internal pure returns (IMetaRegistry.ExternalOperator[] memory ops) {}

    function _extOperatorsArr1(bytes memory data) internal pure returns (IMetaRegistry.ExternalOperator[] memory ops) {
        ops = new IMetaRegistry.ExternalOperator[](1);
        ops[0] = _externalOperator(data);
    }

    function _setBondCurveWeight(uint256 curveId, uint256 weight) internal {
        vm.prank(bondCurveWeightManager);
        registry.setBondCurveWeight(curveId, weight);
    }

    function _createGroup(
        IMetaRegistry.SubNodeOperator[] memory subNodeOperators,
        IMetaRegistry.ExternalOperator[] memory externalOperators
    ) internal {
        registry.createOrUpdateOperatorGroup(
            NO_GROUP_ID,
            IMetaRegistry.OperatorGroup({ subNodeOperators: subNodeOperators, externalOperators: externalOperators })
        );
    }

    function _updateGroup(
        uint256 groupId,
        IMetaRegistry.SubNodeOperator[] memory subNodeOperators,
        IMetaRegistry.ExternalOperator[] memory externalOperators
    ) internal {
        registry.createOrUpdateOperatorGroup(
            groupId,
            IMetaRegistry.OperatorGroup({ subNodeOperators: subNodeOperators, externalOperators: externalOperators })
        );
    }

    function _setExternalNodeOperator(
        uint256 nodeOperatorId,
        uint64 exitedValidators,
        uint64 depositedValidators
    ) internal {
        NodeOperatorsRegistryMock.NodeOperatorData memory data;

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
        externalData = _norData(EXTERNAL_MODULE_ID, externalNodeOperatorId);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(externalData);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(subNodeOperatorId, share), externalOperators);
    }

    function _subOperatorsArr0() internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {}

    function _subOperatorsArr1(
        uint64 nodeOperatorId,
        uint16 share
    ) internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {
        ops = new IMetaRegistry.SubNodeOperator[](1);
        ops[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: nodeOperatorId, share: share });
    }

    function _subOperatorsArr2(
        IMetaRegistry.SubNodeOperator memory op0,
        IMetaRegistry.SubNodeOperator memory op1
    ) internal pure returns (IMetaRegistry.SubNodeOperator[] memory ops) {
        ops = new IMetaRegistry.SubNodeOperator[](2);
        ops[0] = op0;
        ops[1] = op1;
    }
}

contract MetaRegistryTestConstructor is MetaRegistryTestBase {
    function test_constructor_SetsImmutables() public {
        MetaRegistry r = new MetaRegistry(address(module));
        assertEq(address(r.STAKING_ROUTER()), address(stakingRouter));
        assertEq(address(r.MODULE()), address(module));
        assertEq(address(r.ACCOUNTING()), address(module.ACCOUNTING()));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(IMetaRegistry.ZeroModuleAddress.selector);
        new MetaRegistry(address(0));
    }
}

contract MetaRegistryTestInitialize is MetaRegistryTestBase {
    function test_initialize_SetsAdmin() public {
        MetaRegistry r = new MetaRegistry(address(module));
        _enableInitializers(address(r));
        r.initialize(admin);
        assertTrue(r.hasRole(r.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_CreatesDefaultEmptyGroup() public {
        MetaRegistry r = new MetaRegistry(address(module));
        _enableInitializers(address(r));
        r.initialize(admin);

        assertEq(r.getOperatorGroupsCount(), 1);
        IMetaRegistry.OperatorGroup memory groupInfo = r.getOperatorGroup(r.NO_GROUP_ID());
        assertEq(groupInfo.subNodeOperators.length, 0);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        MetaRegistry r = new MetaRegistry(address(module));
        _enableInitializers(address(r));
        vm.expectRevert(IMetaRegistry.ZeroAdminAddress.selector);
        r.initialize(address(0));
    }

    function test_initialize_RevertWhen_DoubleCall() public {
        MetaRegistry r = new MetaRegistry(address(module));
        _enableInitializers(address(r));
        r.initialize(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        r.initialize(admin);
    }
}

contract MetaRegistryTestSetMetadataAsAdmin is MetaRegistryTestBase {
    function test_setOperatorMetadataAsAdmin() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory exp = OperatorMetadata({
            name: "Alpha",
            description: "The first",
            ownerEditsRestricted: false
        });

        vm.prank(metadataAdmin);
        vm.expectEmit(address(registry));
        emit IMetaRegistry.OperatorMetadataSet(nodeOperatorId, exp);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, exp);

        OperatorMetadata memory got = registry.getOperatorMetadata(nodeOperatorId);
        assertEq(got.name, exp.name);
        assertEq(got.description, exp.description);
        assertEq(got.ownerEditsRestricted, exp.ownerEditsRestricted);
    }

    function test_setMetadataAsAdmin_OverwriteAllowed() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory infoV1 = OperatorMetadata({
            name: "Alpha",
            description: "v1",
            ownerEditsRestricted: false
        });
        OperatorMetadata memory infoV2 = OperatorMetadata({
            name: "Omega",
            description: "v2",
            ownerEditsRestricted: true
        });

        vm.startPrank(metadataAdmin);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, infoV1);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, infoV2);
        vm.stopPrank();

        OperatorMetadata memory got = registry.getOperatorMetadata(nodeOperatorId);

        assertEq(got.name, infoV2.name);
        assertEq(got.description, infoV2.description);
        assertEq(got.ownerEditsRestricted, infoV2.ownerEditsRestricted);
    }

    function test_setOperatorMetadataAsAdmin_revertWhen_NameTooLong() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory exp = OperatorMetadata({
            name: string(abi.encodePacked(randomBytes(257))),
            description: "The first",
            ownerEditsRestricted: false
        });

        vm.prank(metadataAdmin);
        vm.expectRevert(IMetaRegistry.OperatorNameTooLong.selector);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, exp);
    }

    function test_setOperatorMetadataAsAdmin_revertWhen_DescriptionTooLong() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory exp = OperatorMetadata({
            name: "Alpha",
            description: string(abi.encodePacked(randomBytes(1025))),
            ownerEditsRestricted: false
        });

        vm.prank(metadataAdmin);
        vm.expectRevert(IMetaRegistry.OperatorDescriptionTooLong.selector);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, exp);
    }

    function test_setOperatorMetadataAsAdmin_RevertWhen_NoRole() public {
        uint256 nodeOperatorId = 0;

        expectRoleRevert(stranger, registry.SET_OPERATOR_INFO_ROLE());
        vm.prank(stranger);
        registry.setOperatorMetadataAsAdmin(nodeOperatorId, emptyOperatorMetadata);
    }

    function test_setOperatorMetadataAsAdmin_RevertWhen_NodeOperatorDoesNotExist() public {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.prank(metadataAdmin);
        vm.expectRevert(IMetaRegistry.NodeOperatorDoesNotExist.selector);
        registry.setOperatorMetadataAsAdmin(nonExistentNoId, emptyOperatorMetadata);
    }
}

contract MetaRegistryTestSetMetadataAsOwner is MetaRegistryTestBase {
    function test_setOperatorMetadataAsOwner() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory exp = OperatorMetadata({
            name: "Alpha",
            description: "The first",
            ownerEditsRestricted: false
        });

        vm.prank(nodeOperatorOwner);
        vm.expectEmit(address(registry));
        emit IMetaRegistry.OperatorMetadataSet(nodeOperatorId, exp);
        registry.setOperatorMetadataAsOwner(nodeOperatorId, exp.name, exp.description);

        OperatorMetadata memory got = registry.getOperatorMetadata(nodeOperatorId);
        assertEq(got.name, exp.name);
        assertEq(got.description, exp.description);
        assertEq(got.ownerEditsRestricted, exp.ownerEditsRestricted);
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_Restricted() public {
        uint256 nodeOperatorId = 0;

        vm.prank(metadataAdmin);
        registry.setOperatorMetadataAsAdmin(
            nodeOperatorId,
            OperatorMetadata({ name: "", description: "", ownerEditsRestricted: true })
        );

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IMetaRegistry.OwnerEditsRestricted.selector);
        registry.setOperatorMetadataAsOwner(nodeOperatorId, "Name", "Desc");
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_NotOwner() public {
        uint256 nodeOperatorId = 0;

        vm.prank(stranger);
        vm.expectRevert(IMetaRegistry.SenderIsNotEligible.selector);
        registry.setOperatorMetadataAsOwner(nodeOperatorId, "Name", "Desc");
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_NodeOperatorDoesNotExist() public {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IMetaRegistry.NodeOperatorDoesNotExist.selector);
        registry.setOperatorMetadataAsOwner(nonExistentNoId, "Name", "Desc");
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_NameTooLong() public {
        uint256 nodeOperatorId = 0;

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IMetaRegistry.OperatorNameTooLong.selector);
        registry.setOperatorMetadataAsOwner(nodeOperatorId, string(abi.encodePacked(randomBytes(257))), "Desc");
    }

    function test_setOperatorMetadataAsOwner_RevertWhen_DescriptionTooLong() public {
        uint256 nodeOperatorId = 0;

        vm.prank(nodeOperatorOwner);
        vm.expectRevert(IMetaRegistry.OperatorDescriptionTooLong.selector);
        registry.setOperatorMetadataAsOwner(nodeOperatorId, "Name", string(abi.encodePacked(randomBytes(1025))));
    }
}

contract MetaRegistryTestGetMetadata is MetaRegistryTestBase {
    function test_getOperatorMetadata_ReturnsEmptyWhenUnset() public {
        uint256 nodeOperatorId = 0;

        OperatorMetadata memory got = registry.getOperatorMetadata(nodeOperatorId);

        assertEq(got.name, emptyOperatorMetadata.name);
        assertEq(got.description, emptyOperatorMetadata.description);
        assertEq(got.ownerEditsRestricted, emptyOperatorMetadata.ownerEditsRestricted);
    }
}

contract MetaRegistryTestGroupsCreate is MetaRegistryTestGroupsBase {
    function test_createGroup_CreatesGroup() public {
        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 4000 });
        bytes memory externalData = _norData(EXTERNAL_MODULE_ID, 0);
        IMetaRegistry.SubNodeOperator[] memory subNodeOperators = _subOperatorsArr2(op0, op1);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(externalData);

        vm.expectEmit(address(registry));
        uint256 newGroupId = registry.getOperatorGroupsCount();
        emit IMetaRegistry.OperatorGroupCreated(
            newGroupId,
            IMetaRegistry.OperatorGroup({ subNodeOperators: subNodeOperators, externalOperators: externalOperators })
        );

        vm.prank(groupManager);
        _createGroup(subNodeOperators, externalOperators);

        assertEq(registry.getOperatorGroupsCount(), 2);
        uint256 groupId0 = registry.getNodeOperatorGroupId(op0.nodeOperatorId);
        assertTrue(groupId0 != NO_GROUP_ID);
        assertEq(groupId0, newGroupId);

        uint256 groupId1 = registry.getNodeOperatorGroupId(op1.nodeOperatorId);
        assertTrue(groupId1 != NO_GROUP_ID);
        assertEq(groupId1, newGroupId);

        uint256 externalGroupId = registry.getExternalOperatorGroupId(_externalOperator(externalData));
        assertTrue(externalGroupId != NO_GROUP_ID);
        assertEq(externalGroupId, newGroupId);

        IMetaRegistry.OperatorGroup memory stored = registry.getOperatorGroup(newGroupId);
        assertEq(stored.subNodeOperators.length, 2);
        assertEq(stored.externalOperators.length, 1);
        assertEq(stored.externalOperators[0].data, externalData);
    }

    function test_createGroup_NoExternalOperators() public {
        uint256 newGroupId = registry.getOperatorGroupsCount();

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        IMetaRegistry.OperatorGroup memory stored = registry.getOperatorGroup(newGroupId);
        assertEq(stored.externalOperators.length, 0);
    }

    function test_createGroup_RevertWhen_NotRole() public {
        expectRoleRevert(stranger, registry.MANAGE_OPERATOR_GROUPS_ROLE());
        vm.prank(stranger);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_EmptyGroup() public {
        vm.expectRevert(IMetaRegistry.InvalidOperatorGroup.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr0(), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_ExternalOnlyGroupOnCreate() public {
        vm.expectRevert(IMetaRegistry.InvalidOperatorGroup.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr0(), _extOperatorsArr1(hex""));
    }

    function test_createGroup_RevertWhen_SharesNotMaxBP() public {
        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 3000 });

        vm.expectRevert(IMetaRegistry.InvalidSubNodeOperatorShares.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op0, op1), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_SubOperatorDoesNotExist() public {
        uint256 nonExistentNoId = module.getNodeOperatorsCount();

        vm.expectRevert(IMetaRegistry.NodeOperatorDoesNotExist.selector);
        vm.prank(groupManager);
        // forge-lint: disable-next-line(unsafe-typecast)
        _createGroup(_subOperatorsArr1(uint64(nonExistentNoId), MAX_BP), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_SubOperatorDuplicatedInGroup() public {
        IMetaRegistry.SubNodeOperator memory op = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 5000 });
        vm.expectRevert(abi.encodeWithSelector(IMetaRegistry.NodeOperatorAlreadyInGroup.selector, op.nodeOperatorId));
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op, op), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_SubOperatorAlreadyInAnotherGroup() public {
        uint64 nodeOperatorId = 0;

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(nodeOperatorId, MAX_BP), _extOperatorsArr0());

        vm.expectRevert(abi.encodeWithSelector(IMetaRegistry.NodeOperatorAlreadyInGroup.selector, nodeOperatorId));
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(nodeOperatorId, MAX_BP), _extOperatorsArr0());
    }

    function test_createGroup_RevertWhen_ExternalOperatorDuplicatedInGroup() public {
        externalModule.mock_setNodeOperatorsCount(1);
        IMetaRegistry.ExternalOperator[] memory externalOperators = new IMetaRegistry.ExternalOperator[](2);
        IMetaRegistry.ExternalOperator memory op = _externalOperator(_norData(EXTERNAL_MODULE_ID, 0));

        externalOperators[0] = op;
        externalOperators[1] = op;

        vm.expectRevert(IMetaRegistry.AlreadyUsedAsExternalOperator.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalOperatorAlreadyUsedInAnotherGroup() public {
        externalModule.mock_setNodeOperatorsCount(2);
        uint64 subOp1Id = 0;
        uint64 subOp2Id = 1;

        uint64 extOpId = 0;

        bytes memory extOpData = _createDefaultGroupWithExternal(subOp1Id, MAX_BP, extOpId);

        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(extOpData);

        vm.expectRevert(IMetaRegistry.AlreadyUsedAsExternalOperator.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(subOp2Id, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalOperatorTypeUnsupported() public {
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(
            abi.encodePacked(uint8(1), EXTERNAL_MODULE_ID, uint64(0))
        );
        vm.expectRevert(ExternalOperatorLib.InvalidExternalOperatorDataEntry.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalModuleDoesNotExist() public {
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(
            _norData(uint8(EXTERNAL_MODULE_ID + 1), 0)
        );

        vm.expectRevert(StakingRouterMock.StakingModuleUnregistered.selector);
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);
    }

    function test_createGroup_RevertWhen_ExternalNodeOperatorDoesNotExist() public {
        uint256 nonExistentNoId = externalModule.getNodeOperatorsCount();
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(
            // forge-lint: disable-next-line(unsafe-typecast)
            _norData(EXTERNAL_MODULE_ID, uint64(nonExistentNoId))
        );

        vm.startPrank(groupManager);
        vm.expectRevert(IMetaRegistry.NodeOperatorDoesNotExist.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        _createGroup(_subOperatorsArr1(uint64(nonExistentNoId), MAX_BP), externalOperators);
        vm.stopPrank();
    }

    function test_createGroup_CallsNotifyNodeOperatorWeightChange() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 4000 });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(op0.nodeOperatorId))
        );
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(op1.nodeOperatorId))
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op0, op1), _extOperatorsArr0());
    }
}

contract MetaRegistryTestGroupsUpdate is MetaRegistryTestGroupsBase {
    function test_updateGroup_OnlySubOperators() public {
        uint256 newGroupId = registry.getOperatorGroupsCount();
        _createDefaultGroupWithExternal(0, MAX_BP, 0);

        IMetaRegistry.SubNodeOperator[] memory subOperators = _subOperatorsArr1(1, MAX_BP);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr0();

        vm.expectEmit(address(registry));
        emit IMetaRegistry.OperatorGroupUpdated(
            newGroupId,
            IMetaRegistry.OperatorGroup({ subNodeOperators: subOperators, externalOperators: externalOperators })
        );

        vm.prank(groupManager);
        _updateGroup(newGroupId, subOperators, externalOperators);

        IMetaRegistry.OperatorGroup memory groupInfo = registry.getOperatorGroup(newGroupId);
        assertEq(groupInfo.subNodeOperators.length, 1);
        assertEq(groupInfo.subNodeOperators[0].nodeOperatorId, 1);
        assertEq(groupInfo.subNodeOperators[0].share, MAX_BP);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_updateGroup_OnlyExternalOperators() public {
        externalModule.mock_setNodeOperatorsCount(2);
        uint256 newGroupId = registry.getOperatorGroupsCount();

        bytes memory initialExternal = _createDefaultGroupWithExternal(0, MAX_BP, 0);

        bytes memory updatedExternal = _norData(EXTERNAL_MODULE_ID, 1);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(updatedExternal);

        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr1(0, MAX_BP), externalOperators);

        IMetaRegistry.OperatorGroup memory groupInfo = registry.getOperatorGroup(newGroupId);
        assertEq(groupInfo.externalOperators.length, 1);
        assertEq(groupInfo.externalOperators[0].data, updatedExternal);

        uint256 oldGroupId = registry.getExternalOperatorGroupId(_externalOperator(initialExternal));
        assertEq(oldGroupId, NO_GROUP_ID);

        uint256 groupId = registry.getExternalOperatorGroupId(_externalOperator(updatedExternal));
        assertTrue(groupId != NO_GROUP_ID);
        assertEq(groupId, newGroupId);
    }

    function test_updateGroup_ToEmptyGroup() public {
        uint256 newGroupId = registry.getOperatorGroupsCount();

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.expectEmit(address(registry));
        emit IMetaRegistry.OperatorGroupCleared(newGroupId);

        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr0(), _extOperatorsArr0());

        IMetaRegistry.OperatorGroup memory groupInfo = registry.getOperatorGroup(newGroupId);
        assertEq(groupInfo.subNodeOperators.length, 0);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_updateGroup_RemovesMemberships() public {
        externalModule.mock_setNodeOperatorsCount(1);
        uint256 newGroupId = registry.getOperatorGroupsCount();
        bytes memory externalData = _createDefaultGroupWithExternal({
            subNodeOperatorId: 0,
            share: MAX_BP,
            externalNodeOperatorId: 0
        });

        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr0(), _extOperatorsArr0());

        uint256 groupId = registry.getNodeOperatorGroupId(0);
        assertEq(groupId, NO_GROUP_ID);

        uint256 externalGroupId = registry.getExternalOperatorGroupId(_externalOperator(externalData));
        assertEq(externalGroupId, NO_GROUP_ID);
    }

    function test_updateGroup_ResetsEffectiveWeightForRemovedOperators() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 4000 });

        uint256 newGroupId = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op0, op1), _extOperatorsArr0());

        uint256[] memory weightsBefore = registry.getOperatorWeights(UintArr(0, 1));
        assertEq(weightsBefore[0], 6000);
        assertEq(weightsBefore[1], 4000);

        // Update group to only contain operator 1 (removing operator 0).
        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        uint256[] memory weightsAfter = registry.getOperatorWeights(UintArr(0, 1));
        assertEq(weightsAfter[0], 0);
        assertEq(weightsAfter[1], CURVE_WEIGHT); // 10000 * 10000 / 10000

        (uint256 w0, ) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(w0, 0);
    }

    function test_updateGroup_ResetsEffectiveWeightOnEmptyUpdate() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        uint256 newGroupId = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        uint256[] memory weightsBefore = registry.getOperatorWeights(UintArr(0));
        assertEq(weightsBefore[0], CURVE_WEIGHT);

        // Update group to empty.
        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr0(), _extOperatorsArr0());

        uint256[] memory weightsAfter = registry.getOperatorWeights(UintArr(0));
        assertEq(weightsAfter[0], 0);
    }

    function test_updateGroup_RemovedOperatorCanBeReAddedToNewGroup() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        uint256 groupId1 = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        // Update group1 to only contain operator 1 (freeing operator 0).
        vm.prank(groupManager);
        _updateGroup(groupId1, _subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        // Operator 0 should be free to join a new group.
        uint256 groupId2 = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        uint256 membership = registry.getNodeOperatorGroupId(0);
        assertEq(membership, groupId2);

        uint256[] memory weights = registry.getOperatorWeights(UintArr(0));
        assertEq(weights[0], CURVE_WEIGHT);
    }

    function test_updateGroup_RevertWhen_GroupIdInvalid() public {
        vm.startPrank(groupManager);
        vm.expectRevert(IMetaRegistry.InvalidOperatorGroupId.selector);
        _updateGroup(1, _subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());
        vm.stopPrank();
    }

    function test_updateGroup_RevertWhen_SubOperatorsEmptyButExternalNotEmpty() public {
        externalModule.mock_setNodeOperatorsCount(1);

        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0));
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());
        uint256 groupId = registry.getOperatorGroupsCount() - 1;

        vm.startPrank(groupManager);
        vm.expectRevert(IMetaRegistry.InvalidOperatorGroup.selector);
        _updateGroup(groupId, _subOperatorsArr0(), externalOperators);
        vm.stopPrank();
    }

    function test_updateGroup_RevertWhen_SubOperatorAlreadyInAnotherGroup() public {
        uint256 groupId0 = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        vm.startPrank(groupManager);
        vm.expectRevert(abi.encodeWithSelector(IMetaRegistry.NodeOperatorAlreadyInGroup.selector, uint256(1)));
        _updateGroup(groupId0, _subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());
        vm.stopPrank();
    }

    function test_updateGroup_CallsNotifyNodeOperatorWeightChange() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        uint256 newGroupId = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        // Calls for both removed and added operators.
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(0))
        );
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(1))
        );
        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());
    }

    function test_updateGroup_CallsNotifyNodeOperatorWeightChangeOnEmptyUpdate() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);
        uint256 newGroupId = registry.getOperatorGroupsCount();
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(0))
        );
        vm.prank(groupManager);
        _updateGroup(newGroupId, _subOperatorsArr0(), _extOperatorsArr0());
    }
}

contract MetaRegistryTestGroupsGetters is MetaRegistryTestGroupsBase {
    function test_getOperatorGroup_ReturnsGroup() public {
        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 7000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 3000 });
        IMetaRegistry.SubNodeOperator[] memory subOperators = _subOperatorsArr2(op0, op1);
        bytes memory externalData = _norData(EXTERNAL_MODULE_ID, 0);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(externalData);
        uint256 newGroupId = registry.getOperatorGroupsCount();

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        IMetaRegistry.OperatorGroup memory stored = registry.getOperatorGroup(newGroupId);
        assertEq(stored.subNodeOperators.length, 2);
        assertEq(stored.subNodeOperators[0].nodeOperatorId, 0);
        assertEq(stored.subNodeOperators[0].share, 7000);
        assertEq(stored.subNodeOperators[1].nodeOperatorId, 1);
        assertEq(stored.subNodeOperators[1].share, 3000);
        assertEq(stored.externalOperators.length, 1);
        assertEq(stored.externalOperators[0].data, externalData);
    }

    function test_getOperatorGroup_RevertWhen_InvalidGroupId() public {
        uint256 invalidGroupId = registry.getOperatorGroupsCount();
        vm.expectRevert(IMetaRegistry.InvalidOperatorGroupId.selector);
        registry.getOperatorGroup(invalidGroupId);
    }

    function test_getOperatorGroupsCount_ReturnsCount() public {
        assertEq(registry.getOperatorGroupsCount(), 1);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr0());

        assertEq(registry.getOperatorGroupsCount(), 2);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(1, MAX_BP), _extOperatorsArr0());

        assertEq(registry.getOperatorGroupsCount(), 3);
    }

    function test_getNodeOperatorGroupId_ReturnsFalseWhenDoesNotExist() public {
        uint256 nonExistentGroupId = registry.getOperatorGroupsCount();
        uint256 groupId = registry.getNodeOperatorGroupId(nonExistentGroupId);
        assertEq(groupId, NO_GROUP_ID);
    }

    function test_getExternalOperatorGroupId_ReturnsFalseWhenDoesNotExist() public {
        uint256 nonExistentNoId = externalModule.getNodeOperatorsCount();
        uint256 groupId = registry.getExternalOperatorGroupId(
            // forge-lint: disable-next-line(unsafe-typecast)
            _externalOperator(_norData(EXTERNAL_MODULE_ID, uint64(nonExistentNoId)))
        );
        assertEq(groupId, NO_GROUP_ID);
    }

    function test_membership_ReturnsFalseAfterUpdateToEmpty() public {
        externalModule.mock_setNodeOperatorsCount(1);

        bytes memory externalData = _norData(EXTERNAL_MODULE_ID, 0);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(externalData);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), externalOperators);

        vm.prank(groupManager);
        _updateGroup(1, _subOperatorsArr0(), _extOperatorsArr0());

        uint256 groupId = registry.getNodeOperatorGroupId(0);
        assertEq(groupId, NO_GROUP_ID);

        uint256 externalGroupId = registry.getExternalOperatorGroupId(_externalOperator(externalData));
        assertEq(externalGroupId, NO_GROUP_ID);
    }
}

contract MetaRegistryTestWeights is MetaRegistryTestGroupsBase {
    function test_getOperatorWeights_ReturnsWeightsInOrder() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        IMetaRegistry.SubNodeOperator[] memory subOperators = new IMetaRegistry.SubNodeOperator[](2);
        subOperators[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 7000 });
        subOperators[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 3000 });

        vm.prank(groupManager);
        _createGroup(subOperators, _extOperatorsArr0());

        uint256[] memory weights = registry.getOperatorWeights(UintArr(0, 1));
        assertEq(weights, UintArr(7000, 3000));
    }

    function test_getOperatorWeights_ReturnsEmptyWhenNoIds() public {
        uint256[] memory weights = registry.getOperatorWeights(UintArr());
        assertEq(weights.length, 0);
    }

    function test_getOperatorWeights_ReturnsZeroWhenNotInGroup() public {
        uint256[] memory weights = registry.getOperatorWeights(UintArr(2));
        assertEq(weights, UintArr(0));
    }

    function test_getNodeOperatorWeight() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);

        IMetaRegistry.SubNodeOperator[] memory subOperators = new IMetaRegistry.SubNodeOperator[](2);
        subOperators[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 7000 });
        subOperators[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 3000 });

        vm.prank(groupManager);
        _createGroup(subOperators, _extOperatorsArr0());

        uint256 weight = registry.getNodeOperatorWeight(0);
        assertEq(weight, 7000);

        weight = registry.getNodeOperatorWeight(1);
        assertEq(weight, 3000);
    }

    function test_getNodeOperatorWeight_ReturnsZeroWhenNotInGroup() public {
        uint256 weight = registry.getNodeOperatorWeight(2);
        assertEq(weight, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_ReturnsZeroWhenNotInGroup() public {
        (uint256 weight, uint256 externalStake) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, 0);
        assertEq(externalStake, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_ReturnsZeroWhenWeightZero() public {
        uint64 noId = 0;
        uint256 bondCurveId = module.ACCOUNTING().getBondCurveId(noId);
        assertEq(registry.getBondCurveWeight(bondCurveId), 0);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(noId, MAX_BP), _extOperatorsArr0());

        (uint256 weight, uint256 externalStake) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, 0);
        assertEq(externalStake, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_ReturnsWeightNoExternalStake() public {
        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaRegistry.SubNodeOperator[] memory subOperators = new IMetaRegistry.SubNodeOperator[](3);
        subOperators[0] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 7000 });
        subOperators[1] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 3000 });
        subOperators[2] = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 2, share: 0 });

        vm.prank(groupManager);
        _createGroup(subOperators, _extOperatorsArr0());

        (uint256 weight0, uint256 externalStake0) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight0, 7000);
        assertEq(externalStake0, 0);

        (uint256 weight2, uint256 externalStake2) = registry.getNodeOperatorWeightAndExternalStake(2);
        assertEq(weight2, 0);
        assertEq(externalStake2, 0);
    }

    function test_getNodeOperatorWeightAndExternalStake_DistributesExternalStake() public {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 2, 10);

        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 5000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 5000 });
        IMetaRegistry.SubNodeOperator[] memory subOperators = _subOperatorsArr2(op0, op1);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0));

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        (uint256 weight0, uint256 externalStake0) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight0, 5000);
        assertEq(externalStake0, 128 ether);

        (uint256 weight1, uint256 externalStake1) = registry.getNodeOperatorWeightAndExternalStake(1);
        assertEq(weight1, 5000);
        assertEq(externalStake1, 128 ether);
    }

    function test_getNodeOperatorWeightAndExternalStake_SkipsZeroActiveValidators() public {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 10, 10);

        _setBondCurveWeight(0, CURVE_WEIGHT);
        IMetaRegistry.SubNodeOperator[] memory subOperators = _subOperatorsArr1(0, MAX_BP);
        IMetaRegistry.ExternalOperator[] memory externalOperators = _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0));

        vm.prank(groupManager);
        _createGroup(subOperators, externalOperators);

        (uint256 weight, uint256 externalStake) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, CURVE_WEIGHT);
        assertEq(externalStake, 0);
    }
}

contract MetaRegistryTestBondCurve is MetaRegistryTestGroupsBase {
    function test_getBondCurveWeight_ReturnsValue() public {
        assertEq(registry.getBondCurveWeight(0), 0);

        vm.expectCall(address(module), abi.encodeWithSelector(IBaseModule.requestFullDepositInfoUpdate.selector));
        vm.expectEmit(address(registry));
        emit IMetaRegistry.BondCurveWeightSet(0, 123);
        vm.prank(bondCurveWeightManager);
        registry.setBondCurveWeight(0, 123);

        assertEq(registry.getBondCurveWeight(0), 123);
    }

    function test_setBondCurveWeight_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, registry.SET_BOND_CURVE_WEIGHT_ROLE());
        vm.prank(stranger);
        registry.setBondCurveWeight(0, 123);
    }

    function test_setBondCurveWeight_RevertWhen_SameWeight() public {
        {
            vm.prank(bondCurveWeightManager);
            registry.setBondCurveWeight(0, 123);
        }

        vm.prank(bondCurveWeightManager);
        vm.expectRevert(IMetaRegistry.SameBondCurveWeight.selector);
        registry.setBondCurveWeight(0, 123);
    }

    function test_refreshOperatorWeight_NoOpWhen_NotInGroup() public {
        expectNoCall(
            address(module),
            abi.encodeWithSelector(ICuratedModule.notifyNodeOperatorWeightChange.selector, uint256(0))
        );
        registry.refreshOperatorWeight(0);

        (uint256 weight, ) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(weight, 0);
    }

    function test_refreshOperatorWeight_EmitsWhen_WeightChanges() public {
        uint64 noId = 0;

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(noId, MAX_BP), _extOperatorsArr0());

        // Set bond curve weight so refreshing produces a non-zero effective weight.
        _setBondCurveWeight(0, CURVE_WEIGHT);

        vm.expectEmit(address(registry));
        emit IMetaRegistry.NodeOperatorEffectiveWeightChanged(noId, 0, CURVE_WEIGHT);
        registry.refreshOperatorWeight(noId);

        // Verify effective weight is persisted.
        (uint256 weight, ) = registry.getNodeOperatorWeightAndExternalStake(noId);
        assertEq(weight, CURVE_WEIGHT);
    }

    function test_refreshOperatorWeight_NoEventWhen_WeightUnchanged() public {
        uint64 noId = 0;

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(noId, MAX_BP), _extOperatorsArr0());

        // Set bond curve weight and refresh once so the weight is cached.
        _setBondCurveWeight(0, CURVE_WEIGHT);
        registry.refreshOperatorWeight(noId);

        // Refresh again with no underlying change.
        vm.recordLogs();
        registry.refreshOperatorWeight(noId);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // No NodeOperatorEffectiveWeightChanged event should be emitted.
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(
                logs[i].topics[0] != IMetaRegistry.NodeOperatorEffectiveWeightChanged.selector,
                "unexpected weight change event"
            );
        }
    }

    function test_refreshOperatorWeight_UpdatesGroupEffectiveWeightSum() public {
        IMetaRegistry.SubNodeOperator memory op0 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 0, share: 6000 });
        IMetaRegistry.SubNodeOperator memory op1 = IMetaRegistry.SubNodeOperator({ nodeOperatorId: 1, share: 4000 });

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr2(op0, op1), _extOperatorsArr0());

        // Both operators use default curve 0.
        _setBondCurveWeight(0, CURVE_WEIGHT);

        // Refresh first operator to cache its effective weight.
        registry.refreshOperatorWeight(0);
        (uint256 w0, ) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(w0, 6000); // 10000 * 6000 / 10000

        // Refresh second operator.
        registry.refreshOperatorWeight(1);
        (uint256 w1, ) = registry.getNodeOperatorWeightAndExternalStake(1);
        assertEq(w1, 4000); // 10000 * 4000 / 10000

        // Change the bond curve weight. This doesn't auto-refresh cached weights.
        _setBondCurveWeight(0, CURVE_WEIGHT * 2);

        // Refresh only operator 0.
        registry.refreshOperatorWeight(0);

        (uint256 w0After, ) = registry.getNodeOperatorWeightAndExternalStake(0);
        assertEq(w0After, 12000); // 20000 * 6000 / 10000

        // Operator 1 still has stale cached weight.
        (uint256 w1After, ) = registry.getNodeOperatorWeightAndExternalStake(1);
        assertEq(w1After, 4000);
    }
}

contract MetaRegistryTestModuleAddressCache is MetaRegistryTestGroupsBase {
    function test_createGroup_CachesModuleAddressFromRouter() public {
        externalModule.mock_setNodeOperatorsCount(1);
        _setExternalNodeOperator(0, 1, 2);

        vm.expectCall(
            address(stakingRouter),
            abi.encodeWithSelector(IStakingRouter.getStakingModule.selector, EXTERNAL_MODULE_ID)
        );
        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0)));

        assertEq(registry.mock_getModuleAddressInCache(EXTERNAL_MODULE_ID), address(externalModule));
    }

    function test_createGroup_UsesCachedModuleAddressOnCacheHit() public {
        externalModule.mock_setNodeOperatorsCount(2);
        _setBondCurveWeight(0, CURVE_WEIGHT);
        _setExternalNodeOperator(0, 1, 10);
        _setExternalNodeOperator(1, 2, 20);

        // Pre-populate the cache for EXTERNAL_MODULE_ID.
        registry.mock_setModuleAddressInCache(EXTERNAL_MODULE_ID, address(externalModule));

        // Remove the module from the router. If the cache is bypassed
        // during group creation, this will revert.
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        stakingRouter.setModules(modules);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0)));
    }

    function test_getNodeOperatorWeightAndExternalStake_RevertWhen_ModuleAddressNotCached() public {
        externalModule.mock_setNodeOperatorsCount(1);
        _setBondCurveWeight(0, CURVE_WEIGHT);
        _setExternalNodeOperator(0, 1, 2);

        vm.prank(groupManager);
        _createGroup(_subOperatorsArr1(0, MAX_BP), _extOperatorsArr1(_norData(EXTERNAL_MODULE_ID, 0)));

        // Clear the cache entry to simulate the invariant violation.
        registry.mock_setModuleAddressInCache(EXTERNAL_MODULE_ID, address(0));

        vm.expectRevert(IMetaRegistry.ModuleAddressNotCached.selector);
        registry.getNodeOperatorWeightAndExternalStake(0);
    }
}
