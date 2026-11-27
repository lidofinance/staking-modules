// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { SigningKeys } from "src/lib/SigningKeys.sol";
import { StakeTracker } from "src/lib/StakeTracker.sol";
import { TopUpAllocationLib } from "src/lib/TopUpAllocationLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";
import { CuratedModule } from "src/CuratedModule.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";

import { Stub } from "../helpers/mocks/Stub.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract/ModuleAbstract.t.sol";

contract CuratedModuleHarness is CuratedModule {
    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties,
        address metaRegistry
    ) CuratedModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties, metaRegistry) {}

    function exposedIncreaseKeyBalances(
        uint256[] calldata operatorIds,
        uint256[] calldata keyIndices,
        uint256[] calldata allocations
    ) external {
        StakeTracker.increaseKeyBalances(_baseStorage(), operatorIds, keyIndices, allocations);
    }
}

contract CuratedCommon is ModuleFixtures {
    ICuratedModule cm;
    CuratedModuleHarness internal curatedHarness;
    Stub internal metaRegistry;
    uint256 internal constant DEFAULT_OPERATOR_WEIGHT = 1;
    uint256 internal constant MAX_MOCKED_OPERATORS = 256;

    function moduleType() internal pure override returns (ModuleType) {
        return ModuleType.Curated;
    }

    function setUp() public virtual {
        nodeOperator = nextAddress("NODE_OPERATOR");
        stranger = nextAddress("STRANGER");
        strangerNumberTwo = nextAddress("STRANGER_TWO");
        admin = nextAddress("ADMIN");
        actor = nextAddress("ACTOR");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");
        stakingRouter = nextAddress("STAKING_ROUTER");

        (locator, wstETH, stETH, , ) = initLido();

        feeDistributor = new Stub();
        parametersRegistry = new ParametersRegistryMock();
        exitPenalties = new ExitPenaltiesMock();

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        accounting = new AccountingMock(BOND_SIZE, address(wstETH), address(stETH), address(feeDistributor));

        metaRegistry = new Stub();
        _mockMetaOperatorDefaults();
        curatedHarness = new CuratedModuleHarness({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
        module = curatedHarness;
        cm = curatedHarness;

        accounting.setModule(module);

        _enableInitializers(address(module));
        cm.initialize({ admin: admin });

        vm.startPrank(admin);
        {
            module.grantRole(module.RESUME_ROLE(), address(admin));
            module.resume();
            module.revokeRole(module.RESUME_ROLE(), address(admin));
        }
        vm.stopPrank();

        _setupRolesForTests();
    }

    function _setupRolesForTests() internal virtual {
        vm.startPrank(admin);
        module.grantRole(cm.ENABLE_TOP_UP_ALLOCATION_ROLE(), address(this));
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        module.grantRole(module.PAUSE_ROLE(), address(this));
        module.grantRole(module.RESUME_ROLE(), address(this));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), stakingRouter);
        module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.VERIFIER_ROLE(), address(this));
        module.grantRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), address(this));
        module.grantRole(module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(), address(this));
        vm.stopPrank();
    }

    function _mockMetaOperatorDefaults() internal {
        for (uint256 i; i < MAX_MOCKED_OPERATORS; ++i) {
            _mockOperatorGroupMembership(i, true);
            _mockOperatorWeightUpdated(i, false);
            _mockOperatorWeight(i, DEFAULT_OPERATOR_WEIGHT);
        }
    }

    function _mockAllOperatorWeights(uint256 weight) internal {
        uint256 count = module.getNodeOperatorsCount();
        for (uint256 i; i < count; ++i) {
            _mockOperatorWeight(i, weight);
        }
    }

    function _mockOperatorWeight(uint256 nodeOperatorId, uint256 weight) internal {
        _mockOperatorWeightAndExternalStake(nodeOperatorId, weight, 0);
    }

    function _mockOperatorWeightAndExternalStake(
        uint256 nodeOperatorId,
        uint256 weight,
        uint256 externalStake
    ) internal {
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getNodeOperatorWeight.selector, nodeOperatorId),
            abi.encode(weight)
        );
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getNodeOperatorWeightAndExternalStake.selector, nodeOperatorId),
            abi.encode(weight, externalStake)
        );
    }

    function _mockOperatorGroupMembership(uint256 nodeOperatorId, bool isInGroup) internal {
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getNodeOperatorGroupId.selector, nodeOperatorId),
            abi.encode(isInGroup, 0)
        );
    }

    function _mockOperatorWeightUpdated(uint256 nodeOperatorId, bool changed) internal {
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.refreshOperatorWeight.selector, nodeOperatorId),
            abi.encode(changed)
        );
    }

    function _moduleInvariants() internal override {
        assertModuleKeys(module);
    }

    function _topUpToOperatorBalance(uint256 nodeOperatorId, uint256 keyIndex, uint256 targetBalanceWei) internal {
        uint256 currentBalanceWei = cm.getNodeOperatorBalance(nodeOperatorId);
        if (targetBalanceWei < currentBalanceWei) revert("cannot decrease operator balance");

        uint256 deltaWei = targetBalanceWei - currentBalanceWei;
        if (deltaWei == 0) return;

        if (!cm.isTopUpAllocationEnabled(nodeOperatorId)) {
            cm.enableTopUpAllocation(nodeOperatorId);
        }
        bytes memory key = module.getSigningKeys(nodeOperatorId, keyIndex, 1);
        cm.allocateDeposits(deltaWei, BytesArr(key), UintArr(keyIndex), UintArr(nodeOperatorId), UintArr(deltaWei));
    }
}

contract CuratedCommonNoRoles is CuratedCommon {
    function _setupRolesForTests() internal override {
        vm.startPrank(admin);
        {
            // NOTE: Needed for the `createNodeOperator` helper.
            module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        }
        vm.stopPrank();
    }
}

contract CuratedFuzz is ModuleFuzz, CuratedCommon {}

contract CuratedInitialize is CuratedCommon {
    function test_constructor() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
        assertEq(module.getType(), "curated-module");
        assertEq(address(module.LIDO_LOCATOR()), address(locator));
        assertEq(address(module.PARAMETERS_REGISTRY()), address(parametersRegistry));
        assertEq(address(module.ACCOUNTING()), address(accounting));
        assertEq(address(module.EXIT_PENALTIES()), address(exitPenalties));
    }

    function test_constructor_RevertWhen_ZeroModuleType() public {
        vm.expectRevert(IBaseModule.ZeroModuleType.selector);
        new CuratedModule({
            moduleType: bytes32(0),
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
    }

    function test_constructor_RevertWhen_ZeroLocator() public {
        vm.expectRevert(IBaseModule.ZeroLocatorAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(0),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress() public {
        Stub registry = new Stub();
        vm.expectRevert(IBaseModule.ZeroParametersRegistryAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(0),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
    }

    function test_constructor_RevertWhen_ZeroAccountingAddress() public {
        Stub registry = new Stub();
        vm.expectRevert(IBaseModule.ZeroAccountingAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(0),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
    }

    function test_constructor_RevertWhen_ZeroExitPenaltiesAddress() public {
        Stub registry = new Stub();
        vm.expectRevert(IBaseModule.ZeroExitPenaltiesAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(0),
            metaRegistry: address(metaRegistry)
        });
    }

    function test_constructor_RevertWhen_ZeroMetaRegistryAddress() public {
        Stub registry = new Stub();
        vm.expectRevert(ICuratedModule.ZeroMetaRegistryAddress.selector);
        new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(0)
        });
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: address(this) });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.finalizeUpgradeV2();
    }

    function test_initialize() public {
        CuratedModule module = new CuratedModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });

        _enableInitializers(address(module));
        module.initialize({ admin: address(this) });
        assertTrue(module.hasRole(module.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(module.getRoleMemberCount(module.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(module.isPaused());
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        CuratedModule module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });

        _enableInitializers(address(module));
        vm.expectRevert(IBaseModule.ZeroAdminAddress.selector);
        module.initialize({ admin: address(0) });
    }

    function test_finalizeUpgradeV2_revertWhen_FreshDeployment() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cm.finalizeUpgradeV2();
    }
}

contract CuratedFinalizeUpgradeV2 is CuratedCommon {
    function setUp() public override {
        super.setUp();

        vm.store(address(module), INITIALIZABLE_STORAGE, bytes32(uint256(1)));
    }

    function test_finalizeUpgradeV2() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        uint256 nonceBefore = cm.getNonce();

        vm.expectEmit(address(module));
        emit ICuratedModule.TopUpAllocationEnabled(firstId);
        vm.expectEmit(address(module));
        emit ICuratedModule.TopUpAllocationEnabled(secondId);
        cm.finalizeUpgradeV2();

        assertEq(module.getInitializedVersion(), 2);
        assertTrue(cm.isTopUpAllocationEnabled(firstId));
        assertTrue(cm.isTopUpAllocationEnabled(secondId));
        assertEq(cm.getNonce(), nonceBefore + 1);
    }

    function test_finalizeUpgradeV2_partiallyWithdrawn() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");
        withdrawKey(noId, 0);

        cm.finalizeUpgradeV2();

        assertTrue(cm.isTopUpAllocationEnabled(noId));
    }

    function test_finalizeUpgradeV2_allKeysWithdrawn() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        assertFalse(cm.isTopUpAllocationEnabled(noId));

        cm.finalizeUpgradeV2();

        assertFalse(cm.isTopUpAllocationEnabled(noId));
    }

    function test_finalizeUpgradeV2_zeroWeight() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        _mockOperatorWeight(noId, 0);

        cm.finalizeUpgradeV2();

        assertTrue(cm.isTopUpAllocationEnabled(noId));
    }

    function test_finalizeUpgradeV2_newOperatorDisabled() public assertInvariants {
        cm.finalizeUpgradeV2();

        uint256 noId = createNodeOperator();
        assertFalse(cm.isTopUpAllocationEnabled(noId));
    }

    function test_finalizeUpgradeV2_noActiveKeys() public assertInvariants {
        uint256 pendingId = createNodeOperator(1);
        uint256 emptyId = createNodeOperator(0);
        uint256 nonceBefore = cm.getNonce();

        assertFalse(cm.isTopUpAllocationEnabled(pendingId));
        assertFalse(cm.isTopUpAllocationEnabled(emptyId));

        cm.finalizeUpgradeV2();

        assertFalse(cm.isTopUpAllocationEnabled(pendingId));
        assertFalse(cm.isTopUpAllocationEnabled(emptyId));
        assertEq(cm.getNonce(), nonceBefore + 1);
    }

    function test_finalizeUpgradeV2_revertWhen_AlreadyFinalized() public {
        cm.finalizeUpgradeV2();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cm.finalizeUpgradeV2();
    }
}

contract CuratedPauseTest is ModulePauseTest, CuratedCommon {}

contract CuratedPauseAffectingTest is ModulePauseAffectingTest, CuratedCommon {}

contract CuratedDisableTopUpAllocation is CuratedCommon {
    function test_disableTopUpAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(nodeOperator, stranger, false);
        cm.enableTopUpAllocation(noId);
        uint256 nonceBefore = cm.getNonce();

        vm.expectEmit(address(module));
        emit ICuratedModule.TopUpAllocationDisabled(noId);
        vm.prank(stranger);
        cm.disableTopUpAllocation(noId);

        assertFalse(cm.isTopUpAllocationEnabled(noId));
        assertEq(cm.getNonce(), nonceBefore);
    }

    function test_disableTopUpAllocation_extendedManagerPermissions() public assertInvariants {
        uint256 noId = createNodeOperator(nodeOperator, stranger, true);
        cm.enableTopUpAllocation(noId);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);

        assertFalse(cm.isTopUpAllocationEnabled(noId));
    }

    function test_disableTopUpAllocation_modulePaused() public assertInvariants {
        uint256 noId = createNodeOperator();
        cm.enableTopUpAllocation(noId);
        module.pauseFor(1 days);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);

        assertFalse(cm.isTopUpAllocationEnabled(noId));
    }

    function test_disableTopUpAllocation_revertWhen_NodeOperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(0);
    }

    function test_disableTopUpAllocation_revertWhen_AlreadyDisabled() public {
        uint256 noId = createNodeOperator();

        vm.expectRevert(TopUpAllocationLib.TopUpAllocationStateUnchanged.selector);
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);
    }
}

contract CuratedEnableTopUpAllocation is CuratedCommon {
    function test_enableTopUpAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(0);
        uint256 nonceBefore = cm.getNonce();

        vm.expectEmit(address(module));
        emit ICuratedModule.TopUpAllocationEnabled(noId);
        cm.enableTopUpAllocation(noId);

        assertTrue(cm.isTopUpAllocationEnabled(noId));
        assertEq(cm.getNonce(), nonceBefore);
    }

    function test_enableTopUpAllocation_modulePaused() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.pauseFor(1 days);

        cm.enableTopUpAllocation(noId);

        assertTrue(cm.isTopUpAllocationEnabled(noId));
    }

    function test_enableTopUpAllocation_revertWhen_NodeOperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        cm.enableTopUpAllocation(0);
    }

    function test_enableTopUpAllocation_revertWhen_AlreadyEnabled() public {
        uint256 noId = createNodeOperator();
        cm.enableTopUpAllocation(noId);

        vm.expectRevert(TopUpAllocationLib.TopUpAllocationStateUnchanged.selector);
        cm.enableTopUpAllocation(noId);
    }
}

contract CuratedCreateNodeOperator is ModuleCreateNodeOperator, CuratedCommon {}

contract CuratedAddValidatorKeys is ModuleAddValidatorKeys, CuratedCommon {}

contract CuratedAddValidatorKeysNegative is ModuleAddValidatorKeysNegative, CuratedCommon {}

contract CuratedObtainDepositData is ModuleObtainDepositData, CuratedCommon {
    function test_obtainDepositData_MultipleOperators() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(3);
        uint256 thirdId = createNodeOperator(1);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(firstId, 0);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(secondId, 1);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(thirdId, 0);
        module.obtainDepositData(6, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 5);
        assertEq(depositableValidatorsCount, 1);
    }

    function test_obtainDepositData_updatesOperatorBalances() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);

        module.obtainDepositData(1, "");

        NodeOperator memory first = module.getNodeOperator(firstId);
        NodeOperator memory second = module.getNodeOperator(secondId);
        uint256 firstBalance = cm.getNodeOperatorBalance(firstId);
        uint256 secondBalance = cm.getNodeOperatorBalance(secondId);

        assertEq(firstBalance, uint256(first.totalDepositedKeys) * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(secondBalance, uint256(second.totalDepositedKeys) * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(firstBalance + secondBalance, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_obtainDepositData_topUpAllocationDisabled() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(2);
        cm.enableTopUpAllocation(firstId);
        module.obtainDepositData(2, "");

        assertEq(module.getNodeOperator(firstId).depositableValidatorsCount, 1);
        assertEq(module.getNodeOperator(secondId).depositableValidatorsCount, 1);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);

        assertEq(module.getNodeOperator(firstId).depositableValidatorsCount, 1);
        assertEq(module.getNodeOperator(secondId).depositableValidatorsCount, 1);

        module.obtainDepositData(2, "");

        assertEq(module.getNodeOperator(firstId).totalDepositedKeys, 2);
        assertEq(module.getNodeOperator(secondId).totalDepositedKeys, 2);
    }

    function test_obtainDepositData_DistributesByWeight() public assertInvariants {
        uint256 first = createNodeOperator(4);
        uint256 second = createNodeOperator(4);

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(second, curveId);
        _mockOperatorWeight(second, 3);

        (bytes memory pubkeys, ) = module.obtainDepositData(4, "");

        NodeOperator memory no0 = module.getNodeOperator(first);
        NodeOperator memory no1 = module.getNodeOperator(second);

        assertEq(no0.totalDepositedKeys, 1);
        assertEq(no1.totalDepositedKeys, 3);

        bytes memory expectedKeys = bytes.concat(
            module.getSigningKeys(first, 0, 1),
            module.getSigningKeys(second, 0, 3)
        );
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_ExternalStakeUses2048EthNormalization() public assertInvariants {
        uint256 noId0 = createNodeOperator(10);
        uint256 noId1 = createNodeOperator(10);

        _mockOperatorWeightAndExternalStake({ nodeOperatorId: noId0, weight: 1, externalStake: 2048 ether });
        _mockOperatorWeightAndExternalStake({ nodeOperatorId: noId1, weight: 1, externalStake: 0 });

        module.obtainDepositData(4, "");

        NodeOperator memory no0 = module.getNodeOperator(noId0);
        NodeOperator memory no1 = module.getNodeOperator(noId1);

        // currents = [1, 0]
        // inflow = 4
        // targetTotal = 1 + 4 = 5
        // targets = [ceil(5/2), ceil(5/2)] = [3, 3]
        // imbalances = [2, 3]
        // deposits greedy => [1, 3]
        assertEq(no0.totalDepositedKeys, 1);
        assertEq(no1.totalDepositedKeys, 3);
    }

    function test_obtainDepositData_LeavesRemainderOnCap() public assertInvariants {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(10);

        (, uint256 totalDepositedBefore, uint256 depositableBefore) = module.getStakingModuleSummary();
        uint256 nonceBefore = module.getNonce();

        (bytes memory pubkeys, bytes memory signatures) = module.obtainDepositData(4, "");

        NodeOperator memory no0 = module.getNodeOperator(first);
        NodeOperator memory no1 = module.getNodeOperator(second);

        assertEq(no0.totalDepositedKeys, 1);
        assertEq(no1.totalDepositedKeys, 2);
        uint256 allocated = no0.totalDepositedKeys + no1.totalDepositedKeys;
        assertEq(pubkeys.length, allocated * 48);
        assertEq(signatures.length, allocated * 96);

        bytes memory expectedKeys = bytes.concat(
            module.getSigningKeys(first, 0, 1),
            module.getSigningKeys(second, 0, 2)
        );
        assertEq(pubkeys, expectedKeys);

        (, uint256 totalDepositedAfter, uint256 depositableAfter) = module.getStakingModuleSummary();
        assertEq(totalDepositedAfter, totalDepositedBefore + allocated);
        assertEq(depositableAfter, depositableBefore - allocated);
        assertEq(module.getNonce(), nonceBefore + 1);
    }

    function test_obtainDepositData_SkipsZeroCapacityOperator() public assertInvariants {
        uint256 first = createNodeOperator(0);
        uint256 second = createNodeOperator(4);

        (bytes memory pubkeys, ) = module.obtainDepositData(3, "");

        NodeOperator memory no0 = module.getNodeOperator(first);
        NodeOperator memory no1 = module.getNodeOperator(second);

        assertEq(no0.totalDepositedKeys, 0);
        assertEq(no1.totalDepositedKeys, 3);

        bytes memory expectedKeys = module.getSigningKeys(second, 0, 3);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_RebalancesUsingCurrent() public assertInvariants {
        uint256 first = createNodeOperator(4);
        uint256 second = createNodeOperator(0);

        module.obtainDepositData(2, "");

        NodeOperator memory noAfterFirst = module.getNodeOperator(first);
        NodeOperator memory noAfterSecond = module.getNodeOperator(second);
        assertEq(noAfterFirst.totalDepositedKeys, 2);
        assertEq(noAfterSecond.totalDepositedKeys, 0);

        uploadMoreKeys(second, 4);

        module.obtainDepositData(2, "");

        NodeOperator memory no0 = module.getNodeOperator(first);
        NodeOperator memory no1 = module.getNodeOperator(second);

        assertEq(no0.totalDepositedKeys, 2);
        assertEq(no1.totalDepositedKeys, 2);
    }

    function test_obtainDepositData_NotEnoughCapacity() public {
        uint256 noId = createNodeOperator(1);

        bytes memory expectedKeys = module.getSigningKeys(noId, 0, 1);
        (bytes memory pubkeys, ) = module.obtainDepositData(2, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalDepositedKeys, 1);
        assertEq(no.depositableValidatorsCount, 0);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_WeightedCapacityTooLow() public assertInvariants {
        uint256 zeroWeightId = createNodeOperator(2);
        uint256 weightedId = createNodeOperator(1);

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(zeroWeightId, curveId);
        _mockOperatorWeight(zeroWeightId, 0);

        bytes memory expectedKeys = module.getSigningKeys(weightedId, 0, 1);
        (bytes memory pubkeys, ) = module.obtainDepositData(2, "");

        NodeOperator memory noZero = module.getNodeOperator(zeroWeightId);
        NodeOperator memory noWeighted = module.getNodeOperator(weightedId);
        assertEq(noZero.totalDepositedKeys, 0);
        assertEq(noWeighted.totalDepositedKeys, 1);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_CompactAllocationSkipsZeroWeightOperator() public assertInvariants {
        uint256 zeroWeightId = createNodeOperator(1);
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(zeroWeightId, curveId);
        _mockOperatorWeight(zeroWeightId, 0);

        bytes memory expectedKeys = module.getSigningKeys(firstId, 0, 1);
        (bytes memory pubkeys, ) = module.obtainDepositData(1, "");

        NodeOperator memory noZero = module.getNodeOperator(zeroWeightId);
        NodeOperator memory noFirst = module.getNodeOperator(firstId);
        NodeOperator memory noSecond = module.getNodeOperator(secondId);

        assertEq(noZero.totalDepositedKeys, 0);
        assertEq(noFirst.totalDepositedKeys, 1);
        assertEq(noSecond.totalDepositedKeys, 0);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_SingleDepositToUnderfilledOperator() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(2);

        module.obtainDepositData(1, "");

        bytes memory expectedKeys = module.getSigningKeys(secondId, 0, 1);
        (bytes memory pubkeys, ) = module.obtainDepositData(1, "");

        NodeOperator memory no0 = module.getNodeOperator(firstId);
        NodeOperator memory no1 = module.getNodeOperator(secondId);

        assertEq(no0.totalDepositedKeys, 1);
        assertEq(no1.totalDepositedKeys, 1);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_WithdrawnKeysAffectAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(2);

        module.obtainDepositData(2, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: firstId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        module.reportRegularWithdrawnValidators(validatorInfos);

        bytes memory expectedKeys = module.getSigningKeys(firstId, 1, 1);
        (bytes memory pubkeys, ) = module.obtainDepositData(1, "");

        NodeOperator memory no0 = module.getNodeOperator(firstId);
        NodeOperator memory no1 = module.getNodeOperator(secondId);

        assertEq(no0.totalDepositedKeys, 2);
        assertEq(no1.totalDepositedKeys, 1);
        assertEq(pubkeys, expectedKeys);
    }

    function test_obtainDepositData_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        module.obtainDepositData(1, "");
    }
}

contract CuratedAllocateDeposits is CuratedCommon {
    function test_allocateDeposits_disabledUntilCommitteeEnables() public assertInvariants {
        uint256 noId = super.createNodeOperator(nodeOperator, false);
        uploadMoreKeys(noId, 1);
        module.obtainDepositData(1, "");
        bytes memory key = module.getSigningKeys(noId, 0, 1);

        (uint256 allocated, uint256[] memory ids, uint256[] memory amounts) = cm.getDepositsAllocation(10 ether);
        assertEq(allocated, 0);
        assertEq(ids.length, 0);
        assertEq(amounts.length, 0);
        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(10 ether)
        );
        assertEq(allocations, UintArr(0));

        cm.enableTopUpAllocation(noId);
        allocations = cm.allocateDeposits(10 ether, BytesArr(key), UintArr(0), UintArr(noId), UintArr(10 ether));
        assertEq(allocations, UintArr(10 ether));
    }

    function test_allocateDeposits_singleKey_fullAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        uint256 nonceBefore = module.getNonce();

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256 limitWei = 8 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            6 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(limitWei)
        );

        assertEq(allocations.length, 1);
        assertEq(allocations[0], 6 ether);
        assertEq(cm.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);
        assertEq(module.getNonce(), nonceBefore);
    }

    function test_allocateDeposits_updatesOperatorBalances() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);
        uint256 firstBalanceBefore = cm.getNodeOperatorBalance(firstId);
        uint256 secondBalanceBefore = cm.getNodeOperatorBalance(secondId);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(10 ether, 10 ether)
        );

        assertEq(allocations.length, 2);
        assertEq(cm.getNodeOperatorBalance(firstId), firstBalanceBefore + allocations[0]);
        assertEq(cm.getNodeOperatorBalance(secondId), secondBalanceBefore + allocations[1]);
        assertEq(
            module.getTotalModuleStake(),
            firstBalanceBefore + secondBalanceBefore + allocations[0] + allocations[1]
        );
    }

    function test_allocateDeposits_multipleKeys_sequentialAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            6 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(2 ether, 6 ether)
        );

        assertEq(allocations.length, 2);
        assertEq(allocations[0], 2 ether);
        assertEq(allocations[1], 4 ether);
        assertEq(cm.getNodeOperatorBalance(noId), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);
        assertEq(module.getTotalModuleStake(), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);
    }

    function test_allocateDeposits_globalShareBaselineMissingOperators() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        createNodeOperator(1);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key0),
            UintArr(0),
            UintArr(firstId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 2 ether);
    }

    function test_allocateDeposits_disabledOperatorPreservesGlobalShareBaseline() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 disabledId = createNodeOperator(1);
        createNodeOperator(1);
        module.obtainDepositData(3, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(disabledId);

        uint256[] memory allocations = cm.allocateDeposits(
            8 ether,
            BytesArr(module.getSigningKeys(firstId, 0, 1)),
            UintArr(0),
            UintArr(firstId),
            UintArr(8 ether)
        );
        assertEq(allocations, UintArr(4 ether));
    }

    function test_allocateDeposits_zeroCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _topUpToOperatorBalance(firstId, 0, 2048 ether);

        bytes memory key = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(secondId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 4 ether);
    }

    function test_allocateDeposits_subStepCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        uint256 almostFullTopUp = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE -
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE -
            1 wei;
        curatedHarness.exposedIncreaseKeyBalances(UintArr(firstId), UintArr(0), UintArr(almostFullTopUp));
        _mockOperatorWeight(firstId, 1000);
        _mockOperatorWeight(secondId, 1);

        bytes memory key = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(secondId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 2 ether);
    }

    function test_allocateDeposits_capacityCapsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        _topUpToOperatorBalance(noId, 0, 2046 ether);

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 2 ether);
    }

    function test_allocateDeposits_fullBalanceSkipsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        _topUpToOperatorBalance(noId, 0, 2048 ether);

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            1 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 0);
    }

    function test_allocateDeposits_limitsAlignedPerKey() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(0, 10 ether)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 4 ether);
    }

    function test_allocateDeposits_exhaustedOperatorAllocationSkipsLaterDuplicateKeys() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);
        bytes memory key2 = module.getSigningKeys(noId, 2, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0, key1, key2),
            UintArr(0, 1, 2),
            UintArr(noId, noId, noId),
            UintArr(10 ether, 10 ether, 10 ether)
        );

        assertEq(allocations, UintArr(2 ether, 0, 0));
        assertEq(cm.getNodeOperatorBalance(noId), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
        assertEq(module.getTotalModuleStake(), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
    }

    function test_allocateDeposits_zeroDepositSkipsValidation() public assertInvariants {
        uint256 nonce = module.getNonce();
        bytes[] memory invalidPubkeys = new bytes[](1);
        invalidPubkeys[0] = new bytes(47);

        uint256[] memory allocations = cm.allocateDeposits(0, invalidPubkeys, UintArr(), UintArr(1), UintArr(1, 2));

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_allocateDeposits_roundsDownToStep() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256 depositAmount = 2 ether + 0.5 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            depositAmount,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 2 ether);
    }

    function test_allocateDeposits_capacityAndKeyCapsLeaveRemainder() public assertInvariants {
        uint256 cappedId = createNodeOperator(1);
        uint256 wideId = createNodeOperator(2);
        module.obtainDepositData(3, "");

        _mockOperatorWeight(wideId, 0);
        _topUpToOperatorBalance(cappedId, 0, 2000 ether);
        _mockOperatorWeight(wideId, DEFAULT_OPERATOR_WEIGHT);

        bytes memory cappedKey = module.getSigningKeys(cappedId, 0, 1);
        bytes memory wideKey = module.getSigningKeys(wideId, 0, 1);
        bytes[] memory pubkeys = BytesArr(cappedKey, wideKey);
        uint256 depositAmount = 2200 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            depositAmount,
            pubkeys,
            UintArr(0, 0),
            UintArr(cappedId, wideId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        assertEq(allocations[0], 48 ether);
        assertEq(allocations[1], 2016 ether);
        assertEq(allocations[0] + allocations[1], 2064 ether);
    }

    function test_allocateDeposits_keyCapBoundsSingleKeyAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits(
            5000 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(5000 ether)
        );

        assertEq(
            allocations[0],
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        );
    }

    function test_allocateDeposits_limitsLeaveRemainder() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(4 ether, 4 ether)
        );

        assertEq(allocations[0], 4 ether);
        assertEq(allocations[1], 4 ether);
    }

    function test_allocateDeposits_topUpLimitsRoundedToStep() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(4.5 ether, 5.1 ether)
        );

        assertEq(allocations[0], 4 ether);
        assertEq(allocations[1], 4 ether);
    }

    function test_allocateDeposits_matchesPredepositAllocation() public assertInvariants {
        uint256 operatorsCount = 5;
        uint256[] memory weights = new uint256[](operatorsCount);
        weights[0] = 1;
        weights[1] = 2;
        weights[2] = 3;
        weights[3] = 4;
        weights[4] = 5;

        uint256[] memory operatorIds = new uint256[](operatorsCount);
        uint256 weightSum;

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });

        for (uint256 i; i < operatorsCount; ++i) {
            uint256 weight = weights[i];
            operatorIds[i] = createNodeOperator(2 * weight);

            uint256 curveId = accounting.addBondCurve(curve);
            accounting.setBondCurve(operatorIds[i], curveId);
            _mockOperatorWeight(operatorIds[i], weight);

            weightSum += weight;
        }

        module.obtainDepositData(weightSum, "");

        uint256[] memory baseDeposited = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            baseDeposited[i] = module.getNodeOperator(operatorIds[i]).totalDepositedKeys;
        }

        uint256 snapshot = vm.snapshotState();

        module.obtainDepositData(weightSum, "");

        uint256[] memory predepositAllocations = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            predepositAllocations[i] = module.getNodeOperator(operatorIds[i]).totalDepositedKeys - baseDeposited[i];
        }

        vm.revertToState(snapshot);

        bytes[] memory pubkeys = new bytes[](operatorsCount);
        uint256[] memory keyIndices = new uint256[](operatorsCount);
        uint256[] memory topUpLimits = new uint256[](operatorsCount);
        uint256 depositAmount = weightSum * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;

        for (uint256 i; i < operatorsCount; ++i) {
            bytes memory key = module.getSigningKeys(operatorIds[i], 0, 1);
            pubkeys[i] = key;
            keyIndices[i] = 0;
            topUpLimits[i] = depositAmount;
        }

        uint256[] memory topUpAllocations = cm.allocateDeposits(
            depositAmount,
            pubkeys,
            keyIndices,
            operatorIds,
            topUpLimits
        );

        assertEq(topUpAllocations.length, operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            assertEq(topUpAllocations[i], predepositAllocations[i] * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        }
    }

    function testFuzz_allocateDeposits_disableMatchesPreview(
        uint256 budget,
        uint8 disableMask
    ) public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        uint256 fullId = createNodeOperator(1);
        module.obtainDepositData(3, "");
        curatedHarness.exposedIncreaseKeyBalances(
            UintArr(secondId, fullId),
            UintArr(0, 0),
            UintArr(968 ether, 2016 ether)
        );
        _mockOperatorWeightAndExternalStake(firstId, 1, 128 ether);
        _mockOperatorWeightAndExternalStake(secondId, 2, 32 ether);
        _mockOperatorWeight(fullId, 3);
        disableMask = uint8(bound(disableMask, 0, 7));
        for (uint256 i; i < 3; ++i) {
            if ((disableMask & (1 << i)) != 0) {
                vm.prank(nodeOperator);
                cm.disableTopUpAllocation(i);
            }
        }
        budget = bound(budget, 1, 6000 ether);

        (uint256 allocated, uint256[] memory ids, uint256[] memory amounts) = cm.getDepositsAllocation(budget);
        uint256[] memory expected = new uint256[](3);
        for (uint256 i; i < ids.length; ++i) {
            assertTrue(cm.isTopUpAllocationEnabled(ids[i]));
            expected[ids[i]] = amounts[i];
        }
        uint256 stakeBefore = module.getTotalModuleStake();
        assertEq(cm.getNodeOperatorBalance(fullId), 2048 ether);
        // Submit every key with sufficient limits: only module capacity and the enable flags constrain allocation.
        uint256[] memory actual = cm.allocateDeposits(
            budget,
            BytesArr(
                module.getSigningKeys(firstId, 0, 1),
                module.getSigningKeys(secondId, 0, 1),
                module.getSigningKeys(fullId, 0, 1)
            ),
            UintArr(0, 0, 0),
            UintArr(firstId, secondId, fullId),
            UintArr(2016 ether, 1048 ether, 0)
        );
        assertEq(actual, expected);
        assertEq(actual[0] + actual[1] + actual[2], allocated);
        assertEq(cm.getNodeOperatorBalance(firstId), 32 ether + expected[0]);
        assertEq(cm.getNodeOperatorBalance(secondId), 1000 ether + expected[1]);
        assertEq(cm.getNodeOperatorBalance(fullId), 2048 ether);
        assertEq(module.getTotalModuleStake(), stakeBefore + allocated);
    }

    function test_allocateDeposits_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(3 ether, 3 ether)
        );
    }

    function test_getDepositsAllocation_matchesAllocateDeposits() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(4 ether);

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory keyAllocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(10 ether, 10 ether)
        );

        assertEq(ids.length, 2);
        assertEq(allocs.length, 2);
        assertEq(ids[0], firstId);
        assertEq(ids[1], secondId);
        assertEq(allocs[0], keyAllocations[0]);
        assertEq(allocs[1], keyAllocations[1]);
    }

    function test_getDepositsAllocation_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        module.obtainDepositData(2, "");

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getDepositsAllocation(2 ether);
    }

    function test_getDepositsAllocation_zeroDepositReturnsEmpty() public assertInvariants {
        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(0);
        assertEq(ids.length, 0);
        assertEq(allocs.length, 0);
    }

    function test_getDepositsAllocation_noOperatorsReturnsEmpty() public assertInvariants {
        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(1 ether);
        assertEq(ids.length, 0);
        assertEq(allocs.length, 0);
    }

    function test_getDepositsAllocation_allZeroWeightsReturnsEmpty() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);
        module.obtainDepositData(2, "");

        _mockAllOperatorWeights(0);
        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        assertEq(ids.length, 0);
        assertEq(allocs.length, 0);
    }

    function test_getDepositsAllocation_allDisabledReturnsEmpty() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(secondId);

        (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations) = cm.getDepositsAllocation(
            100 ether
        );

        assertEq(allocated, 0);
        assertEq(operatorIds.length, 0);
        assertEq(allocations.length, 0);
    }

    function test_getDepositsAllocation_zeroCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _topUpToOperatorBalance(firstId, 0, 2048 ether);

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(4 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 4 ether);
    }

    function test_getDepositsAllocation_subStepCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        uint256 almostFullTopUp = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE -
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE -
            1 wei;
        curatedHarness.exposedIncreaseKeyBalances(UintArr(firstId), UintArr(0), UintArr(almostFullTopUp));
        _mockOperatorWeight(firstId, 1000);
        _mockOperatorWeight(secondId, 1);

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 2 ether);
    }

    function test_getDepositsAllocation_capacityCapsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        _topUpToOperatorBalance(noId, 0, 2046 ether);

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(10 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], noId);
        assertEq(allocs[0], 2 ether);
    }

    function test_getDepositsAllocation_balancesReweightAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _topUpToOperatorBalance(firstId, 0, 1032 ether);

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 2 ether);
    }

    function test_getDepositsAllocation_compactOutputSkipsZeroAllocations() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _topUpToOperatorBalance(firstId, 0, 1032 ether);

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(4 ether);

        assertEq(ids.length, 1);
        assertEq(allocs.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 4 ether);
    }

    function test_allocateDeposits_limitsDoNotAffectShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(2 ether, 10 ether)
        );

        assertEq(allocations.length, 2);
        assertEq(allocations[0], 2 ether);
        assertEq(allocations[1], 4 ether);
        assertEq(allocations[0] + allocations[1], 6 ether);
    }

    function test_allocateDeposits_emptyKeysReturnsEmpty() public assertInvariants {
        uint256 nonce = module.getNonce();
        uint256[] memory allocations = cm.allocateDeposits(1 ether, new bytes[](0), UintArr(), UintArr(), UintArr());

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_allocateDeposits_allZeroWeightsReturnsZeroAllocations() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);
        uint256 limitWei = 2 ether;

        _mockAllOperatorWeights(0);
        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(limitWei, limitWei)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 0);
    }

    function test_allocateDeposits_allDisabledReturnsZeroAllocations() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(secondId);

        uint256[] memory allocations = cm.allocateDeposits(
            100 ether,
            BytesArr(module.getSigningKeys(firstId, 0, 1), module.getSigningKeys(secondId, 0, 1)),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(100 ether, 100 ether)
        );
        assertEq(allocations, UintArr(0, 0));
    }

    function test_allocateDeposits_zeroLimitSkipsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            1 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(0)
        );

        assertEq(allocations[0], 0);
    }

    function test_allocateDeposits_zeroWeightOperatorSkipped() public assertInvariants {
        uint256 zeroWeightId = createNodeOperator(1);
        uint256 weightedId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(zeroWeightId, curveId);
        _mockOperatorWeight(zeroWeightId, 0);

        bytes memory key0 = module.getSigningKeys(zeroWeightId, 0, 1);
        bytes memory key1 = module.getSigningKeys(weightedId, 0, 1);
        uint256 limitWei = 2 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(zeroWeightId, weightedId),
            UintArr(limitWei, limitWei)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 2 ether);
    }

    function test_allocateDeposits_disabledKeysReceiveZeroInMixedBatch() public assertInvariants {
        uint256 disabledId = createNodeOperator(1);
        uint256 readyId = createNodeOperator(2);
        module.obtainDepositData(3, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(disabledId);

        assertEq(cm.getNodeOperatorBalance(disabledId), 32 ether);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(
                module.getSigningKeys(readyId, 0, 1),
                module.getSigningKeys(disabledId, 0, 1),
                module.getSigningKeys(readyId, 1, 1)
            ),
            UintArr(0, 0, 1),
            UintArr(readyId, disabledId, readyId),
            UintArr(3 ether, 10 ether, 10 ether)
        );
        assertEq(allocations, UintArr(2 ether, 0, 8 ether));
        assertEq(cm.getNodeOperatorBalance(disabledId), 32 ether);
        assertEq(cm.getNodeOperatorBalance(readyId), 74 ether);
    }

    function test_allocateDeposits_disabledOperatorExcludedFromBaseline() public assertInvariants {
        uint256 readyId = createNodeOperator(2);
        uint256 pendingId = createNodeOperator(2);
        module.obtainDepositData(4, "");
        // The ready operator has 4000 ETH; the pending operator has only its 64 ETH seed deposits.
        curatedHarness.exposedIncreaseKeyBalances(
            UintArr(readyId, readyId),
            UintArr(0, 1),
            UintArr(1968 ether, 1968 ether)
        );
        bytes memory key0 = module.getSigningKeys(readyId, 0, 1);
        bytes memory key1 = module.getSigningKeys(readyId, 1, 1);

        // Model the bot omitting unactivated keys while their operator still consumes the entire 3200 ETH budget.
        (, uint256[] memory ids, uint256[] memory amounts) = cm.getDepositsAllocation(3200 ether);
        assertEq(ids, UintArr(pendingId));
        assertEq(amounts, UintArr(3200 ether));
        uint256[] memory allocations = cm.allocateDeposits(
            3200 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(readyId, readyId),
            UintArr(46 ether, 46 ether)
        );
        assertEq(allocations, UintArr(0, 0));
        assertEq(cm.getNodeOperatorBalance(pendingId), 64 ether);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(pendingId);
        (, ids, amounts) = cm.getDepositsAllocation(3200 ether);
        assertEq(ids, UintArr(readyId));
        assertEq(amounts, UintArr(96 ether));
        allocations = cm.allocateDeposits(
            3200 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(readyId, readyId),
            UintArr(46 ether, 46 ether)
        );
        assertEq(allocations, UintArr(46 ether, 46 ether));
        assertEq(cm.getNodeOperatorBalance(pendingId), 64 ether);
        assertEq(module.getTotalModuleStake(), 4156 ether);
    }

    function test_allocateDeposits_enabledOperatorReceivesAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);
        cm.enableTopUpAllocation(firstId);
        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(4 ether, 4 ether)
        );

        assertEq(allocations, UintArr(2 ether, 2 ether));
    }

    function testFuzz_allocateDeposits_disabledWeightAndStakeDoNotAffectAllocation(
        uint256 weight,
        uint256 externalStake,
        uint256 budget
    ) public assertInvariants {
        uint256 disabledId = createNodeOperator(1);
        uint256 readyId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(disabledId);
        budget = bound(budget, 0, 3000 ether);
        uint256 expected = budget < 2016 ether ? budget : 2016 ether;
        expected -= expected % 2 ether;

        (uint256 allocated, , ) = cm.getDepositsAllocation(budget);
        assertEq(allocated, expected);

        _mockOperatorWeightAndExternalStake(disabledId, bound(weight, 1, 1e18), bound(externalStake, 0, 1e12 ether));

        (allocated, , ) = cm.getDepositsAllocation(budget);
        assertEq(allocated, expected);
        if (budget == 0) return;
        uint256[] memory allocations = cm.allocateDeposits(
            budget,
            BytesArr(module.getSigningKeys(readyId, 0, 1)),
            UintArr(0),
            UintArr(readyId),
            UintArr(2016 ether)
        );
        assertEq(allocations, UintArr(expected));
    }

    function test_allocateDeposits_balancesReweightAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _topUpToOperatorBalance(firstId, 0, 1032 ether);

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);
        uint256 limitWei = 4 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(limitWei, limitWei)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 2 ether);
    }

    function test_allocateDeposits_belowStepAllocatesZero() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256 limitWei = 10 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether - 1,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(limitWei)
        );

        assertEq(allocations[0], 0);
    }

    function test_allocateDeposits_revertWhen_NotStakingRouter() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        cm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
    }

    function test_allocateDeposits_zeroDepositReturnsEmpty() public assertInvariants {
        uint256 nonce = module.getNonce();
        uint256[] memory allocations = cm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_allocateDeposits_revertWhen_LengthMismatch() public assertInvariants {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        cm.allocateDeposits(1 ether, new bytes[](0), UintArr(), UintArr(0), UintArr());
    }

    function test_allocateDeposits_revertWhen_OperatorIdOutOfRange() public assertInvariants {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        cm.allocateDeposits(1 ether, BytesArr(new bytes(48)), UintArr(0), UintArr(1), UintArr(1 ether));
    }

    function test_allocateDeposits_revertWhen_KeyIndexOutOfRange() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        cm.allocateDeposits(1 ether, BytesArr(key), UintArr(1), UintArr(noId), UintArr(1 ether));
    }

    function test_allocateDeposits_revertWhen_PubkeyMismatch() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory wrongKey = module.getSigningKeys(noId, 0, 1);
        wrongKey[0] = bytes1(uint8(wrongKey[0]) ^ 0x01);

        vm.expectRevert(SigningKeys.InvalidSigningKey.selector);
        cm.allocateDeposits(1 ether, BytesArr(wrongKey), UintArr(0), UintArr(noId), UintArr(1 ether));
    }

    function test_getDepositsAllocation_externalStakeReducesAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        // Both operators have equal weight and the same internal balance.
        // Operator 0 additionally has 4 ether of external stake.
        _mockOperatorWeightAndExternalStake(firstId, 1, 4 ether);

        // currents = [32 + 4, 32] = [36, 32]
        // inflow = 12
        // targetTotal = 68 + 12 = 80
        // targets = [ceil(80/2), ceil(80/2)] = [40, 40]
        // imbalances = [4, 8]
        // deposits greedy => [4, 8]
        (uint256 allocated, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(12 ether);

        assertEq(allocated, 12 ether);
        assertEq(ids.length, 2);
        assertEq(ids[0], firstId);
        assertEq(ids[1], secondId);
        assertEq(allocs[0], 4 ether);
        assertEq(allocs[1], 8 ether);
    }

    function test_allocateDeposits_externalStakeReducesAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        // Operator 0 has large external stake; operator 1 has none.
        _mockOperatorWeightAndExternalStake(firstId, 1, 10 ether);

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        // currents = [5 + 10, 5] = [15, 5]
        // inflow = 2
        // targetTotal = 20 + 2 = 22
        // targets = [ceil(22/2), ceil(22/2)] = [11, 11]
        // imbalances = [0, 6]
        // deposits greedy => [0, 2]
        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(32 ether, 32 ether)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 2 ether);
    }

    function createNodeOperator(
        address managerAddress,
        bool extendedManagerPermissions
    ) internal override returns (uint256 noId) {
        noId = super.createNodeOperator(managerAddress, extendedManagerPermissions);
        cm.enableTopUpAllocation(noId);
    }
}

contract CuratedIsTopUpAllocationEnabled is CuratedCommon {
    function test_isTopUpAllocationEnabled_default() public assertInvariants {
        uint256 noId = createNodeOperator();

        assertFalse(cm.isTopUpAllocationEnabled(noId));
    }
}

contract CuratedGetOperatorsWeights is CuratedCommon {
    function test_getOperatorWeights_ReturnsMetaRegistryValues() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);

        uint256[] memory operatorIds = UintArr(0, 1);
        uint256[] memory expectedWeights = UintArr(42, 7);
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getOperatorWeights.selector, operatorIds),
            abi.encode(expectedWeights)
        );

        uint256[] memory weights = cm.getOperatorWeights(operatorIds);
        assertEq(weights, expectedWeights);
    }

    function test_getOperatorWeights_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);
        createNodeOperator(1);

        uint256[] memory operatorIds = UintArr(0, 1);
        uint256[] memory expectedWeights = UintArr(42, 7);
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getOperatorWeights.selector, operatorIds),
            abi.encode(expectedWeights)
        );

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getOperatorWeights(operatorIds);
    }
}

contract CuratedGetNodeOperatorWeightAndExternalStake is CuratedCommon {
    function test_getNodeOperatorWeightAndExternalStake_ReturnsMetaRegistryValues() public assertInvariants {
        createNodeOperator(1);

        uint256 nodeOperatorId = 0;
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getNodeOperatorWeightAndExternalStake.selector, nodeOperatorId),
            abi.encode(42, 7 ether)
        );

        (uint256 weight, uint256 externalStake) = cm.getNodeOperatorWeightAndExternalStake(nodeOperatorId);
        assertEq(weight, 42);
        assertEq(externalStake, 7 ether);
    }

    function test_getNodeOperatorWeightAndExternalStake_topUpAllocationDisabled() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);
        _mockOperatorWeightAndExternalStake(noId, 3, 2048 ether);

        (uint256 weight, uint256 externalStake) = cm.getNodeOperatorWeightAndExternalStake(noId);
        assertEq(weight, 3);
        assertEq(externalStake, 2048 ether);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);

        (weight, externalStake) = cm.getNodeOperatorWeightAndExternalStake(noId);
        assertEq(weight, 3);
        assertEq(externalStake, 2048 ether);
    }

    function test_getNodeOperatorWeightAndExternalStake_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);

        uint256 nodeOperatorId = 0;
        vm.mockCall(
            address(metaRegistry),
            abi.encodeWithSelector(IMetaRegistry.getNodeOperatorWeightAndExternalStake.selector, nodeOperatorId),
            abi.encode(42, 7 ether)
        );

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getNodeOperatorWeightAndExternalStake(nodeOperatorId);
    }
}

contract CuratedGetDepositAllocationTargets is CuratedCommon {
    function test_getDepositAllocationTargets() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(3);
        _mockOperatorWeight(firstId, 1);
        _mockOperatorWeight(secondId, 3);

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        assertEq(currents.length, 2);
        // No deposits yet, currents and targets are zero.
        assertEq(currents[firstId], 0);
        assertEq(currents[secondId], 0);
        assertEq(targets[firstId], 0);
        assertEq(targets[secondId], 0);
    }

    function test_getDepositAllocationTargets_withDepositedKeys() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        // Each operator has 1 deposited key and 1 remaining capacity.
        assertEq(currents[firstId], 1);
        assertEq(currents[secondId], 1);
        // Equal weights → equal targets: totalCurrent=2, each gets 1.
        assertEq(targets[firstId], 1);
        assertEq(targets[secondId], 1);
    }

    function test_getDepositAllocationTargets_unequalWeights() public assertInvariants {
        uint256 firstId = createNodeOperator(4);
        uint256 secondId = createNodeOperator(4);
        _mockOperatorWeight(firstId, 1);
        _mockOperatorWeight(secondId, 3);
        // Allocation distributes 1:3 per weights → firstId gets 1, secondId gets 3.
        module.obtainDepositData(4, "");

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        assertEq(currents[firstId], 1);
        assertEq(currents[secondId], 3);
        // totalCurrent=4, weights 1:3 → targets 1:3.
        assertEq(targets[firstId], 1);
        assertEq(targets[secondId], 3);
    }

    function test_getDepositAllocationTargets_topUpAllocationDisabled() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        createNodeOperator(2);
        cm.enableTopUpAllocation(firstId);
        module.obtainDepositData(2, "");
        _mockOperatorWeightAndExternalStake(firstId, 3, 2048 ether);

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();
        assertEq(currents, UintArr(2, 1));
        assertEq(targets, UintArr(2, 0));

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);

        (currents, targets) = cm.getDepositAllocationTargets();
        assertEq(currents, UintArr(2, 1));
        assertEq(targets, UintArr(2, 0));
    }

    function test_getDepositAllocationTargets_noOperatorsReturnsEmpty() public assertInvariants {
        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        assertEq(currents.length, 0);
        assertEq(targets.length, 0);
    }

    function test_getDepositAllocationTargets_zeroWeightsReturnZeros() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        _mockAllOperatorWeights(0);

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        assertEq(currents.length, 2);
        assertEq(currents[firstId], 0);
        assertEq(currents[secondId], 0);
        assertEq(targets[firstId], 0);
        assertEq(targets[secondId], 0);
    }

    function test_getDepositAllocationTargets_zeroCapacityIncluded() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        // Consume all capacity.
        module.obtainDepositData(2, "");

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        // Both operators still included despite 0 depositable keys.
        assertEq(currents[firstId], 1);
        assertEq(currents[secondId], 1);
        // Equal weights → equal targets.
        assertEq(targets[firstId], 1);
        assertEq(targets[secondId], 1);
    }

    function test_getDepositAllocationTargets_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getDepositAllocationTargets();
    }

    function test_getDepositAllocationTargets_matchesAllocationWhenAllHaveCapacity() public assertInvariants {
        uint256 firstId = createNodeOperator(4);
        uint256 secondId = createNodeOperator(4);
        _mockOperatorWeight(firstId, 1);
        _mockOperatorWeight(secondId, 3);
        // Deposit 4 → allocated 1:3 by weights. Both still have capacity.
        module.obtainDepositData(4, "");

        (uint256[] memory currents, uint256[] memory targets) = cm.getDepositAllocationTargets();

        // All operators have capacity → targets reflect the same weight set as real allocation.
        // totalCurrent=4, weights 1:3 → targets [1, 3]. Matches the 1:3 allocation above.
        assertEq(currents[firstId], targets[firstId]);
        assertEq(currents[secondId], targets[secondId]);
    }

    function test_getDepositAllocationTargets_differsFromAllocationWhenNoCapacity() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(2);
        // Deposit 2 → 1 each. firstId has 0 remaining keys, secondId has 1.
        module.obtainDepositData(2, "");

        (, uint256[] memory targets) = cm.getDepositAllocationTargets();

        // View includes both (equal weights) → targets [1, 1].
        assertEq(targets[firstId], 1);
        assertEq(targets[secondId], 1);

        // Real allocation: only secondId is eligible (firstId has no capacity).
        // Allocator recalculates shares across eligible operators only → secondId gets everything.
        uint256 snapshot = vm.snapshotState();
        module.obtainDepositData(1, "");
        assertEq(module.getNodeOperator(firstId).totalDepositedKeys, 1); // unchanged
        assertEq(module.getNodeOperator(secondId).totalDepositedKeys, 2); // got the deposit
        vm.revertToState(snapshot);
    }

    function test_getDepositAllocationTargets_externalStakeIncludedInCurrent() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(2);

        _mockOperatorWeightAndExternalStake(firstId, 1, 2048 ether);
        _mockOperatorWeightAndExternalStake(secondId, 1, 0);

        (uint256[] memory currents, ) = cm.getDepositAllocationTargets();

        // firstId: 0 deposited keys + 2048 ether / 2048 ether = 1 external validator.
        assertEq(currents[firstId], 1);
        assertEq(currents[secondId], 0);
    }
}

contract CuratedGetTopUpAllocationTargets is CuratedCommon {
    function test_getTopUpAllocationTargets() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _mockOperatorWeight(firstId, 1);
        _mockOperatorWeight(secondId, 3);

        (uint256[] memory currents, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        assertEq(currents.length, 2);
        // Balance is 32 ether per operator from initial deposit.
        assertEq(currents[firstId], 32 ether);
        assertEq(currents[secondId], 32 ether);
        // totalCurrent=64 ether, weights 1:3 → targets 16:48 ether.
        assertEq(targets[firstId], 16 ether);
        assertEq(targets[secondId], 48 ether);
    }

    function test_getTopUpAllocationTargets_disablingAllocationDoesNotChangeTargets() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        createNodeOperator(1);
        module.obtainDepositData(2, "");
        _mockOperatorWeightAndExternalStake(firstId, 3, 2048 ether);

        (uint256[] memory currents, uint256[] memory targets) = cm.getTopUpAllocationTargets();
        assertEq(currents, UintArr(2080 ether, 32 ether));
        assertEq(targets, UintArr(1584 ether, 528 ether));

        cm.enableTopUpAllocation(firstId);
        (currents, targets) = cm.getTopUpAllocationTargets();
        assertEq(currents, UintArr(2080 ether, 32 ether));
        assertEq(targets, UintArr(1584 ether, 528 ether));

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(firstId);
        (currents, targets) = cm.getTopUpAllocationTargets();
        assertEq(currents, UintArr(2080 ether, 32 ether));
        assertEq(targets, UintArr(1584 ether, 528 ether));
    }

    function test_getTopUpAllocationTargets_noOperatorsReturnsEmpty() public assertInvariants {
        (uint256[] memory currents, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        assertEq(currents.length, 0);
        assertEq(targets.length, 0);
    }

    function test_getTopUpAllocationTargets_zeroWeightsReturnZeros() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");
        _mockAllOperatorWeights(0);

        (uint256[] memory currents, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        assertEq(currents.length, 2);
        assertEq(currents[firstId], 0);
        assertEq(currents[secondId], 0);
        assertEq(targets[firstId], 0);
        assertEq(targets[secondId], 0);
    }

    function test_getTopUpAllocationTargets_zeroCapacityIncluded() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        // Max out balance for firstId so capacity = 0.
        _mockOperatorWeight(secondId, 0);
        _topUpToOperatorBalance(firstId, 0, 2048 ether);
        _mockOperatorWeight(secondId, DEFAULT_OPERATOR_WEIGHT);

        (uint256[] memory currents, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        // Both operators included despite firstId having zero top-up capacity.
        // firstId: 2048 ether, secondId: 32 ether. Total = 2080 ether. Equal weights → equal targets.
        assertEq(currents[firstId], 2048 ether);
        assertEq(currents[secondId], 32 ether);
        assertEq(targets[firstId], 1040 ether);
        assertEq(targets[secondId], 1040 ether);
    }

    function test_getTopUpAllocationTargets_matchesAllocationWhenAllHaveCapacity() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        cm.enableTopUpAllocation(firstId);
        uint256 secondId = createNodeOperator(1);
        cm.enableTopUpAllocation(secondId);
        module.obtainDepositData(2, "");

        // Equal weights, both at 32 ether → both below 2048 ether capacity.
        (, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        // totalCurrent=64 ether, equal weights → targets [32, 32] ether.
        assertEq(targets[firstId], 32 ether);
        assertEq(targets[secondId], 32 ether);

        // Both have capacity → real allocation uses the same weight set.
        (, uint256[] memory allocIds, uint256[] memory allocs) = cm.getDepositsAllocation(4 ether);

        // Real allocation distributes equally → [2, 2] ether.
        assertEq(allocIds.length, 2);
        assertEq(allocs[0], 2 ether);
        assertEq(allocs[1], 2 ether);
        // Allocation ratio matches target ratio.
        assertEq(allocs[0] * targets[secondId], allocs[1] * targets[firstId]);
    }

    function test_getTopUpAllocationTargets_differsFromAllocationWhenNoCapacity() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        cm.enableTopUpAllocation(firstId);
        uint256 secondId = createNodeOperator(1);
        cm.enableTopUpAllocation(secondId);
        module.obtainDepositData(2, "");

        // Max out balance for firstId so capacity = 0.
        _topUpToOperatorBalance(firstId, 0, 2048 ether);

        (, uint256[] memory targets) = cm.getTopUpAllocationTargets();

        // View includes both (equal weights) → equal targets.
        assertEq(targets[firstId], targets[secondId]);

        // Real allocation: only secondId is eligible (firstId at max balance).
        // Allocator recalculates shares → secondId gets everything.
        (, uint256[] memory allocIds, uint256[] memory allocs) = cm.getDepositsAllocation(10 ether);
        assertEq(allocIds.length, 1);
        assertEq(allocIds[0], secondId);
        assertEq(allocs[0], 10 ether);
    }

    function test_getTopUpAllocationTargets_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getTopUpAllocationTargets();
    }

    function test_getTopUpAllocationTargets_externalStakeIncludedInCurrent() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _mockOperatorWeightAndExternalStake(firstId, 1, 100 ether);
        _mockOperatorWeightAndExternalStake(secondId, 1, 0);

        (uint256[] memory currents, ) = cm.getTopUpAllocationTargets();

        // firstId: 32 ether balance + 100 ether external.
        assertEq(currents[firstId], 32 ether + 100 ether);
        assertEq(currents[secondId], 32 ether);
    }
}

contract CuratedProposeNodeOperatorManagerAddressChange is
    ModuleProposeNodeOperatorManagerAddressChange,
    CuratedCommon
{}

contract CuratedConfirmNodeOperatorManagerAddressChange is
    ModuleConfirmNodeOperatorManagerAddressChange,
    CuratedCommon
{}

contract CuratedProposeNodeOperatorRewardAddressChange is ModuleProposeNodeOperatorRewardAddressChange, CuratedCommon {}

contract CuratedConfirmNodeOperatorRewardAddressChange is ModuleConfirmNodeOperatorRewardAddressChange, CuratedCommon {}

contract CuratedResetNodeOperatorManagerAddress is ModuleResetNodeOperatorManagerAddress, CuratedCommon {}

contract CuratedChangeNodeOperatorRewardAddress is ModuleChangeNodeOperatorRewardAddress, CuratedCommon {}

contract CuratedVetKeys is ModuleVetKeys, CuratedCommon {}

contract CuratedDecreaseVettedSigningKeysCount is ModuleDecreaseVettedSigningKeysCount, CuratedCommon {}

contract CuratedGetSigningKeys is ModuleGetSigningKeys, CuratedCommon {}

contract CuratedGetSigningKeysWithSignatures is ModuleGetSigningKeysWithSignatures, CuratedCommon {}

contract CuratedRemoveKeys is ModuleRemoveKeys, CuratedCommon {}

contract CuratedRemoveKeysReverts is ModuleRemoveKeysReverts, CuratedCommon {}

contract CuratedGetNodeOperatorNonWithdrawnKeys is ModuleGetNodeOperatorNonWithdrawnKeys, CuratedCommon {}

contract CuratedGetNodeOperatorSummary is ModuleGetNodeOperatorSummary, CuratedCommon {}

contract CuratedGetNodeOperator is ModuleGetNodeOperator, CuratedCommon {}

contract CuratedUpdateTargetValidatorsLimits is ModuleUpdateTargetValidatorsLimits, CuratedCommon {}

contract CuratedUpdateExitedValidatorsCount is ModuleUpdateExitedValidatorsCount, CuratedCommon {}

contract CuratedUnsafeUpdateValidatorsCount is ModuleUnsafeUpdateValidatorsCount, CuratedCommon {}

contract CuratedReportGeneralDelayedPenalty is ModuleReportGeneralDelayedPenalty, CuratedCommon {}

contract CuratedCancelGeneralDelayedPenalty is ModuleCancelGeneralDelayedPenalty, CuratedCommon {}

contract CuratedSettleGeneralDelayedPenaltyBasic is ModuleSettleGeneralDelayedPenaltyBasic, CuratedCommon {}

contract CuratedSettleGeneralDelayedPenaltyAdvanced is ModuleSettleGeneralDelayedPenaltyAdvanced, CuratedCommon {}

contract CuratedCompensateGeneralDelayedPenalty is ModuleCompensateGeneralDelayedPenalty, CuratedCommon {}

contract CuratedReportWithdrawnValidators is ModuleReportWithdrawnValidators, CuratedCommon {
    function createNodeOperator(
        address managerAddress,
        bool extendedManagerPermissions
    ) internal override returns (uint256 noId) {
        noId = super.createNodeOperator(managerAddress, extendedManagerPermissions);
        cm.enableTopUpAllocation(noId);
    }
}

contract CuratedKeyAllocatedBalance is ModuleKeyAllocatedBalance, CuratedCommon {}

contract CuratedReportValidatorBalance is ModuleReportValidatorBalance, CuratedCommon {
    function test_reportValidatorBalance_doesNotDecreaseKeyAllocatedBalance() public {
        uint256 noId = createNodeOperator();
        cm.enableTopUpAllocation(noId);
        cm.obtainDepositData(1, "");

        // Allocate 20 ether via top-up, setting keyAllocatedBalance to 20 ether.
        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        cm.allocateDeposits({
            maxDepositAmount: 20 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(20 ether)
        });
        assertEq(cm.getKeyAllocatedBalances(noId, 0, 1), UintArr(20 ether));

        // Confirmed balance below allocated — keyAllocatedBalance must not decrease.
        cm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(cm.getKeyAllocatedBalances(noId, 0, 1), UintArr(20 ether), "keyAllocatedBalance must not decrease");
    }

    function test_reportValidatorBalance_afterTopUp_increasesStakeOnlyByDelta() public {
        uint256 noId = createNodeOperator();
        cm.enableTopUpAllocation(noId);
        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        cm.allocateDeposits({
            maxDepositAmount: 20 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(20 ether)
        });

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 20 ether);
        assertEq(cm.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 20 ether);

        cm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);

        assertEq(cm.getKeyAllocatedBalances(noId, 0, 1), UintArr(25 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);
        assertEq(cm.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);
    }
}

contract CuratedTopUpKeyAllocatedBalance is CuratedCommon {
    function test_topUp_emitsKeyAllocatedBalanceChanged() public {
        createNodeOperator(1);
        cm.enableTopUpAllocation(0);
        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(0, 0, 1);
        bytes[] memory pubkeys = BytesArr(key);

        vm.expectEmit(address(cm));
        emit IBaseModule.KeyAllocatedBalanceChanged(0, 0, 4 ether);

        cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5 ether)
        });
    }

    function test_topUp_noEmitWhenKeyAtCap() public {
        createNodeOperator(1);
        cm.enableTopUpAllocation(0);
        cm.obtainDepositData(1, "");

        setKeyConfirmedBalance(
            0,
            0,
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        );

        bytes memory key = cm.getSigningKeys(0, 0, 1);
        bytes[] memory pubkeys = BytesArr(key);

        vm.recordLogs();
        cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5 ether)
        });

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            assertNotEq(entries[i].topics[0], IBaseModule.KeyAllocatedBalanceChanged.selector);
        }
    }

    function test_topUp_withdrawnKeyGetsZeroAllocation() public {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);
        cm.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        cm.reportRegularWithdrawnValidators(validatorInfos);

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        assertEq(allocations, UintArr(0));
        assertEq(cm.getKeyAllocatedBalances(noId, 0, 1), UintArr(0));
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(cm.getNodeOperatorBalance(noId), 0);
    }

    function test_topUp_slashedKeyGetsZeroAllocation() public {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);
        cm.obtainDepositData(1, "");

        cm.reportValidatorSlashing(noId, 0);
        assertTrue(cm.isValidatorSlashed(noId, 0));

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        assertEq(allocations, UintArr(0));
        assertEq(cm.getKeyAllocatedBalances(noId, 0, 1), UintArr(0));
        assertEq(
            module.getTotalModuleStake(),
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            "slashed key must not receive top-up"
        );
        assertEq(cm.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_topUp_slashedKeySkippedAmongMixedBatch() public {
        uint256 noId = createNodeOperator(2);
        cm.enableTopUpAllocation(noId);
        cm.obtainDepositData(2, "");

        // Slash key 0, leave key 1 intact.
        cm.reportValidatorSlashing(noId, 0);

        bytes memory packed = cm.getSigningKeys(noId, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packed, 0, 48), slice(packed, 48, 48));

        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(noId, noId),
            topUpLimits: UintArr(5 ether, 5 ether)
        });

        // Slashed head key gets no allocation; remaining key receives the full per-key limit.
        assertEq(allocations, UintArr(0, 4 ether));
        assertEq(cm.getKeyAllocatedBalances(noId, 0, 2), UintArr(0, 4 ether));
        assertEq(module.getTotalModuleStake(), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(cm.getNodeOperatorBalance(noId), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
    }

    function test_topUp_duplicateKeySharesRemainingHeadroom() public {
        createNodeOperator(1);
        cm.enableTopUpAllocation(0);
        cm.obtainDepositData(1, "");

        uint256 cap = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        setKeyConfirmedBalance(0, 0, cap - 10 ether);

        bytes memory key = cm.getSigningKeys(0, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 20 ether,
            pubkeys: BytesArr(key, key),
            keyIndices: UintArr(0, 0),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(20 ether, 20 ether)
        });

        assertEq(allocations, UintArr(10 ether, 0));
        assertEq(cm.getKeyAllocatedBalances(0, 0, 1), UintArr(cap));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(cm.getNodeOperatorBalance(0), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
    }

    function test_topUp_capsOperatorBalanceIncrementToAppliedHeadroom() public {
        createNodeOperator(1);
        cm.obtainDepositData(1, "");

        uint256 cap = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        setKeyConfirmedBalance(0, 0, cap - 2 ether);

        vm.expectEmit(address(cm));
        emit IBaseModule.KeyAllocatedBalanceChanged(0, 0, cap);
        // Current allocators cap per-key top-ups before they reach StakeTracker, so an over-cap allocation is
        // practically unreachable in production right now. Use the harness to exercise the defensive accounting path.
        curatedHarness.exposedIncreaseKeyBalances(UintArr(0), UintArr(0), UintArr(10 ether));

        assertEq(cm.getKeyAllocatedBalances(0, 0, 1), UintArr(cap));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(cm.getNodeOperatorBalance(0), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
    }

    function test_topUp_capsOperatorBalanceIncrementToAppliedHeadroom_NoUpdate() public {
        createNodeOperator(1);
        cm.obtainDepositData(1, "");

        uint256 cap = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        setKeyConfirmedBalance(0, 0, cap);

        vm.recordLogs();
        // Current allocators cap per-key top-ups before they reach StakeTracker, so an over-cap allocation is
        // practically unreachable in production right now. Use the harness to exercise the defensive accounting path.
        curatedHarness.exposedIncreaseKeyBalances(UintArr(0), UintArr(0), UintArr(10 ether));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        assertEq(cm.getKeyAllocatedBalances(0, 0, 1), UintArr(cap));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(cm.getNodeOperatorBalance(0), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
    }
}

contract CuratedTotalModuleStake is CuratedCommon {
    function test_getTotalModuleStake_tracksDeposits() public {
        uint256 noId = createNodeOperator(1);

        assertEq(module.getTotalModuleStake(), 0);

        cm.obtainDepositData(1, "");
        assertEq(module.getTotalModuleStake(), 32 ether);
        assertEq(cm.getNodeOperatorBalance(noId), 32 ether);
    }

    function test_getTotalModuleStake_tracksTopUps() public {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);

        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });
        uint256 topUpWei = allocations[0];

        assertEq(module.getTotalModuleStake(), 32 ether + topUpWei);
        assertEq(cm.getNodeOperatorBalance(noId), 32 ether + topUpWei);
    }

    function test_getTotalModuleStake_topUpAllocationDisabled() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        _topUpToOperatorBalance(noId, 0, 100 ether);

        assertEq(module.getTotalModuleStake(), 100 ether);
        assertEq(cm.getNodeOperatorBalance(noId), 100 ether);

        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);

        assertEq(module.getTotalModuleStake(), 100 ether);
        assertEq(cm.getNodeOperatorBalance(noId), 100 ether);
    }

    function test_getTotalModuleStake_tracksVerifierIncreases() public {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);

        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        uint256 verifiedExtra = allocations[0] + 2 ether;
        cm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);
        assertEq(cm.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);
    }

    function test_getTotalModuleStake_tracksWithdrawals() public {
        uint256 noId = createNodeOperator(1);
        cm.enableTopUpAllocation(noId);

        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(noId, 0, 1);
        cm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        assertGt(module.getTotalModuleStake(), 32 ether);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });
        cm.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(cm.getNodeOperatorBalance(noId), 0);
    }
}

contract CuratedGetStakingModuleSummary is ModuleGetStakingModuleSummary, CuratedCommon {}

contract CuratedAccessControl is ModuleAccessControl, CuratedCommonNoRoles {
    function test_disableTopUpAllocation_RevertWhenNotOwner() public {
        uint256 noId = createNodeOperator();

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        cm.disableTopUpAllocation(noId);
    }

    function test_disableTopUpAllocation_RevertWhenOnlyEnableRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = cm.ENABLE_TOP_UP_ALLOCATION_ROLE();
        vm.prank(admin);
        module.grantRole(role, address(this));

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        cm.disableTopUpAllocation(noId);
    }

    function test_disableTopUpAllocation_RevertWhenOnlyManager() public {
        uint256 noId = createNodeOperator(nodeOperator, stranger, false);

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(nodeOperator);
        cm.disableTopUpAllocation(noId);
    }

    function test_disableTopUpAllocation_RevertWhenRewardAddressWithExtendedManagerPermissions() public {
        uint256 noId = createNodeOperator(nodeOperator, stranger, true);

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        cm.disableTopUpAllocation(noId);
    }

    function test_enableTopUpAllocation_RevertWhenNoRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = cm.ENABLE_TOP_UP_ALLOCATION_ROLE();

        expectRoleRevert(stranger, role);
        vm.prank(stranger);
        cm.enableTopUpAllocation(noId);
    }

    function test_enableTopUpAllocation_RevertWhenOnlyOwner() public {
        uint256 noId = createNodeOperator();
        bytes32 role = cm.ENABLE_TOP_UP_ALLOCATION_ROLE();

        expectRoleRevert(nodeOperator, role);
        vm.prank(nodeOperator);
        cm.enableTopUpAllocation(noId);
    }

    function test_enableTopUpAllocation_RevertWhenOnlyAdminRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = cm.ENABLE_TOP_UP_ALLOCATION_ROLE();

        expectRoleRevert(admin, role);
        vm.prank(admin);
        cm.enableTopUpAllocation(noId);
    }
}

contract CuratedStakingRouterAccessControl is ModuleStakingRouterAccessControl, CuratedCommonNoRoles {}

contract CuratedDepositableValidatorsCount is ModuleDepositableValidatorsCount, CuratedCommon {
    function test_updateDepositableValidatorsCount_zeroWeightNullifiesDepositable() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 1);

        _mockOperatorWeight(noId, 0);
        module.updateDepositableValidatorsCount(noId);

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 0);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 0);
    }
}

contract CuratedNodeOperatorStateAfterUpdateCurve is ModuleNodeOperatorStateAfterUpdateCurve, CuratedCommon {}

contract CuratedOnRewardsMinted is ModuleOnRewardsMinted, CuratedCommon {}

contract CuratedRecoverERC20 is ModuleRecoverERC20, CuratedCommon {}

contract CuratedMisc is ModuleMisc, CuratedCommon {
    function test_getInitializedVersion() public view override {
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_updateDepositInfo_updatesDepositable() public assertInvariants {
        uint256 noId = createNodeOperator(4);

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        accounting.updateBondCurve(0, BOND_SIZE * 2);
        cm.updateDepositInfo(noId);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 2);
    }

    function test_updateDepositInfo_ZeroDepositableIfWeightIsZero() public assertInvariants {
        uint256 noId = createNodeOperator(4);

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        _mockOperatorWeight(noId, 0);
        cm.updateDepositInfo(noId);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 0);
    }

    function test_requestFullDepositInfoUpdate_fromAccounting() public {
        createNodeOperator(1);

        uint256 nonceBefore = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.FullDepositInfoUpdateRequested();
        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        uint256 nonceAfter = module.getNonce();

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 1);
        assertEq(nonceAfter, nonceBefore + 1);
    }

    function test_requestFullDepositInfoUpdate_fromMetaRegistry() public {
        createNodeOperator(1);

        uint256 nonceBefore = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.FullDepositInfoUpdateRequested();
        vm.prank(address(metaRegistry));
        module.requestFullDepositInfoUpdate();

        uint256 nonceAfter = module.getNonce();

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 1);
        assertEq(nonceAfter, nonceBefore + 1);
    }

    function test_requestFullDepositInfoUpdate_revertWhen_SenderIsNotEligible() public {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(nextAddress());
        module.requestFullDepositInfoUpdate();
    }
}

contract CuratedExitDeadlineThreshold is ModuleExitDeadlineThreshold, CuratedCommon {}

contract CuratedIsValidatorExitDelayPenaltyApplicable is ModuleIsValidatorExitDelayPenaltyApplicable, CuratedCommon {}

contract CuratedReportValidatorExitDelay is ModuleReportValidatorExitDelay, CuratedCommon {}

contract CuratedOnValidatorExitTriggered is ModuleOnValidatorExitTriggered, CuratedCommon {}

contract CuratedCreateNodeOperators is ModuleCreateNodeOperators, CuratedCommon {}

contract CuratedChangeNodeOperatorAddresses is ModuleChangeNodeOperatorAddresses, CuratedCommon {}

contract CuratedHooks is CuratedCommon {
    function test_notifyNodeOperatorWeightChange_bumpsNonce() public {
        uint256 noId = createNodeOperator(1);

        uint256 oldNonce = cm.getNonce();
        address metaRegistry = address(cm.META_REGISTRY());
        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 42, 154);

        uint256 newNonce = cm.getNonce();
        assertEq(newNonce, oldNonce + 1);
    }

    function test_notifyNodeOperatorWeightChange_depositableIsZeroWhenWeightIsZero() public {
        uint256 noId = createNodeOperator(1);
        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);

        address metaRegistry = address(cm.META_REGISTRY());
        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 42, 0);

        no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_notifyNodeOperatorWeightChange_weightChangedFromZeroToNonZero() public {
        uint256 noId = createNodeOperator(1);
        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);

        address metaRegistry = address(cm.META_REGISTRY());
        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 42, 0);

        no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);

        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 0, 154);

        no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_notifyNodeOperatorWeightChange_revertWhen_NotMetaRegistry() public {
        vm.expectRevert(ICuratedModule.SenderIsNotMetaRegistry.selector);
        cm.notifyNodeOperatorWeightChange(0, 0, 154);
    }
}

contract CuratedBatchDepositInfoUpdate is ModuleBatchDepositInfoUpdate, CuratedCommon {}
