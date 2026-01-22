// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CommonBase } from "forge-std/Base.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { CSModule } from "src/CSModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IDepositQueueLib } from "src/lib/DepositQueueLib.sol";
import { ITopUpQueueLib } from "src/lib/TopUpQueueLib.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";

import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { AccountingMock } from "../helpers/mocks/AccountingMock.sol";
import { Stub } from "../helpers/mocks/Stub.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./ModuleAbstract.t.sol";

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
        csm = CSModule(address(module));

        accounting.setModule(module);

        _enableInitializers(address(module));
        csm.initialize({ admin: admin, topUpQueueLimit: topUpQueueLimit });

        vm.startPrank(admin);
        {
            module.grantRole(module.RESUME_ROLE(), address(admin));
            module.resume();
            module.revokeRole(module.RESUME_ROLE(), address(admin));
        }
        vm.stopPrank();

        _setupRolesForTests();

        // Just to make sure we configured defaults properly and check things properly.
        assertNotEq(PRIORITY_QUEUE, csm.QUEUE_LOWEST_PRIORITY());
        REGULAR_QUEUE = uint32(csm.QUEUE_LOWEST_PRIORITY());
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
        module.grantRole(
            module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(),
            address(this)
        );
        module.grantRole(
            module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(),
            address(this)
        );
        vm.stopPrank();
    }

    function _moduleInvariants() internal override {
        assertModuleEnqueuedCount(csm);
        assertModuleKeys(module);
        assertModuleUnusedStorageSlots(module);
    }

    // Checks that the queue is in the expected state starting from its head.
    function _assertQueueState(
        uint256 priority,
        BatchInfo[] memory exp
    ) internal view {
        (uint128 curr, ) = csm.depositQueuePointers(priority); // queue.head

        for (uint256 i = 0; i < exp.length; ++i) {
            BatchInfo memory b = exp[i];
            Batch item = csm.depositQueueItem(priority, curr);

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
            csm.depositQueueItem(priority, curr).isNil(),
            string.concat(
                "unexpected tail of queue with priority=",
                priority.toString()
            )
        );
    }

    function _assertQueueIsEmpty() internal view {
        for (uint256 p = 0; p <= csm.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = csm.depositQueuePointers(p); // queue.head
            assertTrue(
                csm.depositQueueItem(p, curr).isNil(),
                string.concat(
                    "queue with priority=",
                    p.toString(),
                    " is not empty"
                )
            );
        }
    }

    function _printQueue() internal view {
        for (uint256 p = 0; p <= csm.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = csm.depositQueuePointers(p);

            for (;;) {
                Batch item = csm.depositQueueItem(p, curr);
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

        if (limit > length) {
            return limit - length;
        }
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
        csm.obtainDepositData({
            maxDepositAmount: 0,
            packedPubkeys: csm.getSigningKeys(0, 0, 1),
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
        csm.obtainDepositData(0, hex"", UintArr(), UintArr(), UintArr());
    }

    function test_topUp_nonceDoesNotChangeWhenNoKeysProvided() public {
        uint256 nonceBefore = csm.getNonce();
        csm.obtainDepositData(0, hex"", UintArr(), UintArr(), UintArr());
        assertEq(csm.getNonce(), nonceBefore);
    }

    function test_topUp_DepositAmountBelowTopUpLimit() public {
        createNodeOperator(3);
        csm.obtainDepositData(3, "");

        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        (bytes[] memory keys, uint256[] memory allocations) = csm
            .obtainDepositData({
                maxDepositAmount: 5,
                packedPubkeys: packedPubkeys,
                keyIndices: UintArr(0, 1),
                operatorIds: UintArr(0, 0),
                topUpLimits: UintArr(3, 3)
            });

        assertEq(_getTopUpQueueLength(), 2);
        assertEq(allocations, UintArr(3, 2));
        assertEq(keys[0], slice(packedPubkeys, 0 * 48, 48));
        assertEq(keys[1], slice(packedPubkeys, 1 * 48, 48));

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
        (bytes[] memory keys, uint256[] memory allocations) = csm
            .obtainDepositData({
                maxDepositAmount: 4,
                packedPubkeys: packedPubkeys,
                keyIndices: UintArr(0, 1),
                operatorIds: UintArr(0, 0),
                topUpLimits: UintArr(2, 1)
            });

        assertEq(_getTopUpQueueLength(), 1);
        assertEq(allocations, UintArr(2, 1));
        assertEq(keys[0], slice(packedPubkeys, 0 * 48, 48));
        assertEq(keys[1], slice(packedPubkeys, 1 * 48, 48));

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
        (bytes[] memory keys, uint256[] memory allocations) = csm
            .obtainDepositData({
                maxDepositAmount: 2,
                packedPubkeys: packedPubkeys,
                keyIndices: UintArr(0, 1),
                operatorIds: UintArr(0, 0),
                topUpLimits: UintArr(1, 1)
            });

        assertEq(allocations, UintArr(1, 1));
        assertEq(keys[0], slice(packedPubkeys, 0 * 48, 48));
        assertEq(keys[1], slice(packedPubkeys, 1 * 48, 48));

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
        (bytes[] memory keys, uint256[] memory allocations) = csm
            .obtainDepositData({
                maxDepositAmount: 1,
                packedPubkeys: packedPubkeys,
                keyIndices: UintArr(0, 1),
                operatorIds: UintArr(0, 0),
                topUpLimits: UintArr(1, 0)
            });

        assertEq(allocations, UintArr(1, 0));
        assertEq(keys[0], slice(packedPubkeys, 0 * 48, 48));
        assertEq(keys[1], slice(packedPubkeys, 1 * 48, 48));

        assertEq(_getTopUpQueueLength(), 0);
    }

    function test_topUp_nonceIncrementsWhenKeysProvided() public {
        createNodeOperator(1);
        csm.obtainDepositData(1, "");

        uint256 nonceBefore = csm.getNonce();

        bytes memory keys = csm.getSigningKeys(0, 0, 1);
        csm.obtainDepositData({
            maxDepositAmount: 0,
            packedPubkeys: keys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(0)
        });

        assertEq(csm.getNonce(), nonceBefore + 1);
    }

    function test_topUp_RevertWhenTheSameKeyTwiceAboveDepositAmount() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory packedPubkeys = bytes.concat(
            csm.getSigningKeys(0, 0, 1),
            csm.getSigningKeys(0, 0, 1)
        );
        vm.expectRevert(ICSModule.UnexpectedExtraKey.selector);
        csm.obtainDepositData({
            maxDepositAmount: 3,
            packedPubkeys: packedPubkeys,
            keyIndices: UintArr(0, 0),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(4, 4)
        });
    }

    function test_topUp_RevertWhenNextItemDoesNotMatch() public {
        createNodeOperator(2);
        csm.obtainDepositData(2, "");

        bytes memory keys = bytes.concat(
            csm.getSigningKeys(0, 1, 1),
            csm.getSigningKeys(0, 1, 1)
        );

        // Operator ID mismatch
        vm.expectRevert(ICSModule.InvalidTopUpOrder.selector);
        csm.obtainDepositData({
            maxDepositAmount: 3,
            packedPubkeys: keys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(1),
            topUpLimits: UintArr(4)
        });

        // Operator key index mismatch
        vm.expectRevert(ICSModule.InvalidTopUpOrder.selector);
        csm.obtainDepositData({
            maxDepositAmount: 3,
            packedPubkeys: keys,
            keyIndices: UintArr(1),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4)
        });

        vm.expectRevert(ICSModule.InvalidSigningKey.selector);
        csm.obtainDepositData({
            maxDepositAmount: 3,
            packedPubkeys: keys,
            keyIndices: UintArr(0),
            operatorIds: UintArr(0),
            topUpLimits: UintArr(4)
        });
    }

    function test_topUp_RevertWhenKeysAboveDepositAmount() public {
        createNodeOperator(3);
        csm.obtainDepositData(3, "");

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 3);
        vm.expectRevert(ICSModule.UnexpectedExtraKey.selector);
        csm.obtainDepositData({
            maxDepositAmount: 1,
            packedPubkeys: packedPubkeys,
            keyIndices: UintArr(0, 1, 2),
            operatorIds: UintArr(0, 0, 0),
            topUpLimits: UintArr(1, 4, 0)
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

        csm.obtainDepositData({
            maxDepositAmount: 3,
            packedPubkeys: bytes.concat(keys[0], keys[1], keys[2]),
            keyIndices: UintArr(0, 1, 0),
            operatorIds: UintArr(0, 0, 1),
            topUpLimits: UintArr(1, 1, 1)
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

    function testFuzz_setTopUpQueueLimit(uint8 limit) public {
        vm.expectEmit(true, true, true, true, address(csm));
        emit ICSModule.TopUpQueueLimitSet(limit);
        csm.setTopUpQueueLimit(limit);
        assertEq(_getTopUpQueueLimit(), limit);
    }

    function test_setTopUpQueueLimit_incrementsNonce() public {
        uint256 nonceBefore = csm.getNonce();
        csm.setTopUpQueueLimit(0);
        assertEq(csm.getNonce(), nonceBefore + 1);
    }

    function testFuzz_setTopUpQueueLimitToZero() public {
        assertGt(_getTopUpQueueLimit(), 0);
        csm.setTopUpQueueLimit(0);
        assertEq(_getTopUpQueueLimit(), 0);
    }

    function test_setTopUpQueueLimit_RevertWhenLimitExceedsUint8() public {
        uint256 limit = uint256(type(uint32).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                8,
                limit
            )
        );
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

        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.setTopUpQueueLimit(0);
    }

    function test_rewindTopUpQueue() public {
        createNodeOperator(2);
        createNodeOperator(1);
        csm.obtainDepositData(3, "");
        assertEq(_getTopUpQueueLength(), 3);

        bytes memory packedPubkeys = csm.getSigningKeys(0, 0, 2);
        csm.obtainDepositData({
            maxDepositAmount: 2,
            packedPubkeys: packedPubkeys,
            keyIndices: UintArr(0, 1),
            operatorIds: UintArr(0, 0),
            topUpLimits: UintArr(1, 1)
        });

        assertEq(_getTopUpQueueLength(), 1);

        uint256 noId;
        uint256 keyIndex;

        (noId, keyIndex) = csm.getTopUpQueueItem(0);
        assertEq(noId, 1);
        assertEq(keyIndex, 0);

        uint256 to = 1;
        vm.expectEmit(true, true, true, true, address(csm));
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
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                32,
                to
            )
        );
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

        vm.expectRevert(ICSModule.TopUpQueueDisabled.selector);
        csm.rewindTopUpQueue(0);
    }
}

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

contract CSMQueueOps is CSMCommon {
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
        (uint256 removed, uint256 lastRemovedAtDepth) = csm.cleanDepositQueue(
            0
        );
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
        (toRemove, ) = csm.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 2, "should remove 2 batch");

        // let's check the state of the queue
        BatchInfo[] memory exp = new BatchInfo[](2);
        exp[0] = BatchInfo({ nodeOperatorId: 0, count: 3 });
        exp[1] = BatchInfo({ nodeOperatorId: 1, count: 5 });
        _assertQueueState(csm.QUEUE_LOWEST_PRIORITY(), exp);

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
            (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({
                maxItems: 10
            });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }

        vm.revertToState(snapshot);

        {
            (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({
                maxItems: 6
            });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }
    }

    function test_clean_MaxItemsIsZero() public {
        createNodeOperator({ keysCount: 1 });

        (uint256 toRemove, uint256 toVisit) = csm.cleanDepositQueue({
            maxItems: 0
        });
        assertEq(toRemove, 0, "toRemove != 0");
        assertEq(toVisit, 0, "toVisit != 0");
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
        csm.cleanDepositQueue(1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(csm.QUEUE_LOWEST_PRIORITY(), noId, 7);

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
        csm.cleanDepositQueue(1);

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
        emit ICSModule.BatchEnqueued(csm.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }
}

contract CSMPriorityQueue is CSMCommon {
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
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm
                .cleanDepositQueue(3);
            vm.revertToState(snapshot);
            assertEq(toRemove, 0, "should remove 0 batch(es)");
            assertEq(lastRemovedAtDepth, 0, "the depth should be 0");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm
                .cleanDepositQueue(4);
            vm.revertToState(snapshot);
            assertEq(toRemove, 1, "should remove 1 batch(es)");
            assertEq(lastRemovedAtDepth, 4, "the depth should be 4");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm
                .cleanDepositQueue(7);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = csm
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

contract CSMStakingRouterAccessControl is
    ModuleStakingRouterAccessControl,
    CSMCommonNoRoles
{
    function setUp() public override {
        topUpQueueLimit = 32;

        super.setUp();
    }

    function test_stakingRouterRole_topUps() public {
        bytes32 role = csm.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        csm.grantRole(role, actor);

        vm.prank(actor);
        csm.obtainDepositData(0, hex"", UintArr(), UintArr(), UintArr());
    }

    function test_stakingRouterRole_topUps_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        csm.obtainDepositData(0, hex"", UintArr(), UintArr(), UintArr());
    }
}

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

contract CSMMisc is ModuleMisc, CSMCommon {
    function test_getInitializedVersion() public view override {
        assertEq(module.getInitializedVersion(), 3);
    }
}

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
