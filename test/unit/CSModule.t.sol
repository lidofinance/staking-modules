// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { CommonBase } from "forge-std/Base.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { CSModule } from "src/CSModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";

import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { Stub } from "../helpers/mocks/Stub.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract.t.sol";

contract CSMCommon is ModuleFixtures {
    using Strings for uint256;
    using Strings for uint128;

    function moduleType() internal pure override returns (ModuleType) {
        return ModuleType.Community;
    }

    function getModule() internal view virtual returns (ICSModule) {
        return ICSModule(address(module));
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

        IBondCurve.BondCurveIntervalInput[]
            memory curve = new IBondCurve.BondCurveIntervalInput[](1);
        curve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: BOND_SIZE
        });
        accounting = new AccountingMock(
            BOND_SIZE,
            address(wstETH),
            address(stETH),
            address(feeDistributor)
        );

        module = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });

        accounting.setModule(module);

        _enableInitializers(address(module));
        module.initialize({ admin: admin });

        vm.startPrank(admin);
        {
            module.grantRole(module.RESUME_ROLE(), address(admin));
            module.resume();
            module.revokeRole(module.RESUME_ROLE(), address(admin));
        }
        vm.stopPrank();

        _setupRolesForTests();

        // Just to make sure we configured defaults properly and check things properly.
        assertNotEq(PRIORITY_QUEUE, getModule().QUEUE_LOWEST_PRIORITY());
        REGULAR_QUEUE = uint32(getModule().QUEUE_LOWEST_PRIORITY());
    }

    function _setupRolesForTests() internal virtual {
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), address(this));
        module.grantRole(module.PAUSE_ROLE(), address(this));
        module.grantRole(module.RESUME_ROLE(), address(this));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), address(this));
        module.grantRole(module.STAKING_ROUTER_ROLE(), stakingRouter);
        module.grantRole(
            module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        module.grantRole(
            module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
            address(this)
        );
        module.grantRole(module.VERIFIER_ROLE(), address(this));
        module.grantRole(module.SUBMIT_WITHDRAWALS_ROLE(), address(this));
        vm.stopPrank();
    }

    function _moduleInvariants() internal override {
        assertModuleEnqueuedCount(getModule());
        assertModuleKeys(module);
        assertModuleUnusedStorageSlots(module);
    }

    // Checks that the queue is in the expected state starting from its head.
    function _assertQueueState(
        uint256 priority,
        BatchInfo[] memory exp
    ) internal view {
        (uint128 curr, ) = getModule().depositQueuePointers(priority); // queue.head

        for (uint256 i = 0; i < exp.length; ++i) {
            BatchInfo memory b = exp[i];
            Batch item = getModule().depositQueueItem(priority, curr);

            assertFalse(
                item.isNil(),
                string.concat(
                    "unexpected end of queue with priority=",
                    priority.toString(),
                    " at index ",
                    i.toString()
                )
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
            getModule().depositQueueItem(priority, curr).isNil(),
            string.concat(
                "unexpected tail of queue with priority=",
                priority.toString()
            )
        );
    }

    function _assertQueueIsEmpty() internal view {
        for (uint256 p = 0; p <= getModule().QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = getModule().depositQueuePointers(p); // queue.head
            assertTrue(
                getModule().depositQueueItem(p, curr).isNil(),
                string.concat(
                    "queue with priority=",
                    p.toString(),
                    " is not empty"
                )
            );
        }
    }

    function _printQueue() internal view {
        for (uint256 p = 0; p <= getModule().QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = getModule().depositQueuePointers(p);

            for (;;) {
                Batch item = getModule().depositQueueItem(p, curr);
                if (item.isNil()) {
                    break;
                }

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
        (uint256 toRemove, ) = getModule().cleanDepositQueue(maxItems);
        vm.revertToState(snapshot);
        return toRemove > 0;
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
        assertEq(
            address(csm.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
        assertEq(address(csm.ACCOUNTING()), address(accounting));
        assertEq(address(csm.EXIT_PENALTIES()), address(exitPenalties));
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

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress()
        public
    {
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
        csm.initialize({ admin: address(this) });
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
        csm.initialize({ admin: address(this) });
        assertTrue(csm.hasRole(csm.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(csm.getRoleMemberCount(csm.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(csm.isPaused());
        assertEq(csm.getInitializedVersion(), 2);
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
        csm.initialize({ admin: address(0) });
    }
}

contract CSMPauseTest is ModulePauseTest, CSMCommon {}

contract CSMPauseAffectingTest is ModulePauseAffectingTest, CSMCommon {}

contract CSMCreateNodeOperator is ModuleCreateNodeOperator, CSMCommon {}

contract CSMAddValidatorKeys is ModuleAddValidatorKeys, CSMCommon {}

contract CSMAddValidatorKeysViaGate is
    ModuleAddValidatorKeysViaGate,
    CSMCommon
{}

contract CSMAddValidatorKeysNegative is
    ModuleAddValidatorKeysNegative,
    CSMCommon
{}

contract CSMObtainDepositData is ModuleObtainDepositData, CSMCommon {}

contract CSMProposeNodeOperatorManagerAddressChange is
    ModuleProposeNodeOperatorManagerAddressChange,
    CSMCommon
{}

contract CSMConfirmNodeOperatorManagerAddressChange is
    ModuleConfirmNodeOperatorManagerAddressChange,
    CSMCommon
{}

contract CSMProposeNodeOperatorRewardAddressChange is
    ModuleProposeNodeOperatorRewardAddressChange,
    CSMCommon
{}

contract CSMConfirmNodeOperatorRewardAddressChange is
    ModuleConfirmNodeOperatorRewardAddressChange,
    CSMCommon
{}

contract CSMResetNodeOperatorManagerAddress is
    ModuleResetNodeOperatorManagerAddress,
    CSMCommon
{}

contract CSMChangeNodeOperatorRewardAddress is
    ModuleChangeNodeOperatorRewardAddress,
    CSMCommon
{}

contract CSMVetKeys is ModuleVetKeys, CSMCommon {}

abstract contract CSMQueueOps is CSMCommon {
    uint256 internal constant LOOKUP_DEPTH = 150; // derived from maxDepositsPerBlock

    function test_emptyQueueIsClean() public assertInvariants {
        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_queueIsDirty_WhenHasBatchOfNonDepositableOperator()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator({ keysCount: 2 });
        unvetKeys({ noId: noId, to: 0 }); // One of the ways to set `depositableValidatorsCount` to 0.

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertTrue(isDirty, "queue should be dirty");
    }

    function test_queueIsDirty_WhenHasBatchWithNoDepositableKeys()
        public
        assertInvariants
    {
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

        (uint256 toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 1, "should remove 1 batch");

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_cleanup_emptyQueue() public assertInvariants {
        _assertQueueIsEmpty();

        (uint256 toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_zeroMaxItems() public assertInvariants {
        (uint256 removed, uint256 lastRemovedAtDepth) = getModule()
            .cleanDepositQueue(0);
        assertEq(removed, 0, "should not remove any batches");
        assertEq(lastRemovedAtDepth, 0, "lastRemovedAtDepth should be 0");
    }

    function test_cleanup_WhenMultipleInvalidBatchesInRow()
        public
        assertInvariants
    {
        createNodeOperator({ keysCount: 3 });
        createNodeOperator({ keysCount: 5 });
        createNodeOperator({ keysCount: 1 });

        uploadMoreKeys(1, 2);

        unvetKeys({ noId: 1, to: 2 });
        unvetKeys({ noId: 2, to: 0 });

        uint256 toRemove;

        // Operator noId=1 has 1 dangling batch after unvetting.
        // Operator noId=2 is unvetted.
        (toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 2, "should remove 2 batch");

        // let's check the state of the queue
        BatchInfo[] memory exp = new BatchInfo[](2);
        exp[0] = BatchInfo({ nodeOperatorId: 0, count: 3 });
        exp[1] = BatchInfo({ nodeOperatorId: 1, count: 5 });
        _assertQueueState(getModule().QUEUE_LOWEST_PRIORITY(), exp);

        (toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_WhenAllBatchesInvalid() public assertInvariants {
        createNodeOperator({ keysCount: 2 });
        createNodeOperator({ keysCount: 2 });
        unvetKeys({ noId: 0, to: 0 });
        unvetKeys({ noId: 1, to: 0 });

        (uint256 toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
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
            (uint256 toRemove, uint256 toVisit) = getModule()
                .cleanDepositQueue({ maxItems: 10 });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }

        vm.revertToState(snapshot);

        {
            (uint256 toRemove, uint256 toVisit) = getModule()
                .cleanDepositQueue({ maxItems: 6 });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }
    }

    function test_updateDepositableValidatorsCount_NothingToDo()
        public
        assertInvariants
    {
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

    function test_updateDepositableValidatorsCount_NonExistingOperator()
        public
        assertInvariants
    {
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

    function test_queueNormalized_WhenSkippedKeysAndTargetValidatorsLimitRaised()
        public
    {
        uint256 noId = createNodeOperator(7);
        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });
        getModule().cleanDepositQueue(1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(
            getModule().QUEUE_LOWEST_PRIORITY(),
            noId,
            7
        );

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 7
        });
    }

    function test_queueNormalized_WhenWithdrawalChangesDepositable()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 2
        });
        module.obtainDepositData(2, "");
        getModule().cleanDepositQueue(1);

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(
            getModule().QUEUE_LOWEST_PRIORITY(),
            noId,
            1
        );
        module.reportWithdrawnValidators(validatorInfos);
    }
}

abstract contract CSMPriorityQueue is CSMCommon {
    uint256 constant LOOKUP_DEPTH = 150;

    uint32 constant MAX_DEPOSITS = 10;

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

    function test_enqueueToPriorityQueue_AlreadyEnqueuedLessThanMaxDeposits()
        public
    {
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

    function test_enqueueToPriorityQueue_AlreadyEnqueuedMoreThanMaxDeposits()
        public
    {
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

    function test_enqueueToPriorityQueue_EnqueuedWithDepositedLessThanMaxDeposits()
        public
    {
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

    function test_enqueueToPriorityQueue_EnqueuedWithDepositedMoreThanMaxDeposits()
        public
    {
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

        (uint256 toRemove, ) = getModule().cleanDepositQueue(LOOKUP_DEPTH);
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
            (uint256 toRemove, uint256 lastRemovedAtDepth) = getModule()
                .cleanDepositQueue(3);
            vm.revertToState(snapshot);
            assertEq(toRemove, 0, "should remove 0 batch(es)");
            assertEq(lastRemovedAtDepth, 0, "the depth should be 0");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = getModule()
                .cleanDepositQueue(4);
            vm.revertToState(snapshot);
            assertEq(toRemove, 1, "should remove 1 batch(es)");
            assertEq(lastRemovedAtDepth, 4, "the depth should be 4");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = getModule()
                .cleanDepositQueue(7);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = getModule()
                .cleanDepositQueue(100_500);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }
    }

    function _enablePriorityQueue(
        uint32 priority,
        uint32 maxDeposits
    ) internal {
        parametersRegistry.setQueueConfig({
            curveId: 0,
            priority: priority,
            maxDeposits: maxDeposits
        });
    }

    function _assertQueueIsEmptyByPriority(uint32 priority) internal view {
        _assertQueueState(priority, new BatchInfo[](0));
    }
}

contract CSMDecreaseVettedSigningKeysCount is
    ModuleDecreaseVettedSigningKeysCount,
    CSMCommon
{}

contract CSMGetSigningKeys is ModuleGetSigningKeys, CSMCommon {}

contract CSMGetSigningKeysWithSignatures is
    ModuleGetSigningKeysWithSignatures,
    CSMCommon
{}

contract CSMRemoveKeys is ModuleRemoveKeys, CSMCommon {}

contract CSMRemoveKeysChargeFee is ModuleRemoveKeysChargeFee, CSMCommon {}

contract CSMRemoveKeysReverts is ModuleRemoveKeysReverts, CSMCommon {}

contract CSMGetNodeOperatorNonWithdrawnKeys is
    ModuleGetNodeOperatorNonWithdrawnKeys,
    CSMCommon
{}

contract CSMGetNodeOperatorSummary is ModuleGetNodeOperatorSummary, CSMCommon {}

contract CSMGetNodeOperator is ModuleGetNodeOperator, CSMCommon {}

contract CSMUpdateTargetValidatorsLimits is
    ModuleUpdateTargetValidatorsLimits,
    CSMCommon
{}

contract CSMUpdateExitedValidatorsCount is
    ModuleUpdateExitedValidatorsCount,
    CSMCommon
{}

contract CSMUnsafeUpdateValidatorsCount is
    ModuleUnsafeUpdateValidatorsCount,
    CSMCommon
{}

contract CSMReportGeneralDelayedPenalty is
    ModuleReportGeneralDelayedPenalty,
    CSMCommon
{}

contract CSMCancelGeneralDelayedPenalty is
    ModuleCancelGeneralDelayedPenalty,
    CSMCommon
{}

contract CSMSettleGeneralDelayedPenaltyBasic is
    ModuleSettleGeneralDelayedPenaltyBasic,
    CSMCommon
{}

contract CSMSettleGeneralDelayedPenaltyAdvanced is
    ModuleSettleGeneralDelayedPenaltyAdvanced,
    CSMCommon
{}

contract CSMCompensateGeneralDelayedPenalty is
    ModuleCompensateGeneralDelayedPenalty,
    CSMCommon
{}

contract CSMReportWithdrawnValidators is
    ModuleReportWithdrawnValidators,
    CSMCommon
{}

contract CSMGetStakingModuleSummary is
    ModuleGetStakingModuleSummary,
    CSMCommon
{}

contract CSMAccessControl is ModuleAccessControl, CSMCommonNoRoles {}

contract CSMStakingRouterAccessControl is
    ModuleStakingRouterAccessControl,
    CSMCommonNoRoles
{}

contract CSMDepositableValidatorsCount is
    ModuleDepositableValidatorsCount,
    CSMCommon
{}

contract CSMNodeOperatorStateAfterUpdateCurve is
    ModuleNodeOperatorStateAfterUpdateCurve,
    CSMCommon
{}

contract CSMOnRewardsMinted is ModuleOnRewardsMinted, CSMCommon {}

contract CSMRecoverERC20 is ModuleRecoverERC20, CSMCommon {}

contract CSMSupportsInterface is ModuleSupportsInterface, CSMCommon {}

contract CSMMisc is ModuleMisc, CSMCommon {}

contract CSMExitDeadlineThreshold is ModuleExitDeadlineThreshold, CSMCommon {}

contract CSMIsValidatorExitDelayPenaltyApplicable is
    ModuleIsValidatorExitDelayPenaltyApplicable,
    CSMCommon
{}

contract CSMReportValidatorExitDelay is
    ModuleReportValidatorExitDelay,
    CSMCommon
{}

contract CSMOnValidatorExitTriggered is
    ModuleOnValidatorExitTriggered,
    CSMCommon
{}

contract CSMCreateNodeOperators is ModuleCreateNodeOperators, CSMCommon {}
