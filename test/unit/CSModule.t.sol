// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { console } from "forge-std/console.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { Batch } from "src/lib/DepositQueueLib.sol";
import { CSModule } from "src/CSModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IBaseModule, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ITopUpQueueLib } from "src/lib/TopUpQueueLib.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { Stub } from "../helpers/mocks/Stub.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract/ModuleAbstract.t.sol";

contract CSMCommon is ModuleFixtures {
    using Strings for uint256;
    using Strings for uint128;

    CSModule csm;
    uint8 topUpQueueLimit;

    function moduleType() internal pure override returns (ModuleType) {
        return ModuleType.Community;
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
        _configureParametersRegistry();
        exitPenalties = new ExitPenaltiesMock();

        IBondCurve.BondCurveIntervalInput[] memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: BOND_SIZE });
        accounting = new AccountingMock(BOND_SIZE, address(wstETH), address(stETH), address(feeDistributor));

        _deployModule(topUpQueueLimit);
    }

    function _deployModule(uint8 queueLimit) internal {
        module = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        csm = CSModule(address(module));

        accounting.setModule(module);

        _enableInitializers(address(module));
        csm.initialize({ admin: admin, topUpQueueLimit: queueLimit });

        vm.startPrank(admin);
        {
            module.grantRole(module.RESUME_ROLE(), address(admin));
            module.resume();
            module.revokeRole(module.RESUME_ROLE(), address(admin));
        }
        vm.stopPrank();

        _setupRolesForTests();
    }

    function _configureParametersRegistry() internal virtual {
        parametersRegistry.setQueueLowestPriority(0);
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

    function _moduleInvariants() internal override {
        assertModuleEnqueuedCount(csm);
        assertModuleKeys(module);
        assertModuleUnusedStorageSlots(module);
    }

    // Checks that the queue is in the expected state starting from its head.
    function _assertQueueState(uint256 priority, BatchInfo[] memory exp) internal view {
        (uint128 curr, ) = csm.depositQueuePointers(priority); // queue.head

        for (uint256 i = 0; i < exp.length; ++i) {
            BatchInfo memory b = exp[i];
            Batch item = csm.depositQueueItem(priority, curr);

            assertFalse(
                item.isNil(),
                string.concat("unexpected end of queue with priority=", priority.toString(), " at index ", i.toString())
            );

            curr = item.next();
            uint256 noId = item.noId();
            uint256 keysInBatch = item.keys();

            assertEq(
                noId,
                b.nodeOperatorId,
                string.concat(
                    "unexpected `nodeOperatorId` at queue with priority=",
                    priority.toString(),
                    " at index ",
                    i.toString()
                )
            );
            assertEq(
                keysInBatch,
                b.count,
                string.concat(
                    "unexpected `count` at queue with priority=",
                    priority.toString(),
                    " at index ",
                    i.toString()
                )
            );
        }

        assertTrue(
            csm.depositQueueItem(priority, curr).isNil(),
            string.concat("unexpected tail of queue with priority=", priority.toString())
        );
    }

    function _assertQueueIsEmpty() internal view {
        for (uint256 p = 0; p <= parametersRegistry.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = csm.depositQueuePointers(p); // queue.head
            assertTrue(
                csm.depositQueueItem(p, curr).isNil(),
                string.concat("queue with priority=", p.toString(), " is not empty")
            );
        }
    }

    function _printQueue() internal view {
        for (uint256 p = 0; p <= parametersRegistry.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = csm.depositQueuePointers(p);

            for (;;) {
                Batch item = csm.depositQueueItem(p, curr);
                if (item.isNil()) break;

                uint256 noId = item.noId();
                uint256 keysInBatch = item.keys();

                console.log(
                    string.concat(
                        "queue.priority=",
                        p.toString(),
                        "[",
                        curr.toString(),
                        "]={noId:",
                        noId.toString(),
                        ",count:",
                        keysInBatch.toString(),
                        "}"
                    )
                );

                curr = item.next();
            }
        }
    }

    function _isQueueDirty(uint256 maxItems) internal returns (bool) {
        // XXX: Mimic a **eth_call** to avoid state changes.
        uint256 snapshot = vm.snapshotState();
        (uint256 toRemove, ) = csm.cleanDepositQueue(maxItems);
        vm.revertToState(snapshot);
        return toRemove > 0;
    }

    function _getTopUpQueueActive() internal view returns (bool active) {
        (active, , , ) = csm.getTopUpQueue();
    }

    function _getTopUpQueueLimit() internal view returns (uint256 limit) {
        (, limit, , ) = csm.getTopUpQueue();
    }

    function _getTopUpQueueLength() internal view returns (uint256 length) {
        (, , length, ) = csm.getTopUpQueue();
    }

    function _getTopUpQueueHead() internal view returns (uint256 head) {
        (, , , head) = csm.getTopUpQueue();
    }

    function _getTopUpQueueCapacity() internal view returns (uint256) {
        (, uint256 limit, uint256 length, ) = csm.getTopUpQueue();

        if (limit > length) return limit - length;
        return 0;
    }
}

contract CSMCommonNoRoles is CSMCommon {
    function _setupRolesForTests() internal override {
        vm.startPrank(admin);
        {
            // NOTE: Needed for the `createNodeOperator` helper.
            module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        }
        vm.stopPrank();
    }
}

contract CsmFuzz is ModuleFuzz, CSMCommon {}

contract CsmInitialize is CSMCommon {
    function test_constructor() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        assertEq(csm.getType(), "community-staking-module");
        assertEq(address(csm.LIDO_LOCATOR()), address(locator));
        assertEq(address(csm.PARAMETERS_REGISTRY()), address(parametersRegistry));
        assertEq(address(csm.ACCOUNTING()), address(accounting));
        assertEq(address(csm.EXIT_PENALTIES()), address(exitPenalties));
    }

    function test_constructor_RevertWhen_ZeroModuleType() public {
        vm.expectRevert(IBaseModule.ZeroModuleType.selector);
        new CSModule({
            moduleType: bytes32(0),
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroLocator() public {
        vm.expectRevert(IBaseModule.ZeroLocatorAddress.selector);
        new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(0),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress() public {
        vm.expectRevert(IBaseModule.ZeroParametersRegistryAddress.selector);
        new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(0),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroAccountingAddress() public {
        vm.expectRevert(IBaseModule.ZeroAccountingAddress.selector);
        new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(0),
            exitPenalties: address(exitPenalties)
        });
    }

    function test_constructor_RevertWhen_ZeroExitPenaltiesAddress() public {
        vm.expectRevert(IBaseModule.ZeroExitPenaltiesAddress.selector);
        new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(0)
        });
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });
    }

    function test_initialize() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });
        assertTrue(csm.hasRole(csm.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(csm.getRoleMemberCount(csm.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(csm.isPaused());
        assertEq(csm.getInitializedVersion(), 3);
    }

    function test_finalizeUpgradeV3_ClearsFreeSlotsAndDisablesTopUpQueue() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));

        bytes32 slot1 = bytes32(uint256(1));
        vm.store(address(csm), slot1, bytes32(uint256(1)));

        csm.finalizeUpgradeV3();

        assertEq(vm.load(address(csm), slot1), bytes32(0));

        (bool active, uint256 limit, uint256 length, uint256 head) = csm.getTopUpQueue();
        assertFalse(active);
        assertEq(limit, 0);
        assertEq(length, 0);
        assertEq(head, 0);
        assertEq(csm.getInitializedVersion(), 3);
    }

    function test_finalizeUpgradeV3_RevertWhen_calledTwice() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));

        csm.finalizeUpgradeV3();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        csm.finalizeUpgradeV3();
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        vm.expectRevert(IBaseModule.ZeroAdminAddress.selector);
        csm.initialize({ admin: address(0), topUpQueueLimit: 0 });
    }
}

contract CSMPauseTest is ModulePauseTest, CSMCommon {}

contract CSMPauseAffectingTest is ModulePauseAffectingTest, CSMCommon {}

contract CSMCreateNodeOperator is ModuleCreateNodeOperator, CSMCommon {
    function test_createNodeOperator_withReferrer() public assertInvariants {
        {
            vm.expectEmit(address(module));
            emit IBaseModule.NodeOperatorAdded(0, nodeOperator, nodeOperator, false);
            vm.expectEmit(address(module));
            emit IBaseModule.ReferrerSet(0, address(154));
        }
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(154)
        );
    }
}

contract CSMAddValidatorKeys is ModuleAddValidatorKeys, CSMCommon {
    function test_AddValidatorKeysETH_EmitsBatchEnqueued() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 1);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(nodeOperator, noId, 1, keys, signatures);
    }

    function test_AddValidatorKeysStETH_EmitsBatchEnqueued() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: BOND_SIZE, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_AddValidatorKeysWstETH_EmitsBatchEnqueued() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }
}

contract CSMAddValidatorKeysViaGate is ModuleAddValidatorKeysViaGate, CSMCommon {}

contract CSMAddValidatorKeysNegative is ModuleAddValidatorKeysNegative, CSMCommon {}

contract CSMObtainDepositData is ModuleObtainDepositData, CSMCommon {
    function _configureParametersRegistry() internal override {
        parametersRegistry.setQueueLowestPriority(5);
        assertNotEq(PRIORITY_QUEUE, parametersRegistry.QUEUE_LOWEST_PRIORITY());
        REGULAR_QUEUE = uint32(parametersRegistry.QUEUE_LOWEST_PRIORITY());
    }

    function test_obtainDepositData_MultipleOperators() public assertInvariants {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(3);
        uint256 thirdId = createNodeOperator(1);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(firstId, 0);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(secondId, 0);
        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(thirdId, 0);
        module.obtainDepositData(6, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 6);
        assertEq(depositableValidatorsCount, 0);
    }

    function test_obtainDepositData_AcrossDifferentQueues() public assertInvariants {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 20);

        parametersRegistry.setQueueConfig({ curveId: 0, priority: 0, maxDeposits: 10 });
        uploadMoreKeys(noId, 20);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(noId, 5);
        module.obtainDepositData(35, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 35);
        assertEq(depositableValidatorsCount, 5);
    }

    function test_obtainDepositData_AcrossDifferentQueues_OnlyOneQueueProcessed() public assertInvariants {
        uint256 noId = createNodeOperator(0);

        parametersRegistry.setQueueConfig({ curveId: 0, priority: 0, maxDeposits: 10 });
        uploadMoreKeys(noId, 20);

        vm.expectEmit(address(module));
        emit IBaseModule.DepositableSigningKeysCountChanged(noId, 10);
        module.obtainDepositData(10, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 10);
        assertEq(depositableValidatorsCount, 10);
    }

    function test_obtainDepositData_zeroDeposits_enqueuedCount() public assertInvariants {
        uint256 noId = createNodeOperator();

        module.obtainDepositData(0, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 1);
    }

    function test_obtainDepositData_counters_WhenLessThanLastBatch_enqueuedCount() public assertInvariants {
        uint256 noId = createNodeOperator(7);

        module.obtainDepositData(3, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 4);
    }

    function test_obtainDepositData_OneOperator_zeroedEnqueuedCount() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        module.obtainDepositData(1, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 0);
    }

    function test_obtainDepositData_RevertWhen_NotEnoughKeys() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.NotEnoughKeys.selector);
        module.obtainDepositData(2, "");
    }

    function test_obtainDepositData_RevertWhen_DepositInfoIsNotUpToDate() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        module.obtainDepositData(1, "");
    }

    function testFuzz_obtainDepositData_OneOperator_enqueuedCount(
        uint256 batchCount,
        uint256 random
    ) public assertInvariants {
        batchCount = bound(batchCount, 1, 20);
        random = bound(random, 1, 20);
        vm.assume(batchCount > random);

        uint256 totalKeys = 1;
        createNodeOperator(1);
        for (uint256 i = 1; i < batchCount + 1; ++i) {
            uint256 keys = i / random + 1;
            uploadMoreKeys(0, keys);
            totalKeys += keys;
        }

        module.obtainDepositData(totalKeys - random, "");

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.enqueuedCount, random);
    }

    function testFuzz_obtainDepositData_MultipleOperators_exactCounters(
        uint256 batchCount,
        uint256 random
    ) public assertInvariants {
        batchCount = bound(batchCount, 1, 20);
        random = bound(random, 1, 20);
        vm.assume(batchCount > random);

        uint256 totalKeys;
        for (uint256 i = 1; i < batchCount + 1; ++i) {
            uint256 keys = i / random + 1;
            createNodeOperator(keys);
            totalKeys += keys;
        }

        module.obtainDepositData(totalKeys - random, "");

        (, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);
    }
}

contract CSMTopUpQueue is CSMCommon {
    function setUp() public override {
        // Enabling the queue.
        topUpQueueLimit = 32;

        super.setUp();

        vm.startPrank(admin);
        csm.grantRole(csm.MANAGE_TOP_UP_QUEUE_ROLE(), address(this));
        csm.grantRole(csm.REWIND_TOP_UP_QUEUE_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_topUpQueueDisablesUponInitializationWithZeroLimit() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        assertFalse(_getTopUpQueueActive());
    }

    function test_newDepositsScheduleTopUps() public {
        createNodeOperator(2);
        createNodeOperator(2);
        createNodeOperator(2);

        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 3);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 0);
        assertEq(keyIndex, 0);

        (noId, keyIndex) = csm.getTopUpQueueItem(1);
        assertEq(noId, 0);
        assertEq(keyIndex, 1);

        (noId, keyIndex) = csm.getTopUpQueueItem(2);
        assertEq(noId, 1);
        assertEq(keyIndex, 0);

        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 6);

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 0);
        assertEq(keyIndex, 0);

        (noId, keyIndex) = csm.getTopUpQueueItem(1);
        assertEq(noId, 0);
        assertEq(keyIndex, 1);

        (noId, keyIndex) = csm.getTopUpQueueItem(2);
        assertEq(noId, 1);
        assertEq(keyIndex, 0);

        (noId, keyIndex) = csm.getTopUpQueueItem(3);
        assertEq(noId, 1);
        assertEq(keyIndex, 1);

        (noId, keyIndex) = csm.getTopUpQueueItem(4);
        assertEq(noId, 2);
        assertEq(keyIndex, 0);

        (noId, keyIndex) = csm.getTopUpQueueItem(5);
        assertEq(noId, 2);
        assertEq(keyIndex, 1);
    }

    function test_noNewDepositsWhenTopUpQueueHasNoCapacity() public {
        csm.setTopUpQueueLimit(3);

        createNodeOperator(4);
        csm.obtainDepositData(2, "");

        vm.expectRevert(ITopUpQueueLib.TopUpQueueIsFull.selector);
        csm.obtainDepositData(2, "");

        csm.obtainDepositData(1, "");

        vm.expectRevert(ITopUpQueueLib.TopUpQueueIsFull.selector);
        csm.obtainDepositData(1, "");
    }

    function test_depositsAllowedWhenTopUpQueueCapacityRestored() public {
        csm.setTopUpQueueLimit(3);
        assertEq(_getTopUpQueueCapacity(), 3);

        createNodeOperator(5);
        csm.obtainDepositData(3, "");
        assertEq(_getTopUpQueueCapacity(), 0);

        vm.expectRevert(ITopUpQueueLib.TopUpQueueIsFull.selector);
        csm.obtainDepositData(1, "");

        csm.setTopUpQueueLimit(4);
        assertEq(_getTopUpQueueCapacity(), 1);
        csm.obtainDepositData(1, "");

        assertEq(_getTopUpQueueCapacity(), 0);
        csm.allocateDeposits({
            maxDepositAmount: 0,
            pubkeys: BytesArr(csm.getSigningKeys(0, 0, 1)),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(0)
        });
        assertEq(_getTopUpQueueCapacity(), 1);
        csm.obtainDepositData(1, "");
    }

    function test_moduleDepositableLimitedByTopUpQueueCapacity() public {
        createNodeOperator(10);

        uint256 depositable;

        (, , depositable) = csm.getStakingModuleSummary();
        assertEq(depositable, 10);

        csm.setTopUpQueueLimit(3);
        (, , depositable) = csm.getStakingModuleSummary();
        assertEq(depositable, 3);

        csm.setTopUpQueueLimit(8);
        (, , depositable) = csm.getStakingModuleSummary();
        assertEq(depositable, 8);
    }

    function test_topUp_RevertWhenDepositQueueDisabled() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
    }

    function test_topUp_nonceDoesNotChangeWhenNoKeysProvided() public {
        uint256 nonceBefore = csm.getNonce();
        csm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
        assertEq(csm.getNonce(), nonceBefore);
    }

    function test_topUp_DepositAmountBelowTopUpLimit() public {
        createNodeOperator(3);
        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(6 ether, 6 ether)
        });

        assertEq(_getTopUpQueueLength(), 2);
        assertEq(allocations, UintArr(6 ether, 4 ether));
        assertEq(module.getTotalModuleStake(), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getNodeOperatorBalance(0), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 0);
        assertEq(keyIndex, 1);
    }

    function test_topUp_DepositAmountAboveTopUpLimit() public {
        createNodeOperator(3);
        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 6 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(4 ether, 2 ether)
        });

        assertEq(_getTopUpQueueLength(), 1);
        assertEq(allocations, UintArr(4 ether, 2 ether));
        assertEq(module.getTotalModuleStake(), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);
        assertEq(module.getNodeOperatorBalance(0), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 6 ether);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 0);
        assertEq(keyIndex, 2);
    }

    function test_topUp_RemovesFullKeys() public {
        createNodeOperator(2);
        createNodeOperator(1);
        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 4 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(2 ether, 2 ether)
        });

        assertEq(allocations, UintArr(2 ether, 2 ether));
        assertEq(module.getTotalModuleStake(), 3 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(module.getNodeOperatorBalance(0), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(module.getNodeOperatorBalance(1), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);

        assertEq(_getTopUpQueueLength(), 1);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 1);
        assertEq(keyIndex, 0);
    }

    function test_topUp_RemovesKeysWithoutCapacity() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        assertEq(_getTopUpQueueLength(), 2);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(2 ether, 0)
        });

        assertEq(allocations, UintArr(2 ether, 0));
        assertEq(module.getTotalModuleStake(), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
        assertEq(module.getNodeOperatorBalance(0), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);

        assertEq(_getTopUpQueueLength(), 0);
    }

    function test_topUp_skipsSubStepTopUpLimits() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(2 ether - 1 gwei, 2 ether)
        });

        assertEq(allocations, UintArr(0, 2 ether));
        assertEq(module.getTotalModuleStake(), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
        assertEq(module.getNodeOperatorBalance(0), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
        assertEq(_getTopUpQueueLength(), 0);
    }

    function test_topUp_capsAllocationByKeyAllocatedBalance() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 5000 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5000 ether)
        });

        assertEq(
            allocations[0],
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        );
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(module.getNodeOperatorBalance(0), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(_getTopUpQueueLength(), 0);
    }

    function test_topUp_rewindedWithdrawnHeadKeyIsDequeuedWithoutAllocation() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes memory key0 = slice(packedPubkeys, 0, 48);
        bytes memory key1 = slice(packedPubkeys, 48, 48);

        csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: BytesArr(key0),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(2 ether)
        });

        WithdrawnValidatorInfo[] memory infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether,
            slashingPenalty: 0,
            isSlashed: false
        });
        csm.reportRegularWithdrawnValidators(infos);

        csm.rewindTopUpQueue(0);

        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 4 ether,
            pubkeys: BytesArr(key0, key1),
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(4 ether, 4 ether)
        });

        assertEq(allocations, UintArr(0, 4 ether));
        assertEq(csm.getKeyAllocatedBalances(0, 0, 2), UintArr(2 ether, 4 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(module.getNodeOperatorBalance(0), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(_getTopUpQueueLength(), 0);
    }

    function test_topUp_emitsKeyAllocatedBalanceChanged() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        vm.expectEmit(address(csm));
        emit IBaseModule.KeyAllocatedBalanceChanged(0, 0, 4 ether);

        csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5 ether)
        });
    }

    function test_topUp_emitsTopUpQueueItemProcessedForEachKey() public {
        createNodeOperator(2);
        createNodeOperator(1);
        csm.obtainDepositData(3, "");

        bytes memory packed = csm.getSigningKeys(0, 0, 2);
        bytes memory key2 = csm.getSigningKeys(1, 0, 1);
        bytes[] memory pubkeys = BytesArr(slice(packed, 0, 48), slice(packed, 48, 48), key2);

        vm.expectEmit(address(csm));
        emit ICSModule.TopUpQueueItemProcessed(0, 0);
        vm.expectEmit(address(csm));
        emit ICSModule.TopUpQueueItemProcessed(0, 1);
        vm.expectEmit(address(csm));
        emit ICSModule.TopUpQueueItemProcessed(1, 0);

        csm.allocateDeposits({
            maxDepositAmount: 6 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1, 0),
            operatorIds: UintArr(0, 0, 1),
            topUpLimits: UintArr(2 ether, 2 ether, 2 ether)
        });
    }

    function test_topUp_noProcessedEventWhenPartialAllocation() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);

        vm.recordLogs();
        csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4 ether)
        });
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint256 i; i < entries.length; ++i) {
            assertNotEq(entries[i].topics[0], ICSModule.TopUpQueueItemProcessed.selector);
        }
    }

    function test_topUp_quantizesDepositAmountToStep() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);

        uint256[] memory firstAllocations = csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4 ether)
        });

        assertEq(firstAllocations, UintArr(2 ether));
        assertEq(_getTopUpQueueLength(), 1);
        assertEq(csm.getKeyAllocatedBalances(0, 0, 1), UintArr(2 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);
        assertEq(module.getNodeOperatorBalance(0), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 2 ether);

        uint256[] memory secondAllocations = csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(2 ether)
        });

        assertEq(secondAllocations, UintArr(2 ether));
        assertEq(_getTopUpQueueLength(), 0);
        assertEq(csm.getKeyAllocatedBalances(0, 0, 1), UintArr(4 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
        assertEq(module.getNodeOperatorBalance(0), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 4 ether);
    }

    function test_topUp_noEmitWhenKeyAtCap() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        setKeyConfirmedBalance(
            0,
            0,
            ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        );

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        vm.recordLogs();
        csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5 ether)
        });

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            assertNotEq(entries[i].topics[0], IBaseModule.KeyAllocatedBalanceChanged.selector);
        }
    }

    function test_topUp_allocatesOnlyRemainingToCap() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        uint256 cap = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
        setKeyConfirmedBalance(0, 0, cap - 2 ether);

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        vm.expectEmit(address(csm));
        // keyAllocatedBalance is already at cap - 2 ether (set by reportValidatorBalance), allocation adds 2 ether to reach cap
        emit IBaseModule.KeyAllocatedBalanceChanged(0, 0, cap);

        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(5 ether)
        });

        assertEq(allocations, UintArr(2 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
        assertEq(module.getNodeOperatorBalance(0), ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE);
    }

    function test_withdrawalChargesMissedAmount() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        csm.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(10 ether)
        });

        // Confirm the top-up on-chain via a balance proof so penalty calculation uses the full balance.
        setKeyConfirmedBalance(0, 0, 10 ether);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(0);
        uint256 bondBefore = accounting.getBond(0);

        WithdrawnValidatorInfo[] memory infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: 40 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        csm.reportRegularWithdrawnValidators(infos);
        assertEq(accounting.getBond(0), bondBefore - 2 ether);
    }

    function test_topUp_nonceIncrementsWhenKeysProvided() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        uint256 nonceBefore = csm.getNonce();

        bytes memory keys = csm.getSigningKeys(0, 0, 1);
        csm.allocateDeposits({
            maxDepositAmount: 0,
            pubkeys: BytesArr(keys),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(0)
        });

        assertEq(csm.getNonce(), nonceBefore + 1);
    }

    function test_topUp_RevertWhenTheSameKeyTwiceAboveDepositAmount() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory key = csm.getSigningKeys(0, 0, 1);
        bytes[] memory pubkeys = BytesArr(key, key);
        vm.expectRevert(ICSModule.UnexpectedExtraKey.selector);
        csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 0),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(4 ether, 4 ether)
        });
    }

    function test_topUp_RevertWhenNextItemDoesNotMatch() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory key = csm.getSigningKeys(0, 1, 1);
        bytes[] memory pubkeys = BytesArr(key);

        // Operator ID mismatch
        vm.expectRevert(ICSModule.InvalidTopUpOrder.selector);
        csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(1),
            topUpLimits: UintArr(4 ether)
        });

        // Operator key index mismatch
        vm.expectRevert(ICSModule.InvalidTopUpOrder.selector);
        csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(1),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4 ether)
        });

        vm.expectRevert(SigningKeys.InvalidSigningKey.selector);
        csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4 ether)
        });
    }

    function test_topUp_RevertWhenKeysAboveDepositAmount() public {
        createNodeOperator(3);
        csm.obtainDepositData(3, "");

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 3);
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = slice(packedPubkeys, 0 * 48, 48);
        pubkeys[1] = slice(packedPubkeys, 1 * 48, 48);
        pubkeys[2] = slice(packedPubkeys, 2 * 48, 48);
        vm.expectRevert(ICSModule.UnexpectedExtraKey.selector);
        csm.allocateDeposits({
            maxDepositAmount: 1 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1, 2),
            operatorIds: UintArr(0, 0, 0),
            topUpLimits: UintArr(1 ether, 4 ether, 0)
        });
    }

    function test_topUp_RevertWhen_LengthMismatch() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        csm.allocateDeposits({
            maxDepositAmount: 1 ether,
            pubkeys: new bytes[](0),
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(1 ether)
        });
    }

    function test_topUp_RevertWhen_PubkeyLengthMismatch() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes[] memory pubkeys = BytesArr(new bytes(47));
        vm.expectRevert(SigningKeys.InvalidSigningKey.selector);
        csm.allocateDeposits({
            maxDepositAmount: 1 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(1 ether)
        });
    }

    function test_topUp_revertWhen_inputKeysExceedQueueLength() public {
        csm.setTopUpQueueLimit(2);
        createNodeOperator(3);
        csm.obtainDepositData(1, "");

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 3);
        bytes[] memory pubkeys = new bytes[](3);
        pubkeys[0] = slice(packedPubkeys, 0 * 48, 48);
        pubkeys[1] = slice(packedPubkeys, 1 * 48, 48);
        pubkeys[2] = slice(packedPubkeys, 2 * 48, 48);

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        csm.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1, 2),
            operatorIds: UintArr(0, 0, 0),
            topUpLimits: UintArr(1 ether, 4 ether, 5 ether)
        });
    }

    function test_getKeysForTopUp_ReturnsExpectedKeys() public {
        createNodeOperator(2);
        createNodeOperator(2);
        createNodeOperator(2);

        bytes[] memory keys;
        assertEq(csm.getKeysForTopUp(3), keys);

        csm.obtainDepositData(3, "");
        csm.obtainDepositData(3, "");

        keys = new bytes[](3);
        keys[0] = csm.getSigningKeys(0, 0, 1);
        keys[1] = csm.getSigningKeys(0, 1, 1);
        keys[2] = csm.getSigningKeys(1, 0, 1);

        assertEq(csm.getKeysForTopUp(3), keys);

        keys = new bytes[](6);
        keys[0] = csm.getSigningKeys(0, 0, 1);
        keys[1] = csm.getSigningKeys(0, 1, 1);
        keys[2] = csm.getSigningKeys(1, 0, 1);
        keys[3] = csm.getSigningKeys(1, 1, 1);
        keys[4] = csm.getSigningKeys(2, 0, 1);
        keys[5] = csm.getSigningKeys(2, 1, 1);

        assertEq(csm.getKeysForTopUp(6), keys);
        assertEq(csm.getKeysForTopUp(7), keys);

        csm.allocateDeposits({
            maxDepositAmount: 3 ether,
            pubkeys: BytesArr(keys[0], keys[1], keys[2]),
            keyIndices: UintArr(0, 1, 0),
            operatorIds: UintArr(0, 0, 1),
            topUpLimits: UintArr(1 ether, 1 ether, 1 ether)
        });

        keys = new bytes[](3);
        keys[0] = csm.getSigningKeys(1, 1, 1);
        keys[1] = csm.getSigningKeys(2, 0, 1);
        keys[2] = csm.getSigningKeys(2, 1, 1);

        assertEq(csm.getKeysForTopUp(3), keys);
    }

    function test_getKeysForTopUp_RevertWhenQueueDisabled() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.getKeysForTopUp(0);
    }

    function test_setTopUpQueueLimit() public {
        for (uint256 limit = 1; limit < 256; ++limit) {
            csm.setTopUpQueueLimit(limit);
            assertEq(_getTopUpQueueLimit(), limit);
        }
    }

    function test_setTopUpQueueLimit_incrementsNonce() public {
        uint256 nonceBefore = csm.getNonce();
        csm.setTopUpQueueLimit(1);
        assertEq(csm.getNonce(), nonceBefore + 1);
    }

    function test_setTopUpQueueLimit_RevertWhenLimitZero() public {
        vm.expectRevert(ICSModule.ZeroTopUpQueueLimit.selector);
        csm.setTopUpQueueLimit(0);
    }

    function test_setTopUpQueueLimit_RevertWhenLimitSame() public {
        csm.setTopUpQueueLimit(1);
        vm.expectRevert(ICSModule.SameTopUpQueueLimit.selector);
        csm.setTopUpQueueLimit(1);
    }

    function test_setTopUpQueueLimit_RevertWhenLimitExceedsUint8() public {
        uint256 limit = uint256(type(uint32).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 8, limit));
        csm.setTopUpQueueLimit(limit);
    }

    function test_setTopUpQueueLimit_RevertWhenTopUpQueueDisabled() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        csm.grantRole(csm.MANAGE_TOP_UP_QUEUE_ROLE(), address(this));
        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.setTopUpQueueLimit(0);
    }

    function test_rewindTopUpQueue() public {
        createNodeOperator(2);
        createNodeOperator(1);
        csm.obtainDepositData(3, "");
        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        bytes[] memory pubkeys = BytesArr(slice(packedPubkeys, 0 * 48, 48), slice(packedPubkeys, 1 * 48, 48));
        csm.allocateDeposits({
            maxDepositAmount: 2 ether,
            pubkeys: pubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(1 ether, 1 ether)
        });

        assertEq(_getTopUpQueueLength(), 1);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 1);
        assertEq(keyIndex, 0);

        uint256 to = 1;
        vm.expectEmit(address(csm));
        emit ICSModule.TopUpQueueRewound(to);
        csm.rewindTopUpQueue(to);
        assertEq(_getTopUpQueueHead(), to);
        assertEq(_getTopUpQueueLength(), 2);

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 0);
        assertEq(keyIndex, 1);
    }

    function test_rewindTopUpQueue_RevertWhenExceedsUint32() public {
        uint256 to = uint256(type(uint32).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 32, to));
        csm.rewindTopUpQueue(to);
    }

    function test_rewindTopUpQueue_RevertWhenTopUpQueueDisabled() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        csm.grantRole(csm.REWIND_TOP_UP_QUEUE_ROLE(), address(this));
        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.rewindTopUpQueue(0);
    }

    function test_reportValidatorBalance_RevertWhenTopUpQueueDisabled() public {
        csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        _enableInitializers(address(csm));
        csm.initialize({ admin: address(this), topUpQueueLimit: 0 });

        csm.grantRole(csm.VERIFIER_ROLE(), address(this));
        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.reportValidatorBalance(0, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 1 ether);
    }
}

contract CSMProposeNodeOperatorManagerAddressChange is ModuleProposeNodeOperatorManagerAddressChange, CSMCommon {}

contract CSMConfirmNodeOperatorManagerAddressChange is ModuleConfirmNodeOperatorManagerAddressChange, CSMCommon {}

contract CSMProposeNodeOperatorRewardAddressChange is ModuleProposeNodeOperatorRewardAddressChange, CSMCommon {}

contract CSMConfirmNodeOperatorRewardAddressChange is ModuleConfirmNodeOperatorRewardAddressChange, CSMCommon {}

contract CSMResetNodeOperatorManagerAddress is ModuleResetNodeOperatorManagerAddress, CSMCommon {}

contract CSMChangeNodeOperatorRewardAddress is ModuleChangeNodeOperatorRewardAddress, CSMCommon {}

contract CSMVetKeys is ModuleVetKeys, CSMCommon {}

contract CSMQueueOps is CSMCommon {
    uint256 internal constant LOOKUP_DEPTH = 150; // derived from maxDepositsPerBlock

    function test_emptyQueueIsClean() public assertInvariants {
        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_queueIsDirty_WhenHasBatchOfNonDepositableOperator() public assertInvariants {
        uint256 noId = createNodeOperator({ keysCount: 2 });
        unvetKeys({ noId: noId, to: 0 }); // One of the ways to set `depositableValidatorsCount` to 0.

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertTrue(isDirty, "queue should be dirty");
    }

    function test_queueIsDirty_WhenHasBatchWithNoDepositableKeys() public assertInvariants {
        uint256 noId = createNodeOperator({ keysCount: 2 });
        uploadMoreKeys(noId, 1);
        unvetKeys({ noId: noId, to: 2 });
        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertTrue(isDirty, "queue should be dirty");
    }

    function test_queueIsClean_AfterCleanup() public assertInvariants {
        uint256 noId = createNodeOperator({ keysCount: 2 });
        uploadMoreKeys(noId, 1);
        unvetKeys({ noId: noId, to: 2 });

        (uint256 toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 1, "should remove 1 batch");

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_cleanup_emptyQueue() public assertInvariants {
        _assertQueueIsEmpty();

        (uint256 toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_zeroMaxItems() public assertInvariants {
        (uint256 removed, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(0);
        assertEq(removed, 0, "should not remove any batches");
        assertEq(lastRemovedAtDepth, 0, "lastRemovedAtDepth should be 0");
    }

    function test_cleanup_WhenMultipleInvalidBatchesInRow() public assertInvariants {
        createNodeOperator({ keysCount: 3 });
        createNodeOperator({ keysCount: 5 });
        createNodeOperator({ keysCount: 1 });

        uploadMoreKeys(1, 2);

        unvetKeys({ noId: 1, to: 2 });
        unvetKeys({ noId: 2, to: 0 });

        uint256 toRemove;

        // Operator noId=1 has 1 dangling batch after unvetting.
        // Operator noId=2 is unvetted.
        (toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 2, "should remove 2 batch");

        // let's check the state of the queue
        BatchInfo[] memory exp = new BatchInfo[](2);
        exp[0] = BatchInfo({ nodeOperatorId: 0, count: 3 });
        exp[1] = BatchInfo({ nodeOperatorId: 1, count: 5 });
        _assertQueueState(parametersRegistry.QUEUE_LOWEST_PRIORITY(), exp);

        (toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_WhenAllBatchesInvalid() public assertInvariants {
        createNodeOperator({ keysCount: 2 });
        createNodeOperator({ keysCount: 2 });
        unvetKeys({ noId: 0, to: 0 });
        unvetKeys({ noId: 1, to: 0 });

        (uint256 toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 2, "should remove all batches");

        _assertQueueIsEmpty();
    }

    function test_cleanup_ToVisitCounterIsCorrect() public {
        createNodeOperator({ keysCount: 3 }); // noId: 0
        createNodeOperator({ keysCount: 5 }); // noId: 1
        createNodeOperator({ keysCount: 1 }); // noId: 2
        createNodeOperator({ keysCount: 4 }); // noId: 3
        createNodeOperator({ keysCount: 2 }); // noId: 4

        uploadMoreKeys({ noId: 1, keysCount: 2 });
        uploadMoreKeys({ noId: 3, keysCount: 2 });
        uploadMoreKeys({ noId: 4, keysCount: 2 });

        unvetKeys({ noId: 1, to: 2 });
        unvetKeys({ noId: 2, to: 0 });

        // Items marked with * below are supposed to be removed.
        // (0;3) (1;5) *(2;1) (3;4) (4;2) *(1;2) (3;2) (4;2)

        uint256 snapshot = vm.snapshotState();

        {
            (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({ maxItems: 10 });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }

        vm.revertToState(snapshot);

        {
            (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({ maxItems: 6 });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }
    }

    function test_clean_MaxItemsIsZero() public {
        createNodeOperator({ keysCount: 1 });

        (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({ maxItems: 0 });
        assertEq(toRemove, 0, "toRemove != 0");
        assertEq(toVisit, 0, "toVisit != 0");
    }

    function test_clean_revertWhen_depositInfoNotUpToDate() public {
        createNodeOperator({ keysCount: 1 });

        vm.prank(address(accounting));
        module.requestFullDepositInfoUpdate();

        vm.expectRevert(IBaseModule.DepositInfoIsNotUpToDate.selector);
        csm.cleanDepositQueue({ maxItems: 10 });
    }

    function test_updateDepositableValidatorsCount_NothingToDo() public assertInvariants {
        // `updateDepositableValidatorsCount` will be called on creating a node operator and uploading a key.
        uint256 noId = createNodeOperator();

        (, , uint256 depositableBefore) = module.getStakingModuleSummary();
        uint256 nonceBefore = module.getNonce();

        vm.recordLogs();
        module.updateDepositableValidatorsCount(noId);

        (, , uint256 depositableAfter) = module.getStakingModuleSummary();
        uint256 nonceAfter = module.getNonce();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(depositableBefore, depositableAfter);
        assertEq(nonceBefore, nonceAfter);
        assertEq(logs.length, 0);
    }

    function test_updateDepositableValidatorsCount_NonExistingOperator() public assertInvariants {
        (, , uint256 depositableBefore) = module.getStakingModuleSummary();
        uint256 nonceBefore = module.getNonce();

        vm.recordLogs();
        module.updateDepositableValidatorsCount(100500);

        (, , uint256 depositableAfter) = module.getStakingModuleSummary();
        uint256 nonceAfter = module.getNonce();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(depositableBefore, depositableAfter);
        assertEq(nonceBefore, nonceAfter);
        assertEq(logs.length, 0);
    }

    function test_queueNormalized_WhenSkippedKeysAndTargetValidatorsLimitRaised() public {
        uint256 noId = createNodeOperator(7);
        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 0 });
        csm.cleanDepositQueue(1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 7);

        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 7 });
    }

    function test_queueNormalized_WhenWithdrawalChangesDepositable() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.updateTargetValidatorsLimits({ nodeOperatorId: noId, targetLimitMode: 1, targetLimit: 2 });
        module.obtainDepositData(2, "");
        csm.cleanDepositQueue(1);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }
}

contract CSMPriorityQueue is CSMCommon {
    uint256 constant LOOKUP_DEPTH = 150;

    uint32 constant MAX_DEPOSITS = 10;

    function _configureParametersRegistry() internal override {
        parametersRegistry.setQueueLowestPriority(5);
        assertNotEq(PRIORITY_QUEUE, parametersRegistry.QUEUE_LOWEST_PRIORITY());
        REGULAR_QUEUE = uint32(parametersRegistry.QUEUE_LOWEST_PRIORITY());
    }

    function test_enqueueToPriorityQueue_LessThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 8);

            uploadMoreKeys(noId, 8);
        }

        _assertQueueIsEmptyByPriority(REGULAR_QUEUE);

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 8 });
        _assertQueueState(PRIORITY_QUEUE, exp);
    }

    function test_enqueueToPriorityQueue_MoreThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 10);

            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(REGULAR_QUEUE, noId, 5);

            uploadMoreKeys(noId, 15);
        }

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 10 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 5 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_enqueueToPriorityQueue_AlreadyEnqueuedLessThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uploadMoreKeys(noId, 8);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 2);

            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(REGULAR_QUEUE, noId, 10);

            uploadMoreKeys(noId, 12);
        }

        BatchInfo[] memory exp = new BatchInfo[](2);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 8 });
        exp[1] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 10 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_enqueueToPriorityQueue_AlreadyEnqueuedMoreThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uploadMoreKeys(noId, 12);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(REGULAR_QUEUE, noId, 12);

            uploadMoreKeys(noId, 12);
        }

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 10 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp = new BatchInfo[](2);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        exp[1] = BatchInfo({ nodeOperatorId: noId, count: 12 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_enqueueToPriorityQueue_EnqueuedWithDepositedLessThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uploadMoreKeys(noId, 8);
        module.obtainDepositData(3, ""); // no.enqueuedCount == 5

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 2);

            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(REGULAR_QUEUE, noId, 10);

            uploadMoreKeys(noId, 12);
        }

        BatchInfo[] memory exp = new BatchInfo[](2);

        // The batch was partially consumed by the obtainDepositData call.
        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 5 });
        exp[1] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 10 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_enqueueToPriorityQueue_EnqueuedWithDepositedMoreThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uploadMoreKeys(noId, 12);
        module.obtainDepositData(3, ""); // no.enqueuedCount == 9

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(REGULAR_QUEUE, noId, 12);

            uploadMoreKeys(noId, 12);
        }

        BatchInfo[] memory exp = new BatchInfo[](1);

        // The batch was partially consumed by the obtainDepositData call.
        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 7 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp = new BatchInfo[](2);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        exp[1] = BatchInfo({ nodeOperatorId: noId, count: 12 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_queueCleanupWorksAcrossQueues() public {
        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uint256 noId = createNodeOperator(0);

        uploadMoreKeys(noId, 2);
        uploadMoreKeys(noId, 10);
        uploadMoreKeys(noId, 10);
        // [2] [8] | ... | [2] [10]

        unvetKeys({ noId: noId, to: 2 });

        (uint256 toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 3, "should remove 3 batches");

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_queueCleanupReturnsCorrectDepth() public {
        uint256 noIdOne = createNodeOperator(0);
        uint256 noIdTwo = createNodeOperator(0);

        _enablePriorityQueue(0, 10);
        uploadMoreKeys(noIdOne, 2);
        uploadMoreKeys(noIdOne, 10);
        uploadMoreKeys(noIdOne, 10);

        _enablePriorityQueue(1, 10);
        uploadMoreKeys(noIdTwo, 2);
        uploadMoreKeys(noIdTwo, 8);
        uploadMoreKeys(noIdTwo, 2);

        unvetKeys({ noId: noIdTwo, to: 2 });

        // [0,2] [0,8] | [1,2] [1,8] | ... | [0,2] [0,10] [1,2]
        //     1     2       3     4             5      6     7
        //                         ^                          ^ removed

        uint256 snapshot;

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(3);
            vm.revertToState(snapshot);
            assertEq(toRemove, 0, "should remove 0 batch(es)");
            assertEq(lastRemovedAtDepth, 0, "the depth should be 0");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(4);
            vm.revertToState(snapshot);
            assertEq(toRemove, 1, "should remove 1 batch(es)");
            assertEq(lastRemovedAtDepth, 4, "the depth should be 4");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(7);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(100_500);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }
    }

    function _enablePriorityQueue(uint32 priority, uint32 maxDeposits) internal {
        parametersRegistry.setQueueConfig({ curveId: 0, priority: priority, maxDeposits: maxDeposits });
    }

    function _assertQueueIsEmptyByPriority(uint32 priority) internal view {
        _assertQueueState(priority, new BatchInfo[](0));
    }
}

contract CSMDecreaseVettedSigningKeysCount is ModuleDecreaseVettedSigningKeysCount, CSMCommon {}

contract CSMGetSigningKeys is ModuleGetSigningKeys, CSMCommon {}

contract CSMGetSigningKeysWithSignatures is ModuleGetSigningKeysWithSignatures, CSMCommon {}

contract CSMRemoveKeys is ModuleRemoveKeys, CSMCommon {}

contract CSMRemoveKeysChargeFee is CSMCommon {
    function test_removeKeys_chargeFee() public assertInvariants {
        uint256 noId = createNodeOperator(3);

        uint256 amountToCharge = module.PARAMETERS_REGISTRY().getKeyRemovalCharge(0) * 2;

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, amountToCharge),
            1
        );

        vm.expectEmit(address(module));
        emit IBaseModule.KeyRemovalChargeApplied(noId);

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the charge is fully paid.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_removeKeys_withNoFee() public assertInvariants {
        ParametersRegistryMock registry = parametersRegistry;
        vm.prank(admin);
        registry.setKeyRemovalCharge(0, 0);

        uint256 noId = createNodeOperator(3);

        vm.recordLogs();

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertNotEq(entries[i].topics[0], IBaseModule.KeyRemovalChargeApplied.selector);
        }

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the is no charge.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }
}

contract CSMRemoveKeysReverts is ModuleRemoveKeysReverts, CSMCommon {}

contract CSMGetNodeOperatorNonWithdrawnKeys is ModuleGetNodeOperatorNonWithdrawnKeys, CSMCommon {}

contract CSMGetNodeOperatorSummary is ModuleGetNodeOperatorSummary, CSMCommon {}

contract CSMGetNodeOperator is ModuleGetNodeOperator, CSMCommon {}

contract CSMUpdateTargetValidatorsLimits is ModuleUpdateTargetValidatorsLimits, CSMCommon {}

contract CSMUpdateExitedValidatorsCount is ModuleUpdateExitedValidatorsCount, CSMCommon {}

contract CSMUnsafeUpdateValidatorsCount is ModuleUnsafeUpdateValidatorsCount, CSMCommon {}

contract CSMReportGeneralDelayedPenalty is ModuleReportGeneralDelayedPenalty, CSMCommon {
    function test_reportGeneralDelayedPenalty_UpdatesDepositableAfterUnlock_EmitsBatchEnqueued()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        csm.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        csm.cleanDepositQueue(1);
        NodeOperator memory no = csm.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 0);

        vm.warp(accounting.getBondLockPeriod() + 1);

        vm.expectEmit(address(csm));
        emit ICSModule.BatchEnqueued(parametersRegistry.QUEUE_LOWEST_PRIORITY(), noId, 1);
        accounting.unlockExpiredLock(noId);

        no = csm.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 1);
    }
}

contract CSMCancelGeneralDelayedPenalty is ModuleCancelGeneralDelayedPenalty, CSMCommon {}

contract CSMSettleGeneralDelayedPenaltyBasic is ModuleSettleGeneralDelayedPenaltyBasic, CSMCommon {}

contract CSMSettleGeneralDelayedPenaltyAdvanced is ModuleSettleGeneralDelayedPenaltyAdvanced, CSMCommon {}

contract CSMCompensateGeneralDelayedPenalty is ModuleCompensateGeneralDelayedPenalty, CSMCommon {}

contract CSMReportWithdrawnValidators is ModuleReportWithdrawnValidators, CSMCommon {
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }
}

contract CSMKeyAllocatedBalance is ModuleKeyAllocatedBalance, CSMCommon {
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }
}

contract CSMReportValidatorBalance is ModuleReportValidatorBalance, CSMCommon {
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }

    function test_reportValidatorBalance_doesNotDecreaseKeyAllocatedBalance() public {
        uint256 noId = createNodeOperator(1);
        csm.obtainDepositData(1, "");

        // Allocate 20 ether via top-up, setting keyAllocatedBalance to 20 ether.
        bytes memory key = csm.getSigningKeys(noId, 0, 1);
        csm.allocateDeposits({
            maxDepositAmount: 20 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(20 ether)
        });
        assertEq(csm.getKeyAllocatedBalances(noId, 0, 1), UintArr(20 ether));

        // Confirmed balance below allocated — keyAllocatedBalance must not decrease.
        csm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(csm.getKeyAllocatedBalances(noId, 0, 1), UintArr(20 ether), "keyAllocatedBalance must not decrease");
    }

    function test_reportValidatorBalance_afterTopUp_increasesStakeOnlyByDelta() public {
        uint256 noId = createNodeOperator(1);
        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(noId, 0, 1);
        csm.allocateDeposits({
            maxDepositAmount: 20 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(20 ether)
        });

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 20 ether);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 20 ether);

        csm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);

        assertEq(csm.getKeyAllocatedBalances(noId, 0, 1), UintArr(25 ether));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 25 ether);
    }
}

contract CSMGetStakingModuleSummary is ModuleGetStakingModuleSummary, CSMCommon {}

contract CSMTotalModuleStake is CSMCommon {
    function _enableTopUpQueue() internal {
        _deployModule(32);
    }

    function test_getTotalModuleStake_tracksDeposits_whenTopUpQueueDisabled() public {
        uint256 noId = createNodeOperator(1);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);

        csm.obtainDepositData(1, "");
        assertEq(module.getTotalModuleStake(), 32 ether);
        assertEq(module.getNodeOperatorBalance(noId), 32 ether);
    }

    function test_getTotalModuleStake_tracksWithdrawals_whenTopUpQueueDisabled() public {
        uint256 noId = createNodeOperator(1);

        csm.obtainDepositData(1, "");
        assertEq(module.getTotalModuleStake(), 32 ether);

        WithdrawnValidatorInfo[] memory infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });
        csm.reportRegularWithdrawnValidators(infos);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_getTotalModuleStake_tracksTopUps_whenTopUpQueueEnabled() public {
        _enableTopUpQueue();
        uint256 noId = createNodeOperator(1);

        csm.obtainDepositData(1, "");
        assertEq(module.getTotalModuleStake(), 32 ether);

        bytes memory key = csm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });
        uint256 topUpWei = allocations[0];
        assertEq(module.getTotalModuleStake(), 32 ether + topUpWei);
        assertEq(module.getNodeOperatorBalance(noId), 32 ether + topUpWei);
    }

    function test_getTotalModuleStake_tracksVerifierIncreases_whenTopUpQueueEnabled() public {
        _enableTopUpQueue();
        uint256 noId = createNodeOperator(1);

        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(noId, 0, 1);
        uint256[] memory allocations = csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        uint256 verifiedExtra = allocations[0] + 2 ether;
        csm.reportValidatorBalance(noId, 0, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + verifiedExtra);
    }

    function test_getTotalModuleStake_tracksWithdrawals_whenTopUpQueueEnabled() public {
        _enableTopUpQueue();
        uint256 noId = createNodeOperator(1);

        csm.obtainDepositData(1, "");

        bytes memory key = csm.getSigningKeys(noId, 0, 1);
        csm.allocateDeposits({
            maxDepositAmount: 5 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(5 ether)
        });

        assertGt(module.getTotalModuleStake(), 32 ether);
        assertGt(module.getNodeOperatorBalance(noId), 32 ether);

        WithdrawnValidatorInfo[] memory infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: false
        });
        csm.reportRegularWithdrawnValidators(infos);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }
}

contract CSMFinalizeUpgradeV3 is CSMCommon {
    bytes32 internal constant TOTAL_WITHDRAWN_VALIDATORS_SLOT = bytes32(uint256(3));
    uint64 internal expectedTotalWithdrawn;

    function setUp() public override {
        super.setUp();

        vm.pauseGasMetering();

        uint256 operatorsCount = 1000;

        for (uint256 i; i < operatorsCount; ++i) {
            createNodeOperator(1);
        }

        module.obtainDepositData(operatorsCount, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](operatorsCount);

        for (uint256 i; i < operatorsCount; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: i,
                keyIndex: 0,
                exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0,
                isSlashed: false
            });
        }

        module.reportRegularWithdrawnValidators(validatorInfos);

        // forge-lint: disable-next-line(unsafe-typecast)
        expectedTotalWithdrawn = uint64(operatorsCount);

        vm.store(address(module), TOTAL_WITHDRAWN_VALIDATORS_SLOT, bytes32(0));
        vm.store(address(module), INITIALIZABLE_STORAGE, bytes32(uint256(2)));

        vm.resumeGasMetering();
    }

    function test_finalizeUpgradeV3_MigratesTotalWithdrawnValidators_1k() public {
        vm.startSnapshotGas("finalizeUpgradeV3");
        csm.finalizeUpgradeV3();
        uint256 gasUsed = vm.stopSnapshotGas();
        emit log_named_uint("finalizeUpgradeV3 gas", gasUsed);

        uint256 migrated = uint256(vm.load(address(module), TOTAL_WITHDRAWN_VALIDATORS_SLOT)) & type(uint64).max;
        assertEq(migrated, expectedTotalWithdrawn);
    }
}

contract CSMAccessControl is ModuleAccessControl, CSMCommonNoRoles {
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }

    function test_setTopUpQueueLimit_RevertWhenNoRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = csm.MANAGE_TOP_UP_QUEUE_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        csm.setTopUpQueueLimit(33);
    }

    function test_rewindToUpQueue_RevertWhenNoRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = csm.REWIND_TOP_UP_QUEUE_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        csm.rewindTopUpQueue(33);
    }
}

contract CSMStakingRouterAccessControl is ModuleStakingRouterAccessControl, CSMCommonNoRoles {
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }

    function test_stakingRouterRole_topUps() public {
        bytes32 role = csm.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        csm.grantRole(role, actor);

        vm.prank(actor);
        csm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
    }

    function test_stakingRouterRole_topUps_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        csm.allocateDeposits(0, new bytes[](0), UintArr(), UintArr(), UintArr());
    }
}

contract CSMDepositableValidatorsCount is ModuleDepositableValidatorsCount, CSMCommon {}

contract CSMNodeOperatorStateAfterUpdateCurve is ModuleNodeOperatorStateAfterUpdateCurve, CSMCommon {}

contract CSMOnRewardsMinted is ModuleOnRewardsMinted, CSMCommon {}

contract CSMRecoverERC20 is ModuleRecoverERC20, CSMCommon {}

contract CSMMisc is ModuleMisc, CSMCommon {
    function test_getInitializedVersion() public view override {
        assertEq(module.getInitializedVersion(), 3);
    }

    function test_updateDepositInfo_updatesDepositable() public assertInvariants {
        uint256 noId = createNodeOperator(4);

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        accounting.updateBondCurve(0, BOND_SIZE * 2);
        csm.updateDepositInfo(0);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 2);
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

    function test_requestFullDepositInfoUpdate_revertWhen_SenderIsNotEligible() public {
        createNodeOperator(1);

        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        vm.prank(nextAddress());
        module.requestFullDepositInfoUpdate();
    }
}

contract CSMExitDeadlineThreshold is ModuleExitDeadlineThreshold, CSMCommon {}

contract CSMIsValidatorExitDelayPenaltyApplicable is ModuleIsValidatorExitDelayPenaltyApplicable, CSMCommon {}

contract CSMReportValidatorExitDelay is ModuleReportValidatorExitDelay, CSMCommon {}

contract CSMOnValidatorExitTriggered is ModuleOnValidatorExitTriggered, CSMCommon {}

contract CSMCreateNodeOperators is ModuleCreateNodeOperators, CSMCommon {}

contract CSMBatchDepositInfoUpdate is ModuleBatchDepositInfoUpdate, CSMCommon {}
