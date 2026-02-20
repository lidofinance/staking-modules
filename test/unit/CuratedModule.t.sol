// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CuratedDepositAllocator } from "src/lib/allocator/CuratedDepositAllocator.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { ValidatorCountsReport } from "src/lib/ValidatorCountsReport.sol";
import { CuratedModule } from "src/CuratedModule.sol";
import { IBaseModule, INOAddresses, NodeOperator, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";

import { Stub } from "../helpers/mocks/Stub.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract/ModuleAbstract.t.sol";

contract CuratedCommon is ModuleFixtures {
    ICuratedModule cm;
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
        module = new CuratedModule({
            moduleType: "curated-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties),
            metaRegistry: address(metaRegistry)
        });
        cm = CuratedModule(address(module));

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
        assertModuleUnusedStorageSlots(module);
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
        assertEq(module.getInitializedVersion(), 1);
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
}

contract CuratedPauseTest is ModulePauseTest, CuratedCommon {}

contract CuratedPauseAffectingTest is ModulePauseAffectingTest, CuratedCommon {}

contract CuratedCreateNodeOperator is ModuleCreateNodeOperator, CuratedCommon {}

contract CuratedAddValidatorKeys is ModuleAddValidatorKeys, CuratedCommon {}

contract CuratedAddValidatorKeysViaGate is ModuleAddValidatorKeysViaGate, CuratedCommon {}

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

        assertEq(firstBalance, uint256(first.totalDepositedKeys) * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE);
        assertEq(secondBalance, uint256(second.totalDepositedKeys) * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE);
        assertEq(firstBalance + secondBalance, CuratedDepositAllocator.MIN_ACTIVATION_BALANCE);
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
            exitBalance: CuratedDepositAllocator.MIN_ACTIVATION_BALANCE,
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

contract CuratedTopUpObtainDepositData is CuratedCommon {
    function test_topUpObtainDepositData_singleKey_fullAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256 limitWei = 4 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            3 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(limitWei)
        );

        assertEq(allocations.length, 1);
        assertEq(allocations[0], 3 ether);
    }

    function test_topUpObtainDepositData_updatesOperatorBalances() public assertInvariants {
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
    }

    function test_topUpObtainDepositData_multipleKeys_sequentialAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            3 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(1 ether, 3 ether)
        );

        assertEq(allocations.length, 2);
        assertEq(allocations[0], 1 ether);
        assertEq(allocations[1], 2 ether);
    }

    function test_topUpObtainDepositData_globalShareBaselineMissingOperators() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            2 ether,
            BytesArr(key0),
            UintArr(0),
            UintArr(firstId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 1 ether);
    }

    function test_topUpObtainDepositData_zeroCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(2048 ether / 1 gwei, 0))
        );

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

    function test_topUpObtainDepositData_balanceUpdateRespectsGlobalShare() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(1);

        module.obtainDepositData(3, "");

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(secondId, curveId);
        _mockOperatorWeight(secondId, 3);

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(0, 0))
        );

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(firstId, 1, 1);
        bytes[] memory pubkeys = BytesArr(key0, key1);

        uint256[] memory allocations = cm.allocateDeposits(
            4 ether,
            pubkeys,
            UintArr(0, 1),
            UintArr(firstId, firstId),
            UintArr(10 ether, 10 ether)
        );

        assertEq(allocations[0], 1 ether);
        assertEq(allocations[1], 0);

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(allocations[0] / 1 gwei, 0))
        );

        uint256[] memory secondAllocations = cm.allocateDeposits(
            7 ether,
            pubkeys,
            UintArr(0, 1),
            UintArr(firstId, firstId),
            UintArr(10 ether, 10 ether)
        );

        assertEq(secondAllocations[0], 1 ether);
        assertEq(secondAllocations[1], 0);
    }

    function test_topUpObtainDepositData_capacityCapsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(noId)),
            _encodeUint128Values(UintArr(2047 ether / 1 gwei))
        );

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(10 ether)
        );

        assertEq(allocations[0], 1 ether);
    }

    function test_topUpObtainDepositData_fullBalanceSkipsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(noId)),
            _encodeUint128Values(UintArr(2048 ether / 1 gwei))
        );

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

    function test_topUpObtainDepositData_limitsAlignedPerKey() public assertInvariants {
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

    function test_topUpObtainDepositData_zeroDepositSkipsValidation() public assertInvariants {
        uint256 nonce = module.getNonce();
        bytes[] memory invalidPubkeys = new bytes[](1);
        invalidPubkeys[0] = new bytes(47);

        uint256[] memory allocations = cm.allocateDeposits(0, invalidPubkeys, UintArr(), UintArr(1), UintArr(1, 2));

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_topUpObtainDepositData_roundsDownToStep() public assertInvariants {
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

    function test_topUpObtainDepositData_capacityAndKeyCapsLeaveRemainder() public assertInvariants {
        uint256 cappedId = createNodeOperator(1);
        uint256 wideId = createNodeOperator(2);
        module.obtainDepositData(3, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(cappedId, wideId)),
            _encodeUint128Values(UintArr(2000 ether / 1 gwei, 0))
        );

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

    function test_topUpObtainDepositData_keyCapBoundsSingleKeyAllocation() public assertInvariants {
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
            WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE - WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE
        );
    }

    function test_topUpObtainDepositData_globalBaselineHeavilyOmitted() public assertInvariants {
        uint256 omittedHeavyId = createNodeOperator(1);
        uint256 omittedMidId = createNodeOperator(1);
        uint256 includedId = createNodeOperator(1);
        module.obtainDepositData(3, "");

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });

        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(omittedHeavyId, curveId);
        _mockOperatorWeight(omittedHeavyId, 100);

        curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(omittedMidId, curveId);
        _mockOperatorWeight(omittedMidId, 10);

        curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(includedId, curveId);
        _mockOperatorWeight(includedId, 1);

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(omittedHeavyId, omittedMidId, includedId)),
            _encodeUint128Values(UintArr(0, 0, 0))
        );

        bytes memory key = module.getSigningKeys(includedId, 0, 1);
        uint256 depositAmount = 111 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            depositAmount,
            BytesArr(key),
            UintArr(0),
            UintArr(includedId),
            UintArr(depositAmount)
        );

        assertEq(allocations[0], 1 ether);
    }

    function test_topUpObtainDepositData_limitsLeaveRemainder() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(3 ether, 3 ether)
        );

        assertEq(allocations[0], 3 ether);
        assertEq(allocations[1], 3 ether);
    }

    function test_topUpObtainDepositData_topUpLimitsRoundedToStep() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key0 = module.getSigningKeys(noId, 0, 1);
        bytes memory key1 = module.getSigningKeys(noId, 1, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 1),
            UintArr(noId, noId),
            UintArr(2.5 ether, 3.1 ether)
        );

        assertEq(allocations[0], 2 ether);
        assertEq(allocations[1], 3 ether);
    }

    function test_topUpObtainDepositData_matchesPredepositAllocation() public assertInvariants {
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

        uint256 snapshot = vm.snapshot();

        module.obtainDepositData(weightSum, "");

        uint256[] memory predepositAllocations = new uint256[](operatorsCount);
        for (uint256 i; i < operatorsCount; ++i) {
            predepositAllocations[i] = module.getNodeOperator(operatorIds[i]).totalDepositedKeys - baseDeposited[i];
        }

        vm.revertTo(snapshot);

        bytes[] memory pubkeys = new bytes[](operatorsCount);
        uint256[] memory keyIndices = new uint256[](operatorsCount);
        uint256[] memory topUpLimits = new uint256[](operatorsCount);
        uint256 depositAmount = weightSum * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE;

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
            assertEq(topUpAllocations[i], predepositAllocations[i] * CuratedDepositAllocator.MIN_ACTIVATION_BALANCE);
        }
    }

    function test_topUpObtainDepositData_revertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
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

    function test_getDepositsAllocation_matchesObtainDepositData() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(10, 10))
        );

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory keyAllocations = cm.allocateDeposits(
            2 ether,
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
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        cm.getDepositsAllocation(2 ether);
    }

    function test_getDepositsAllocation_matchesObtainDepositData_twoSteps() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);

        module.obtainDepositData(2, "");

        {
            IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
            curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
            uint256 curveId = accounting.addBondCurve(curve);
            accounting.setBondCurve(firstId, curveId);
            curveId = accounting.addBondCurve(curve);
            accounting.setBondCurve(secondId, curveId);
        }

        _mockOperatorWeight(firstId, 1);
        _mockOperatorWeight(secondId, 2);

        uint256[2] memory balances = [uint256(1 ether), uint256(2 ether)];
        {
            bytes[] memory pubkeys = BytesArr(
                module.getSigningKeys(firstId, 0, 1),
                module.getSigningKeys(secondId, 0, 1)
            );

            cm.updateOperatorBalances(
                _encodeNodeOperatorIds(UintArr(firstId, secondId)),
                _encodeUint128Values(UintArr(balances[0] / 1 gwei, balances[1] / 1 gwei))
            );

            (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(3 ether);
            assertEq(ids.length, 2);
            assertEq(allocs.length, 2);
            assertEq(ids[0], firstId);
            assertEq(ids[1], secondId);
            assertEq(allocs[0], 1 ether);
            assertEq(allocs[1], 2 ether);

            uint256[] memory keyAllocations = cm.allocateDeposits(
                3 ether,
                pubkeys,
                UintArr(0, 0),
                UintArr(firstId, secondId),
                UintArr(10 ether, 10 ether)
            );
            assertEq(keyAllocations[0], 1 ether);
            assertEq(keyAllocations[1], 2 ether);
        }

        balances[0] += 1 ether;
        balances[1] += 2 ether;

        {
            bytes[] memory pubkeys = BytesArr(
                module.getSigningKeys(firstId, 0, 1),
                module.getSigningKeys(secondId, 0, 1)
            );

            cm.updateOperatorBalances(
                _encodeNodeOperatorIds(UintArr(firstId, secondId)),
                _encodeUint128Values(UintArr(balances[0] / 1 gwei, balances[1] / 1 gwei))
            );

            (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(3 ether);
            assertEq(ids.length, 2);
            assertEq(allocs.length, 2);
            assertEq(ids[0], firstId);
            assertEq(ids[1], secondId);
            assertEq(allocs[0], 1 ether);
            assertEq(allocs[1], 2 ether);

            uint256[] memory keyAllocations = cm.allocateDeposits(
                3 ether,
                pubkeys,
                UintArr(0, 0),
                UintArr(firstId, secondId),
                UintArr(10 ether, 10 ether)
            );
            assertEq(keyAllocations[0], 1 ether);
            assertEq(keyAllocations[1], 2 ether);
        }
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
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        _mockAllOperatorWeights(0);
        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        assertEq(ids.length, 0);
        assertEq(allocs.length, 0);
    }

    function test_getDepositsAllocation_zeroCapacityExcludedFromShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(2048 ether / 1 gwei, 0))
        );

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(4 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 4 ether);
    }

    function test_getDepositsAllocation_capacityCapsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(noId)),
            _encodeUint128Values(UintArr(2047 ether / 1 gwei))
        );

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(10 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], noId);
        assertEq(allocs[0], 1 ether);
    }

    function test_getDepositsAllocation_balancesReweightAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(10_000_000_000, 0))
        );

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(1 ether);

        assertEq(ids.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 1 ether);
    }

    function test_getDepositsAllocation_compactOutputSkipsZeroAllocations() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(10, 0))
        );

        (, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(2 ether);

        assertEq(ids.length, 1);
        assertEq(allocs.length, 1);
        assertEq(ids[0], secondId);
        assertEq(allocs[0], 1 ether);
    }

    function test_topUpObtainDepositData_limitsDoNotAffectShare() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(10, 10))
        );

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);

        uint256[] memory allocations = cm.allocateDeposits(
            10 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(1 ether, 10 ether)
        );

        assertEq(allocations.length, 2);
        assertEq(allocations[0], 1 ether);
        assertEq(allocations[1], 5 ether);
        assertEq(allocations[0] + allocations[1], 6 ether);
    }

    function test_topUpObtainDepositData_emptyKeysReturnsEmpty() public assertInvariants {
        uint256 nonce = module.getNonce();
        uint256[] memory allocations = cm.allocateDeposits(1 ether, new bytes[](0), UintArr(), UintArr(), UintArr());

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_topUpObtainDepositData_allZeroWeightsReturnsZeroAllocations() public assertInvariants {
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

    function test_topUpObtainDepositData_zeroLimitSkipsAllocation() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        cm.updateOperatorBalances(_encodeNodeOperatorIds(UintArr(noId)), _encodeUint128Values(UintArr(10)));

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

    function test_topUpObtainDepositData_zeroWeightOperatorSkipped() public assertInvariants {
        uint256 zeroWeightId = createNodeOperator(1);
        uint256 weightedId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(zeroWeightId, weightedId)),
            _encodeUint128Values(UintArr(10, 10))
        );

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        uint256 curveId = accounting.addBondCurve(curve);
        accounting.setBondCurve(zeroWeightId, curveId);
        _mockOperatorWeight(zeroWeightId, 0);

        bytes memory key0 = module.getSigningKeys(zeroWeightId, 0, 1);
        bytes memory key1 = module.getSigningKeys(weightedId, 0, 1);
        uint256 limitWei = 1 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            1 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(zeroWeightId, weightedId),
            UintArr(limitWei, limitWei)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 1 ether);
    }

    function test_topUpObtainDepositData_balancesReweightAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(10_000_000_000, 0))
        );

        bytes memory key0 = module.getSigningKeys(firstId, 0, 1);
        bytes memory key1 = module.getSigningKeys(secondId, 0, 1);
        uint256 limitWei = 2 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            1 ether,
            BytesArr(key0, key1),
            UintArr(0, 0),
            UintArr(firstId, secondId),
            UintArr(limitWei, limitWei)
        );

        assertEq(allocations[0], 0);
        assertEq(allocations[1], 1 ether);
    }

    function test_topUpObtainDepositData_belowStepAllocatesZero() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        cm.updateOperatorBalances(_encodeNodeOperatorIds(UintArr(noId)), _encodeUint128Values(UintArr(10)));

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        uint256 limitWei = 10 ether;

        uint256[] memory allocations = cm.allocateDeposits(
            1 ether - 1,
            BytesArr(key),
            UintArr(0),
            UintArr(noId),
            UintArr(limitWei)
        );

        assertEq(allocations[0], 0);
    }

    function test_topUpObtainDepositData_revertWhen_NotStakingRouter() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        cm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
    }

    function test_topUpObtainDepositData_zeroDepositReturnsEmpty() public assertInvariants {
        uint256 nonce = module.getNonce();
        uint256[] memory allocations = cm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());

        assertEq(allocations.length, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_topUpObtainDepositData_revertWhen_LengthMismatch() public assertInvariants {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        cm.allocateDeposits(1 ether, new bytes[](0), UintArr(), UintArr(0), UintArr());
    }

    function test_topUpObtainDepositData_revertWhen_OperatorIdOutOfRange() public assertInvariants {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        cm.allocateDeposits(1 ether, BytesArr(new bytes(48)), UintArr(0), UintArr(1), UintArr(1 ether));
    }

    function test_topUpObtainDepositData_revertWhen_KeyIndexOutOfRange() public assertInvariants {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        cm.allocateDeposits(1 ether, BytesArr(key), UintArr(1), UintArr(noId), UintArr(1 ether));
    }

    function test_topUpObtainDepositData_revertWhen_PubkeyMismatch() public assertInvariants {
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
        // inflow = 6
        // targetTotal = 68 + 6 = 74
        // targets = [ceil(74/2), ceil(74/2)] = [37, 37]
        // imbalances = [1, 5]
        // deposits greedy => [1, 5]
        (uint256 allocated, uint256[] memory ids, uint256[] memory allocs) = cm.getDepositsAllocation(6 ether);

        assertEq(allocated, 6 ether);
        assertEq(ids.length, 2);
        assertEq(ids[0], firstId);
        assertEq(ids[1], secondId);
        assertEq(allocs[0], 1 ether);
        assertEq(allocs[1], 5 ether);
    }

    function test_topUpObtainDepositData_externalStakeReducesAllocation() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);
        module.obtainDepositData(2, "");

        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(5 ether / 1 gwei, 5 ether / 1 gwei))
        );

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
}

contract CuratedUpdateOperatorBalances is CuratedCommon {
    function test_updateOperatorBalances_storesBalancesAndIncrementsNonce() public assertInvariants {
        uint256 firstId = createNodeOperator(1);
        uint256 secondId = createNodeOperator(1);

        uint256 nonce = module.getNonce();
        cm.updateOperatorBalances(
            _encodeNodeOperatorIds(UintArr(firstId, secondId)),
            _encodeUint128Values(UintArr(13, 24))
        );

        assertEq(module.getNonce(), nonce + 1);
        assertEq(cm.getNodeOperatorBalance(firstId), 13 gwei);
        assertEq(cm.getNodeOperatorBalance(secondId), 24 gwei);
    }

    function test_updateOperatorBalances_RevertWhen_LengthMismatch() public {
        createNodeOperator(1);

        vm.expectRevert(ValidatorCountsReport.InvalidReportData.selector);
        cm.updateOperatorBalances(_encodeNodeOperatorIds(UintArr(0)), _encodeUint128Values(UintArr(1, 2)));
    }

    function test_updateOperatorBalances_RevertWhen_NodeOperatorDoesNotExist() public {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        cm.updateOperatorBalances(_encodeNodeOperatorIds(UintArr(1)), _encodeUint128Values(UintArr(1)));
    }

    function test_updateOperatorBalances_RevertWhen_NotStakingRouter() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        cm.updateOperatorBalances(_encodeNodeOperatorIds(UintArr()), _encodeUint128Values(UintArr()));
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

contract CuratedReportWithdrawnValidators is ModuleReportWithdrawnValidators, CuratedCommon {}

contract CuratedKeyAddedBalance is ModuleKeyAddedBalance, CuratedCommon {}

contract CuratedTopUpKeyAddedBalance is CuratedCommon {
    function test_topUp_emitsKeyAddedBalanceChanged() public {
        createNodeOperator(1);
        cm.obtainDepositData(1, "");

        bytes memory key = cm.getSigningKeys(0, 0, 1);
        bytes[] memory pubkeys = BytesArr(key);

        vm.expectEmit(address(cm));
        emit IBaseModule.KeyAddedBalanceChanged(0, 0, 5 ether);

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
        cm.obtainDepositData(1, "");

        uint256 cap = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE - WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;
        cm.increaseKeyAddedBalance(0, 0, cap);

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
        bytes32 signature = keccak256("KeyAddedBalanceChanged(uint256,uint256,uint256)");
        for (uint256 i; i < entries.length; ++i) {
            assertNotEq(entries[i].topics[0], signature);
        }
    }
}

contract CuratedGetStakingModuleSummary is ModuleGetStakingModuleSummary, CuratedCommon {}

contract CuratedAccessControl is ModuleAccessControl, CuratedCommonNoRoles {}

contract CuratedStakingRouterAccessControl is ModuleStakingRouterAccessControl, CuratedCommonNoRoles {
    function test_stakingRouterRole_onWithdrawalCredentialsChanged_noDepositable() public override {
        vm.skip(true);
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_withDepositable() public {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        // TODO: need proper revert message from onWithdrawalCredentialsChanged
        vm.expectRevert();
        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
    }
}

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
        assertEq(module.getInitializedVersion(), 1);
    }

    function test_onNodeOperatorBondCurveChange_updatesDepositable() public assertInvariants {
        uint256 noId = createNodeOperator(4);

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        accounting.updateBondCurve(0, BOND_SIZE * 2);
        cm.onNodeOperatorBondCurveChange(noId);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 2);
    }

    function test_onNodeOperatorBondCurveChange_ZeroDepositableIfWeightIsZero() public assertInvariants {
        uint256 noId = createNodeOperator(4);

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        _mockOperatorWeight(noId, 0);
        cm.onNodeOperatorBondCurveChange(noId);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 0);
    }

    function test_requestFullDepositInfoUpdate_fromAccounting() public {
        createNodeOperator(1);

        uint256 nonceBefore = module.getNonce();

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        uint256 nonceAfter = module.getNonce();

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 1);
        assertEq(nonceAfter, nonceBefore + 1);
    }

    function test_requestFullDepositInfoUpdate_fromMetaRegistry() public {
        createNodeOperator(1);

        uint256 nonceBefore = module.getNonce();

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

contract CuratedChangeNodeOperatorAddresses is CuratedCommon {
    function test_changeNodeOperatorAddresses_NoExtendedManagerPermissions_SingleOwner() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(noId, nodeOperator, manager);

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(noId, nodeOperator, rewards);

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_NoExtendedManagerPermissions_SeparateManagerReward() public {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(noId, managerToChange, manager);

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(noId, rewardsToChange, rewards);

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ExtendedManagerPermissions_SingleOwner() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: true
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(noId, nodeOperator, manager);

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(noId, nodeOperator, rewards);

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ExtendedManagerPermissions_SeparateManagerReward() public {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: true
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(noId, managerToChange, manager);

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(noId, rewardsToChange, rewards);

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
    }

    function test_changeNodeOperatorAddresses_ChangesOnlyGivenAddress() public {
        address managerToChange = nextAddress();
        address rewardsToChange = nextAddress();

        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: managerToChange,
                rewardAddress: rewardsToChange,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        uint256 snapshot = vm.snapshotState();

        {
            vm.expectEmit(address(cm));
            emit INOAddresses.NodeOperatorRewardAddressChanged(noId, rewardsToChange, rewards);

            vm.recordLogs();
            cm.changeNodeOperatorAddresses(noId, managerToChange, rewards);
            assertEq(vm.getRecordedLogs().length, 1);
        }
        vm.revertToState(snapshot);

        {
            vm.expectEmit(address(cm));
            emit INOAddresses.NodeOperatorManagerAddressChanged(noId, managerToChange, manager);

            vm.recordLogs();
            cm.changeNodeOperatorAddresses(noId, manager, rewardsToChange);
            assertEq(vm.getRecordedLogs().length, 1);
        }
        vm.revertToState(snapshot);
    }

    function test_changeNodeOperatorAddresses_ResetProposedAddresses() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        address proposedManager = nextAddress();
        address proposedRewards = nextAddress();

        vm.startPrank(nodeOperator);
        cm.proposeNodeOperatorManagerAddressChange(noId, proposedManager);
        cm.proposeNodeOperatorRewardAddressChange(noId, proposedRewards);
        vm.stopPrank();

        assertEq(cm.getNodeOperator(noId).proposedManagerAddress, proposedManager);
        assertEq(cm.getNodeOperator(noId).proposedRewardAddress, proposedRewards);

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorManagerAddressChanged(noId, nodeOperator, manager);

        vm.expectEmit(address(cm));
        emit INOAddresses.NodeOperatorRewardAddressChanged(noId, nodeOperator, rewards);

        cm.changeNodeOperatorAddresses(noId, manager, rewards);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, rewards);
        assertEq(cm.getNodeOperator(noId).proposedManagerAddress, address(0));
        assertEq(cm.getNodeOperator(noId).proposedRewardAddress, address(0));
    }

    function test_changeNodeOperatorAddresses_RevertsIfOperatorDoesNotExist() public {
        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        cm.changeNodeOperatorAddresses(0, manager, rewards);
    }

    function test_changeNodeOperatorAddresses_RevertsIfHasNoRole() public {
        assertFalse(cm.hasRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this)));

        address manager = nextAddress();
        address rewards = nextAddress();

        expectRoleRevert(address(this), cm.OPERATOR_ADDRESSES_ADMIN_ROLE());
        cm.changeNodeOperatorAddresses(0, manager, rewards);
    }

    function test_changeNodeOperatorAddresses_RevertsIfZeroAddressProvided() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nextAddress(),
                rewardAddress: nextAddress(),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        vm.startPrank(admin);
        cm.grantRole(cm.OPERATOR_ADDRESSES_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        address manager = nextAddress();
        address rewards = nextAddress();

        vm.expectRevert(INOAddresses.ZeroManagerAddress.selector);
        cm.changeNodeOperatorAddresses(noId, address(0), rewards);

        vm.expectRevert(INOAddresses.ZeroRewardAddress.selector);
        cm.changeNodeOperatorAddresses(noId, manager, address(0));
    }
}

contract CuratedHooks is CuratedCommon {
    function test_notifyNodeOperatorWeightChange_bumpsNonce() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nextAddress(),
                rewardAddress: nextAddress(),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        uint256 oldNonce = cm.getNonce();
        address metaRegistry = address(cm.META_REGISTRY());
        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 154);

        uint256 newNonce = cm.getNonce();
        assertEq(newNonce, oldNonce + 1);
    }

    function test_notifyNodeOperatorWeightChange_depositableIsZeroWhenWeightIsZero() public {
        uint256 noId = cm.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: nextAddress(),
                rewardAddress: nextAddress(),
                extendedManagerPermissions: false
            }),
            address(0)
        );

        address metaRegistry = address(cm.META_REGISTRY());
        vm.prank(metaRegistry);
        cm.notifyNodeOperatorWeightChange(noId, 0);

        NodeOperator memory no = cm.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_notifyNodeOperatorWeightChange_revertWhen_NotMetaRegistry() public {
        vm.expectRevert(ICuratedModule.SenderIsNotMetaRegistry.selector);
        cm.notifyNodeOperatorWeightChange(0, 0);
    }
}

contract CuratedBatchDepositInfoUpdate is ModuleBatchDepositInfoUpdate, CuratedCommon {}
