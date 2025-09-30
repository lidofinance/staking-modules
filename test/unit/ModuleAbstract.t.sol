// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { InvariantAsserts } from "../helpers/InvariantAsserts.sol";
import { ICSModule, NodeOperator, NodeOperatorManagementProperties, ValidatorWithdrawalInfo } from "src/interfaces/ICSModule.sol";
import { CSAccountingMock } from "../helpers/mocks/CSAccountingMock.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { CSParametersRegistryMock } from "../helpers/mocks/CSParametersRegistryMock.sol";
import { LidoLocatorMock } from "../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../helpers/mocks/LidoMock.sol";
import { WstETHMock } from "../helpers/mocks/WstETHMock.sol";
import { CSModule } from "src/CSModule.sol";
import { Stub } from "../helpers/mocks/Stub.sol";
import { Batch } from "src/lib/QueueLib.sol";
import { ERC20Testable } from "../helpers/ERCTestable.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { ICSAccounting } from "src/interfaces/ICSAccounting.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { INOAddresses } from "src/lib/NOAddresses.sol";
import { CSBondLock } from "src/abstract/CSBondLock.sol";
import { ICSExitPenalties, ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/ICSExitPenalties.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";

abstract contract ModuleFixtures is
    Test,
    Fixtures,
    Utilities,
    InvariantAsserts
{
    using Strings for uint256;
    using Strings for uint128;

    struct BatchInfo {
        uint256 nodeOperatorId;
        uint256 count;
    }

    uint256 public constant BOND_SIZE = 2 ether;

    LidoLocatorMock public locator;
    WstETHMock public wstETH;
    LidoMock public stETH;
    CSModule public module;
    CSAccountingMock public accounting;
    Stub public feeDistributor;
    CSParametersRegistryMock public parametersRegistry;
    ExitPenaltiesMock public exitPenalties;

    address internal actor;
    address internal admin;
    address internal stranger;
    address internal strangerNumberTwo;
    address internal nodeOperator;
    address internal testChargePenaltyRecipient;
    address internal stakingRouter;

    uint32 internal REGULAR_QUEUE;
    uint32 internal LEGACY_QUEUE;
    uint32 constant PRIORITY_QUEUE = 0;

    struct NodeOperatorSummary {
        uint256 targetLimitMode;
        uint256 targetValidatorsCount;
        uint256 stuckValidatorsCount;
        uint256 refundedValidatorsCount;
        uint256 stuckPenaltyEndTimestamp;
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    struct StakingModuleSummary {
        uint256 totalExitedValidators;
        uint256 totalDepositedValidators;
        uint256 depositableValidatorsCount;
    }

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        assertModuleEnqueuedCount(module);
        assertModuleKeys(module);
        assertModuleUnusedStorageSlots(module);
        vm.resumeGasMetering();
    }

    function createNodeOperator() internal returns (uint256) {
        return createNodeOperator(nodeOperator, 1);
    }

    function createNodeOperator(uint256 keysCount) internal returns (uint256) {
        return createNodeOperator(nodeOperator, keysCount);
    }

    function createNodeOperator(
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        return createNodeOperator(nodeOperator, extendedManagerPermissions);
    }

    function createNodeOperator(
        address managerAddress,
        uint256 keysCount
    ) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        if (keysCount > 0) {
            uploadMoreKeys(nodeOperatorId, keysCount);
        }
    }

    function createNodeOperator(
        address managerAddress,
        uint256 keysCount,
        bytes memory keys,
        bytes memory signatures
    ) internal returns (uint256 nodeOperatorId) {
        nodeOperatorId = createNodeOperator(managerAddress, false);
        uploadMoreKeys(nodeOperatorId, keysCount, keys, signatures);
    }

    function createNodeOperator(
        address managerAddress,
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        vm.prank(module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0));
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function createNodeOperator(
        address managerAddress,
        address rewardAddress,
        bool extendedManagerPermissions
    ) internal returns (uint256) {
        vm.prank(module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0));
        return
            module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: managerAddress,
                    rewardAddress: rewardAddress,
                    extendedManagerPermissions: extendedManagerPermissions
                }),
                address(0)
            );
    }

    function uploadMoreKeys(
        uint256 noId,
        uint256 keysCount,
        bytes memory keys,
        bytes memory signatures
    ) internal {
        uint256 amount = accounting.getRequiredBondForNextKeys(noId, keysCount);
        address managerAddress = module.getNodeOperator(noId).managerAddress;
        vm.deal(managerAddress, amount);
        vm.prank(managerAddress);
        module.addValidatorKeysETH{ value: amount }(
            managerAddress,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function uploadMoreKeys(uint256 noId, uint256 keysCount) internal {
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uploadMoreKeys(noId, keysCount, keys, signatures);
    }

    function unvetKeys(uint256 noId, uint256 to) internal {
        module.decreaseVettedSigningKeysCount(
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(to)))
        );
    }

    function setExited(uint256 noId, uint256 to) internal {
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(uint64(noId))),
            bytes.concat(bytes16(uint128(to)))
        );
    }

    function withdrawKey(uint256 noId, uint256 /* keyIndex */) internal {
        ValidatorWithdrawalInfo[]
            memory withdrawalsInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalsInfo[0] = ValidatorWithdrawalInfo(
            noId,
            0,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );
        module.submitWithdrawals(withdrawalsInfo);
    }

    // Checks that the queue is in the expected state starting from its head.
    function _assertQueueState(
        uint256 priority,
        BatchInfo[] memory exp
    ) internal view {
        (uint128 curr, ) = module.depositQueuePointers(priority); // queue.head

        for (uint256 i = 0; i < exp.length; ++i) {
            BatchInfo memory b = exp[i];
            Batch item = module.depositQueueItem(priority, curr);

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
            module.depositQueueItem(priority, curr).isNil(),
            string.concat(
                "unexpected tail of queue with priority=",
                priority.toString()
            )
        );
    }

    function _assertQueueIsEmpty() internal view {
        for (uint256 p = 0; p <= module.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = module.depositQueuePointers(p); // queue.head
            assertTrue(
                module.depositQueueItem(p, curr).isNil(),
                string.concat(
                    "queue with priority=",
                    p.toString(),
                    " is not empty"
                )
            );
        }
    }

    function _printQueue() internal view {
        for (uint256 p = 0; p <= module.QUEUE_LOWEST_PRIORITY(); ++p) {
            (uint128 curr, ) = module.depositQueuePointers(p);

            for (;;) {
                Batch item = module.depositQueueItem(p, curr);
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
        (uint256 toRemove, ) = module.cleanDepositQueue(maxItems);
        vm.revertToState(snapshot);
        return toRemove > 0;
    }

    function getNodeOperatorSummary(
        uint256 noId
    ) public view returns (NodeOperatorSummary memory) {
        (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getNodeOperatorSummary(noId);
        return
            NodeOperatorSummary({
                targetLimitMode: targetLimitMode,
                targetValidatorsCount: targetValidatorsCount,
                stuckValidatorsCount: stuckValidatorsCount,
                refundedValidatorsCount: refundedValidatorsCount,
                stuckPenaltyEndTimestamp: stuckPenaltyEndTimestamp,
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function getStakingModuleSummary()
        public
        view
        returns (StakingModuleSummary memory)
    {
        (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        return
            StakingModuleSummary({
                totalExitedValidators: totalExitedValidators,
                totalDepositedValidators: totalDepositedValidators,
                depositableValidatorsCount: depositableValidatorsCount
            });
    }

    function penalize(uint256 noId, uint256 amount) public {
        vm.prank(address(module));
        accounting.penalize(noId, amount);
        module.updateDepositableValidatorsCount(noId);
    }
}

abstract contract ModuleFuzz is ModuleFixtures {
    function testFuzz_CreateNodeOperator(
        uint256 keysCount
    ) public assertInvariants {
        keysCount = bound(keysCount, 1, 99);
        createNodeOperator(keysCount);
        assertEq(module.getNodeOperatorsCount(), 1);
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalAddedKeys, keysCount);
    }

    function testFuzz_CreateMultipleNodeOperators(
        uint256 count
    ) public assertInvariants {
        count = bound(count, 1, 100);
        for (uint256 i = 0; i < count; i++) {
            createNodeOperator(1);
        }
        assertEq(module.getNodeOperatorsCount(), count);
    }

    function testFuzz_UploadKeys(uint256 keysCount) public assertInvariants {
        keysCount = bound(keysCount, 1, 99);
        createNodeOperator(1);
        uploadMoreKeys(0, keysCount);
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.totalAddedKeys, keysCount + 1);
    }
}

abstract contract ModulePauseTest is ModuleFixtures {
    function test_notPausedByDefault() public view {
        assertFalse(module.isPaused());
    }

    function test_pauseFor() public {
        module.pauseFor(1 days);
        assertTrue(module.isPaused());
        assertEq(module.getResumeSinceTimestamp(), block.timestamp + 1 days);
    }

    function test_pauseFor_indefinitely() public {
        module.pauseFor(type(uint256).max);
        assertTrue(module.isPaused());
        assertEq(module.getResumeSinceTimestamp(), type(uint256).max);
    }

    function test_pauseFor_RevertWhen_ZeroPauseDuration() public {
        vm.expectRevert(PausableUntil.ZeroPauseDuration.selector);
        module.pauseFor(0);
    }

    function test_resume() public {
        module.pauseFor(1 days);
        module.resume();
        assertFalse(module.isPaused());
    }

    function test_auto_resume() public {
        module.pauseFor(1 days);
        assertTrue(module.isPaused());
        vm.warp(block.timestamp + 1 days + 1 seconds);
        assertFalse(module.isPaused());
    }

    function test_pause_RevertWhen_notAdmin() public {
        expectRoleRevert(stranger, module.PAUSE_ROLE());
        vm.prank(stranger);
        module.pauseFor(1 days);
    }

    function test_resume_RevertWhen_notAdmin() public {
        module.pauseFor(1 days);

        expectRoleRevert(stranger, module.RESUME_ROLE());
        vm.prank(stranger);
        module.resume();
    }
}

abstract contract ModulePauseAffectingTest is ModuleFixtures {
    function test_createNodeOperator_RevertWhen_Paused() public {
        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_addValidatorKeysETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function test_addValidatorKeysStETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_addValidatorKeysWstETH_RevertWhen_Paused() public {
        uint256 noId = createNodeOperator();
        uint16 keysCount = 1;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        module.pauseFor(1 days);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}

abstract contract ModuleCreateNodeOperator is ModuleFixtures {
    function test_createNodeOperator() public assertInvariants {
        uint256 nonce = module.getNonce();
        vm.expectEmit(address(module));
        emit ICSModule.NodeOperatorAdded(0, nodeOperator, nodeOperator, false);

        uint256 nodeOperatorId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
        assertEq(module.getNodeOperatorsCount(), 1);
        assertEq(module.getNonce(), nonce + 1);
        assertEq(nodeOperatorId, 0);
    }

    function test_createNodeOperator_withCustomAddresses()
        public
        assertInvariants
    {
        address manager = address(154);
        address reward = address(42);

        vm.expectEmit(address(module));
        emit ICSModule.NodeOperatorAdded(0, manager, reward, false);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: false
            }),
            address(0)
        );

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, reward);
        assertEq(no.extendedManagerPermissions, false);
    }

    function test_createNodeOperator_withExtendedManagerPermissions()
        public
        assertInvariants
    {
        address manager = address(154);
        address reward = address(42);

        vm.expectEmit(address(module));
        emit ICSModule.NodeOperatorAdded(0, manager, reward, true);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: true
            }),
            address(0)
        );

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, manager);
        assertEq(no.rewardAddress, reward);
        assertEq(no.extendedManagerPermissions, true);
    }

    function test_createNodeOperator_withReferrer() public assertInvariants {
        {
            vm.expectEmit(address(module));
            emit ICSModule.NodeOperatorAdded(
                0,
                nodeOperator,
                nodeOperator,
                false
            );
            vm.expectEmit(address(module));
            emit ICSModule.ReferrerSet(0, address(154));
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

    function test_createNodeOperator_RevertWhen_ZeroSenderAddress() public {
        vm.expectRevert(ICSModule.ZeroSenderAddress.selector);
        module.createNodeOperator(
            address(0),
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_createNodeOperator_multipleInSameTx() public {
        address manager = nextAddress("MANAGER");
        address referrer = nextAddress("REFERRER");
        NodeOperatorManagementProperties
            memory props = NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: address(0),
                extendedManagerPermissions: false
            });
        uint256 nonceBefore = module.getNonce();
        uint256 countBefore = module.getNodeOperatorsCount();

        // Act: create two node operators in the same transaction
        uint256 id1 = module.createNodeOperator(manager, props, referrer);
        uint256 id2 = module.createNodeOperator(manager, props, referrer);

        // Assert: both created, ids are sequential, nonce incremented twice
        assertEq(id1, countBefore);
        assertEq(id2, countBefore + 1);
        assertEq(module.getNodeOperatorsCount(), countBefore + 2);
        assertEq(module.getNonce(), nonceBefore + 2);
        // Check events and referrer
        NodeOperator memory no1 = module.getNodeOperator(id1);
        assertEq(no1.managerAddress, manager);
        NodeOperator memory no2 = module.getNodeOperator(id2);
        assertEq(no2.managerAddress, manager);
    }
}

abstract contract ModuleAddValidatorKeys is ModuleFixtures {
    function test_AddValidatorKeysWstETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(
                module.QUEUE_LOWEST_PRIORITY(),
                noId,
                1
            );
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysWstETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysWstETH_createNodeOperatorRole()
        public
        assertInvariants
        brutalizeMemory
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        vm.prank(stranger);
        uint256 noId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 nonce = module.getNonce();

        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysWstETH_createNodeOperatorRole_MultipleOperators()
        public
        assertInvariants
        brutalizeMemory
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i; i < ids.length; i++) {
            vm.prank(stranger);
            ids[i] = module.createNodeOperator(
                nodeOperator,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        shuffle(ids);

        for (uint256 i; i < ids.length; i++) {
            uint256 toWrap = BOND_SIZE + 2 wei;
            vm.deal(nodeOperator, toWrap);
            vm.startPrank(nodeOperator);
            stETH.submit{ value: toWrap }(address(0));
            stETH.approve(address(wstETH), UINT256_MAX);
            wstETH.wrap(toWrap);
            vm.stopPrank();
            (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
            uint256 nonce = module.getNonce();

            vm.prank(stranger);
            module.addValidatorKeysWstETH(
                nodeOperator,
                ids[i],
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
            assertEq(module.getNonce(), nonce + 1);
        }
    }

    function test_AddValidatorKeysWstETH_withPermit()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(toWrap);
        uint256 nonce = module.getNonce();
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: wstETHAmount,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(
                module.QUEUE_LOWEST_PRIORITY(),
                noId,
                1
            );
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysStETH_createNodeOperatorRole()
        public
        assertInvariants
        brutalizeMemory
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        vm.prank(stranger);
        uint256 noId = module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        uint256 nonce = module.getNonce();

        vm.prank(stranger);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysStETH_createNodeOperatorRole_MultipleOperators()
        public
        assertInvariants
        brutalizeMemory
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i; i < ids.length; i++) {
            vm.prank(stranger);
            ids[i] = module.createNodeOperator(
                nodeOperator,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        shuffle(ids);

        for (uint256 i; i < ids.length; i++) {
            (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
            vm.deal(nodeOperator, BOND_SIZE + 1 wei);
            vm.prank(nodeOperator);
            stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
            uint256 nonce = module.getNonce();

            vm.prank(stranger);
            module.addValidatorKeysStETH(
                nodeOperator,
                ids[i],
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: BOND_SIZE,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
            assertEq(module.getNonce(), nonce + 1);
        }
    }

    function test_AddValidatorKeysStETH_withPermit()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        vm.prank(nodeOperator);
        stETH.submit{ value: required }(address(0));
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: required,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(
                module.QUEUE_LOWEST_PRIORITY(),
                noId,
                1
            );
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH_keysLimit_withdrawnKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        parametersRegistry.setKeysLimit(0, 1);

        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        withdrawKey(noId, 0);

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysETH_withTargetLimitSet()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();

        module.updateTargetValidatorsLimits({
            nodeOperatorId: noId,
            targetLimitMode: 1,
            targetLimit: 0
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_AddValidatorKeysETH_createNodeOperatorRole_MultipleOperators()
        public
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i; i < ids.length; i++) {
            vm.prank(stranger);
            ids[i] = module.createNodeOperator(
                stranger,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: false
                }),
                address(0)
            );
        }
        shuffle(ids);

        for (uint256 i; i < ids.length; i++) {
            (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
            uint256 required = accounting.getRequiredBondForNextKeys(ids[i], 1);
            vm.deal(stranger, required);
            uint256 nonce = module.getNonce();

            vm.prank(stranger);
            module.addValidatorKeysETH{ value: required }(
                nodeOperator,
                ids[i],
                1,
                keys,
                signatures
            );
            assertEq(module.getNonce(), nonce + 1);
        }
    }

    function test_AddValidatorKeysETH_withMoreEthThanRequired()
        public
        assertInvariants
        brutalizeMemory
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        uint256 deposit = required + 1 ether;
        vm.deal(nodeOperator, deposit);
        uint256 nonce = module.getNonce();

        vm.prank(nodeOperator);
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyAdded(noId, keys);
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.addValidatorKeysETH{ value: deposit }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_AddValidatorKeysETH_RevertWhenCalledFromAnotherExtension()
        public
        assertInvariants
    {
        address extensionOne = nextAddress("EXTENSION_ONE");
        address extensionTwo = nextAddress("EXTENSION_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionTwo);

        vm.prank(extensionOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        vm.deal(extensionTwo, required);

        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(extensionTwo);
            module.addValidatorKeysETH{ value: required }(
                nodeOperator,
                noId,
                1,
                keys,
                signatures
            );
        }
    }

    function test_AddValidatorKeysStETH_RevertWhenCalledFromAnotherExtension()
        public
        assertInvariants
    {
        address extensionOne = nextAddress("EXTENSION_ONE");
        address extensionTwo = nextAddress("EXTENSION_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionTwo);

        vm.prank(extensionOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(extensionTwo);
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_AddValidatorKeysWstETH_RevertWhenCalledFromAnotherExtension()
        public
        assertInvariants
    {
        address extensionOne = nextAddress("EXTENSION_ONE");
        address extensionTwo = nextAddress("EXTENSION_TWO");

        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionOne);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), extensionTwo);

        vm.prank(extensionOne);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(extensionTwo);
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_AddValidatorKeysETH_RevertWhenCalledTwice()
        public
        assertInvariants
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        vm.prank(stranger);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        vm.deal(stranger, required);

        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );

        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(stranger);
            module.addValidatorKeysETH(nodeOperator, noId, 1, keys, signatures);
        }
    }

    function test_AddValidatorKeysStETH_RevertWhenCalledTwice()
        public
        assertInvariants
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        vm.prank(stranger);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        uint256 toWrap = required + 1 wei;
        vm.deal(stranger, toWrap);

        vm.prank(stranger);
        stETH.submit{ value: toWrap }(address(0));

        vm.prank(stranger);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );

        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(stranger);
            module.addValidatorKeysStETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }

    function test_AddValidatorKeysWstETH_RevertWhenCalledTwice()
        public
        assertInvariants
    {
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);

        vm.prank(stranger);
        uint256 noId = module.createNodeOperator({
            from: nodeOperator,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: nodeOperator,
                rewardAddress: nodeOperator,
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);
        uint256 required = accounting.getRequiredBondForNextKeys(noId, 1);
        uint256 toWrap = required + 1 wei;
        vm.deal(stranger, toWrap);

        vm.startPrank(stranger);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();

        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );

        {
            vm.expectRevert(ICSModule.CannotAddKeys.selector);

            vm.prank(stranger);
            module.addValidatorKeysWstETH(
                nodeOperator,
                noId,
                1,
                keys,
                signatures,
                ICSAccounting.PermitInput({
                    value: 0,
                    deadline: 0,
                    v: 0,
                    r: 0,
                    s: 0
                })
            );
        }
    }
}

abstract contract ModuleAddValidatorKeysNegative is ModuleFixtures {
    function beforeTestSetup(
        bytes4 /* testSelector */
    ) public pure returns (bytes[] memory beforeTestCalldata) {
        beforeTestCalldata = new bytes[](1);
        beforeTestCalldata[0] = abi.encodePacked(this.beforeEach.selector);
    }

    function beforeEach() external {
        createNodeOperator();
    }

    function test_AddValidatorKeysETH_RevertWhen_SenderIsNotEligible() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.expectRevert(ICSModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(stranger, required);
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(ICSModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 required = accounting.getRequiredBondForNextKeys(0, 0);
        vm.deal(nodeOperator, required);
        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0)
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(ICSModule.KeysLimitExceeded.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_SenderIsNotEligible()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(ICSModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.prank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(ICSModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysETH_RevertWhen_InvalidAmount()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        uint256 required = accounting.getRequiredBondForNextKeys(0, 1);
        vm.deal(nodeOperator, required - 1 ether);

        vm.expectRevert(ICSModule.InvalidAmount.selector);
        vm.prank(nodeOperator);
        module.addValidatorKeysETH{ value: required - 1 ether }(
            nodeOperator,
            noId,
            1,
            keys,
            signatures
        );
    }

    function test_AddValidatorKeysStETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        vm.deal(nodeOperator, BOND_SIZE + 1 wei);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: BOND_SIZE + 1 wei }(address(0));

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(ICSModule.KeysLimitExceeded.selector);
        module.addValidatorKeysStETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: BOND_SIZE,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_SenderIsNotEligible()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();

        vm.expectRevert(ICSModule.SenderIsNotEligible.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            stranger,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_CannotAddKeys() public {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        vm.stopPrank();
        vm.startPrank(admin);
        module.grantRole(module.CREATE_NODE_OPERATOR_ROLE(), stranger);
        vm.stopPrank();

        vm.expectRevert(ICSModule.CannotAddKeys.selector);
        vm.prank(stranger);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_NoKeys()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            0,
            new bytes(0),
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysAndSigsLengthMismatch()
        public
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, ) = keysSignatures(keysCount);

        vm.expectRevert(SigningKeys.InvalidLength.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            new bytes(0),
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_ZeroKey()
        public
        assertInvariants
    {
        uint256 noId = module.getNodeOperatorsCount() - 1;
        uint16 keysCount = 1;
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (
            bytes memory keys,
            bytes memory signatures
        ) = keysSignaturesWithZeroKey(keysCount, 0);

        vm.expectRevert(SigningKeys.EmptyKey.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            keysCount,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }

    function test_AddValidatorKeysWstETH_RevertWhen_KeysLimitExceeded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 toWrap = BOND_SIZE + 1 wei;
        vm.deal(nodeOperator, toWrap);
        vm.startPrank(nodeOperator);
        stETH.submit{ value: toWrap }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        wstETH.wrap(toWrap);
        (bytes memory keys, bytes memory signatures) = keysSignatures(1, 1);

        parametersRegistry.setKeysLimit(0, 1);

        vm.expectRevert(ICSModule.KeysLimitExceeded.selector);
        module.addValidatorKeysWstETH(
            nodeOperator,
            noId,
            1,
            keys,
            signatures,
            ICSAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}

abstract contract ModuleObtainDepositData is ModuleFixtures {
    // TODO: test with near to real values

    function test_obtainDepositData() public assertInvariants {
        uint256 nodeOperatorId = createNodeOperator(1);
        (bytes memory keys, bytes memory signatures) = module
            .getSigningKeysWithSignatures(nodeOperatorId, 0, 1);

        vm.expectEmit(address(module));
        emit ICSModule.DepositableSigningKeysCountChanged(nodeOperatorId, 0);
        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .obtainDepositData(1, "");
        assertEq(obtainedKeys, keys);
        assertEq(obtainedSignatures, signatures);
    }

    function test_obtainDepositData_MultipleOperators()
        public
        assertInvariants
    {
        uint256 firstId = createNodeOperator(2);
        uint256 secondId = createNodeOperator(3);
        uint256 thirdId = createNodeOperator(1);

        vm.expectEmit(address(module));
        emit ICSModule.DepositableSigningKeysCountChanged(firstId, 0);
        vm.expectEmit(address(module));
        emit ICSModule.DepositableSigningKeysCountChanged(secondId, 0);
        vm.expectEmit(address(module));
        emit ICSModule.DepositableSigningKeysCountChanged(thirdId, 0);
        module.obtainDepositData(6, "");
    }

    function test_obtainDepositData_counters() public assertInvariants {
        uint256 keysCount = 1;
        uint256 noId = createNodeOperator(keysCount);
        (bytes memory keys, bytes memory signatures) = module
            .getSigningKeysWithSignatures(noId, 0, keysCount);

        vm.expectEmit(address(module));
        emit ICSModule.DepositedSigningKeysCountChanged(noId, keysCount);
        (bytes memory depositedKeys, bytes memory depositedSignatures) = module
            .obtainDepositData(keysCount, "");

        assertEq(keys, depositedKeys);
        assertEq(signatures, depositedSignatures);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 0);
        assertEq(no.totalDepositedKeys, 1);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_obtainDepositData_zeroDeposits() public assertInvariants {
        uint256 noId = createNodeOperator();

        (bytes memory publicKeys, bytes memory signatures) = module
            .obtainDepositData(0, "");

        assertEq(publicKeys.length, 0);
        assertEq(signatures.length, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 1);
        assertEq(no.totalDepositedKeys, 0);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_obtainDepositData_unvettedKeys() public assertInvariants {
        createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(1);
        createNodeOperator(3);

        unvetKeys(secondNoId, 0);

        module.obtainDepositData(5, "");

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, 5);
        assertEq(depositableValidatorsCount, 0);
    }

    function test_obtainDepositData_counters_WhenLessThanLastBatch()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);

        vm.expectEmit(address(module));
        emit ICSModule.DepositedSigningKeysCountChanged(noId, 3);
        module.obtainDepositData(3, "");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.enqueuedCount, 4);
        assertEq(no.totalDepositedKeys, 3);
        assertEq(no.depositableValidatorsCount, 4);
    }

    function test_obtainDepositData_RevertWhen_NoMoreKeys()
        public
        assertInvariants
    {
        vm.expectRevert(ICSModule.NotEnoughKeys.selector);
        module.obtainDepositData(1, "");
    }

    function test_obtainDepositData_nonceChanged() public assertInvariants {
        createNodeOperator();
        uint256 nonce = module.getNonce();

        module.obtainDepositData(1, "");
        assertEq(module.getNonce(), nonce + 1);
    }

    function testFuzz_obtainDepositData_MultipleOperators(
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

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);
    }

    function testFuzz_obtainDepositData_OneOperator(
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

        (
            ,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        ) = module.getStakingModuleSummary();
        assertEq(totalDepositedValidators, totalKeys - random);
        assertEq(depositableValidatorsCount, random);

        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.enqueuedCount, random);
        assertEq(no.totalDepositedKeys, totalKeys - random);
        assertEq(no.depositableValidatorsCount, random);
    }
}

abstract contract ModuleProposeNodeOperatorManagerAddressChange is
    ModuleFixtures
{
    function test_proposeNodeOperatorManagerAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChangeProposed(
            noId,
            address(0),
            stranger
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorManagerAddressChange_proposeNew() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChangeProposed(
            noId,
            stranger,
            strangerNumberTwo
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, strangerNumberTwo);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.proposeNodeOperatorManagerAddressChange(0, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_NotManager()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_AlreadyProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.AlreadyProposed.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorManagerAddressChange_RevertWhen_SameAddressProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, nodeOperator);
    }
}

abstract contract ModuleConfirmNodeOperatorManagerAddressChange is
    ModuleFixtures
{
    function test_confirmNodeOperatorManagerAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.confirmNodeOperatorManagerAddressChange(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, stranger);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.confirmNodeOperatorManagerAddressChange(0);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_NotProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(stranger);
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function test_confirmNodeOperatorManagerAddressChange_RevertWhen_OtherProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(nextAddress());
        module.confirmNodeOperatorManagerAddressChange(noId);
    }
}

abstract contract ModuleProposeNodeOperatorRewardAddressChange is
    ModuleFixtures
{
    function test_proposeNodeOperatorRewardAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChangeProposed(
            noId,
            address(0),
            stranger
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorRewardAddressChange_proposeNew() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChangeProposed(
            noId,
            stranger,
            strangerNumberTwo
        );
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, strangerNumberTwo);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.proposeNodeOperatorRewardAddressChange(0, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_NotRewardAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotRewardAddress.selector);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_AlreadyProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.AlreadyProposed.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
    }

    function test_proposeNodeOperatorRewardAddressChange_RevertWhen_SameAddressProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, nodeOperator);
    }
}

abstract contract ModuleConfirmNodeOperatorRewardAddressChange is
    ModuleFixtures
{
    function test_confirmNodeOperatorRewardAddressChange() public {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.confirmNodeOperatorRewardAddressChange(0);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_NotProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);
    }

    function test_confirmNodeOperatorRewardAddressChange_RevertWhen_OtherProposed()
        public
    {
        uint256 noId = createNodeOperator();
        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(nextAddress());
        module.confirmNodeOperatorRewardAddressChange(noId);
    }
}

abstract contract ModuleResetNodeOperatorManagerAddress is ModuleFixtures {
    function test_resetNodeOperatorManagerAddress() public {
        uint256 noId = createNodeOperator();

        vm.prank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        vm.prank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorManagerAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(stranger);
        module.resetNodeOperatorManagerAddress(noId);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, stranger);
        assertEq(no.rewardAddress, stranger);
    }

    function test_resetNodeOperatorManagerAddress_proposedManagerAddressIsReset()
        public
    {
        uint256 noId = createNodeOperator();
        address manager = nextAddress("MANAGER");

        vm.startPrank(nodeOperator);
        module.proposeNodeOperatorManagerAddressChange(noId, manager);
        module.proposeNodeOperatorRewardAddressChange(noId, stranger);
        vm.stopPrank();

        vm.startPrank(stranger);
        module.confirmNodeOperatorRewardAddressChange(noId);
        module.resetNodeOperatorManagerAddress(noId);
        vm.stopPrank();

        vm.expectRevert(INOAddresses.SenderIsNotProposedAddress.selector);
        vm.prank(manager);
        module.confirmNodeOperatorManagerAddressChange(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.resetNodeOperatorManagerAddress(0);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_NotRewardAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SenderIsNotRewardAddress.selector);
        vm.prank(stranger);
        module.resetNodeOperatorManagerAddress(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_SameAddress()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.resetNodeOperatorManagerAddress(noId);
    }

    function test_resetNodeOperatorManagerAddress_RevertWhen_ExtendedPermissions()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.MethodCallIsNotAllowed.selector);
        vm.prank(nodeOperator);
        module.resetNodeOperatorManagerAddress(noId);
    }
}

abstract contract ModuleChangeNodeOperatorRewardAddress is ModuleFixtures {
    function test_changeNodeOperatorRewardAddress() public {
        uint256 noId = createNodeOperator(true);

        vm.expectEmit(address(module));
        emit INOAddresses.NodeOperatorRewardAddressChanged(
            noId,
            nodeOperator,
            stranger
        );
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, stranger);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
    }

    function test_changeNodeOperatorRewardAddress_proposedRewardAddressReset()
        public
    {
        uint256 noId = createNodeOperator(true);

        vm.startPrank(nodeOperator);
        module.proposeNodeOperatorRewardAddressChange(noId, nextAddress());
        module.changeNodeOperatorRewardAddress(noId, stranger);
        vm.stopPrank();

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, stranger);
        assertEq(no.proposedRewardAddress, address(0));
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(0, stranger);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_SameAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.SameAddress.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, nodeOperator);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_ZeroRewardAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.ZeroRewardAddress.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, address(0));
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NotManagerAddress()
        public
    {
        uint256 noId = createNodeOperator(true);
        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        vm.prank(stranger);
        module.changeNodeOperatorRewardAddress(noId, stranger);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_SenderIsRewardAddress()
        public
    {
        uint256 noId = createNodeOperator(nodeOperator, stranger, true);

        vm.expectRevert(INOAddresses.SenderIsNotManagerAddress.selector);
        vm.prank(stranger);
        module.changeNodeOperatorRewardAddress(noId, nodeOperator);
    }

    function test_changeNodeOperatorRewardAddress_RevertWhen_NoExtendedPermissions()
        public
    {
        uint256 noId = createNodeOperator(false);
        vm.expectRevert(INOAddresses.MethodCallIsNotAllowed.selector);
        vm.prank(nodeOperator);
        module.changeNodeOperatorRewardAddress(noId, stranger);
    }
}

abstract contract ModuleVetKeys is ModuleFixtures {
    function test_vetKeys_OnUploadKeys() public assertInvariants {
        uint256 noId = createNodeOperator(2);

        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountChanged(noId, 3);
        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(module.QUEUE_LOWEST_PRIORITY(), noId, 1);
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 3);

        BatchInfo[] memory exp = new BatchInfo[](2);
        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        exp[1] = BatchInfo({ nodeOperatorId: noId, count: 1 });
        _assertQueueState(module.QUEUE_LOWEST_PRIORITY(), exp);
    }

    function test_vetKeys_Counters() public assertInvariants {
        uint256 noId = createNodeOperator(false);
        uint256 nonce = module.getNonce();
        uploadMoreKeys(noId, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_vetKeys_VettedBackViaRemoveKey() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 7);
        unvetKeys({ noId: noId, to: 4 });
        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 4);

        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountChanged(noId, 5); // 7 - 2 removed at the next step.

        vm.prank(nodeOperator);
        module.removeKeys(noId, 4, 2); // Remove keys 4 and 5.

        no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 5);
    }
}

abstract contract ModuleQueueOps is ModuleFixtures {
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

        (uint256 toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 1, "should remove 1 batch");

        bool isDirty = _isQueueDirty(LOOKUP_DEPTH);
        assertFalse(isDirty, "queue should be clean");
    }

    function test_cleanup_emptyQueue() public assertInvariants {
        _assertQueueIsEmpty();

        (uint256 toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_zeroMaxItems() public assertInvariants {
        (uint256 removed, uint256 lastRemovedAtDepth) = module
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
        (toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 2, "should remove 2 batch");

        // let's check the state of the queue
        BatchInfo[] memory exp = new BatchInfo[](2);
        exp[0] = BatchInfo({ nodeOperatorId: 0, count: 3 });
        exp[1] = BatchInfo({ nodeOperatorId: 1, count: 5 });
        _assertQueueState(module.QUEUE_LOWEST_PRIORITY(), exp);

        (toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
        assertEq(toRemove, 0, "queue should be clean");
    }

    function test_cleanup_WhenAllBatchesInvalid() public assertInvariants {
        createNodeOperator({ keysCount: 2 });
        createNodeOperator({ keysCount: 2 });
        unvetKeys({ noId: 0, to: 0 });
        unvetKeys({ noId: 1, to: 0 });

        (uint256 toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
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
            (uint256 toRemove, uint256 toVisit) = module.cleanDepositQueue({
                maxItems: 10
            });
            assertEq(toRemove, 2, "toRemove != 2");
            assertEq(toVisit, 6, "toVisit != 6");
        }

        vm.revertToState(snapshot);

        {
            (uint256 toRemove, uint256 toVisit) = module.cleanDepositQueue({
                maxItems: 6
            });
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
        module.cleanDepositQueue(1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(module.QUEUE_LOWEST_PRIORITY(), noId, 7);

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
        module.cleanDepositQueue(1);

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            0,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(module.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.submitWithdrawals(withdrawalInfo);
    }
}

abstract contract ModulePriorityQueue is ModuleFixtures {
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

    function test_migrateToPriorityQueue_EnqueuedLessThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 8);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uint256 initialNonce = module.getNonce();

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 8);

            module.migrateToPriorityQueue(noId);
        }

        assertEq(module.getNodeOperator(noId).enqueuedCount, 8 + 8);

        uint256 updatedNonce = module.getNonce();
        assertEq(
            updatedNonce,
            initialNonce + 1,
            "Module nonce should increment by 1"
        );

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 8 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 8 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_migrateToPriorityQueue_EnqueuedMoreThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 15);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 10);

            module.migrateToPriorityQueue(noId);
        }

        assertEq(module.getNodeOperator(noId).enqueuedCount, 15 + 10);

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 10 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 15 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_migrateToPriorityQueue_DepositedLessThanMaxDeposits() public {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 15);

        module.obtainDepositData(8, "");

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectEmit(address(module));
            emit ICSModule.BatchEnqueued(PRIORITY_QUEUE, noId, 2);

            module.migrateToPriorityQueue(noId);
        }

        assertEq(module.getNodeOperator(noId).enqueuedCount, 15 - 8 + 2);

        BatchInfo[] memory exp = new BatchInfo[](1);

        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 2 });
        _assertQueueState(PRIORITY_QUEUE, exp);

        // The batch was partially consumed by the obtainDepositData call.
        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 7 });
        _assertQueueState(REGULAR_QUEUE, exp);
    }

    function test_migrateToPriorityQueue_RevertsIfDepositedMoreThanMaxDeposits()
        public
    {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 15);

        module.obtainDepositData(12, "");

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectRevert(ICSModule.PriorityQueueMaxDepositsUsed.selector);
            module.migrateToPriorityQueue(noId);
        }
    }

    function test_migrateToPriorityQueue_RevertsIfPriorityQueueAlreadyUsedViaMigrate()
        public
    {
        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 15);

        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        module.migrateToPriorityQueue(noId);

        {
            vm.expectRevert(ICSModule.PriorityQueueAlreadyUsed.selector);
            module.migrateToPriorityQueue(noId);
        }
    }

    function test_migrateToPriorityQueue_RevertsIfPriorityQueueAlreadyUsedViaAddKeys()
        public
    {
        _assertQueueIsEmptyByPriority(PRIORITY_QUEUE);
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        uint256 noId = createNodeOperator(0);
        uploadMoreKeys(noId, 15);

        {
            vm.expectRevert(ICSModule.PriorityQueueAlreadyUsed.selector);
            module.migrateToPriorityQueue(noId);
        }
    }

    function test_migrateToPriorityQueue_RevertsIfNoPriorityQueue() public {
        vm.expectRevert(ICSModule.NotEligibleForPriorityQueue.selector);
        module.migrateToPriorityQueue(0);
    }

    function test_migrateToPriorityQueue_RevertsIfEmptyNodeOperator() public {
        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectRevert(ICSModule.NoQueuedKeysToMigrate.selector);
            module.migrateToPriorityQueue(0);
        }
    }

    function test_migrateToPriorityQueue_RevertsIfMaxDepositsUsed() public {
        createNodeOperator(MAX_DEPOSITS + 1);
        module.obtainDepositData(MAX_DEPOSITS, "");

        _enablePriorityQueue(PRIORITY_QUEUE, MAX_DEPOSITS);

        {
            vm.expectRevert(ICSModule.PriorityQueueMaxDepositsUsed.selector);
            module.migrateToPriorityQueue(0);
        }
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

        (uint256 toRemove, ) = module.cleanDepositQueue(LOOKUP_DEPTH);
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
            (uint256 toRemove, uint256 lastRemovedAtDepth) = module
                .cleanDepositQueue(3);
            vm.revertToState(snapshot);
            assertEq(toRemove, 0, "should remove 0 batch(es)");
            assertEq(lastRemovedAtDepth, 0, "the depth should be 0");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = module
                .cleanDepositQueue(4);
            vm.revertToState(snapshot);
            assertEq(toRemove, 1, "should remove 1 batch(es)");
            assertEq(lastRemovedAtDepth, 4, "the depth should be 4");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = module
                .cleanDepositQueue(7);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }

        {
            snapshot = vm.snapshotState();
            (uint256 toRemove, uint256 lastRemovedAtDepth) = module
                .cleanDepositQueue(100_500);
            vm.revertToState(snapshot);
            assertEq(toRemove, 2, "should remove 2 batch(es)");
            assertEq(lastRemovedAtDepth, 7, "the depth should be 7");
        }
    }

    function test_queueCleanupInvalidBatchesAfterMigrationToPriorityQueue()
        public
    {
        createNodeOperator({ keysCount: 12 });
        _enablePriorityQueue(0, 12);
        module.migrateToPriorityQueue(0);
        module.cleanDepositQueue({ maxItems: 2 });
        assertEq(module.getNodeOperator(0).enqueuedCount, 12);
    }

    function test_obtainDepositDataAfterMigrationSkipsInvalidBatches() public {
        createNodeOperator(10);
        createNodeOperator(10);

        _enablePriorityQueue(0, 8);
        module.migrateToPriorityQueue(0);

        module.obtainDepositData(20, "");
        assertEq(module.getNodeOperator(0).enqueuedCount, 0);
        assertEq(module.getNodeOperator(1).enqueuedCount, 0);
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

abstract contract ModuleDecreaseVettedSigningKeysCount is ModuleFixtures {
    function test_decreaseVettedSigningKeysCount_counters()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountChanged(noId, 1);
        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountDecreased(noId);
        unvetKeys({ noId: noId, to: 1 });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(module.getNonce(), nonce + 1);
        assertEq(no.totalVettedKeys, 1);
        assertEq(no.depositableValidatorsCount, 1);
    }

    function test_decreaseVettedSigningKeysCount_MultipleOperators()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 thirdNoId = createNodeOperator(15);
        uint256 newVettedFirst = 5;
        uint256 newVettedSecond = 3;

        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountChanged(firstNoId, newVettedFirst);
        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountDecreased(firstNoId);

        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountChanged(
            secondNoId,
            newVettedSecond
        );
        vm.expectEmit(address(module));
        emit ICSModule.VettedSigningKeysCountDecreased(secondNoId);

        module.decreaseVettedSigningKeysCount(
            bytes.concat(bytes8(uint64(firstNoId)), bytes8(uint64(secondNoId))),
            bytes.concat(
                bytes16(uint128(newVettedFirst)),
                bytes16(uint128(newVettedSecond))
            )
        );

        uint256 actualVettedFirst = module
            .getNodeOperator(firstNoId)
            .totalVettedKeys;
        uint256 actualVettedSecond = module
            .getNodeOperator(secondNoId)
            .totalVettedKeys;
        uint256 actualVettedThird = module
            .getNodeOperator(thirdNoId)
            .totalVettedKeys;
        assertEq(actualVettedFirst, newVettedFirst);
        assertEq(actualVettedSecond, newVettedSecond);
        assertEq(actualVettedThird, 15);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_MissingVettedData()
        public
    {
        uint256 firstNoId = createNodeOperator(10);
        uint256 secondNoId = createNodeOperator(7);
        uint256 newVettedFirst = 5;

        vm.expectRevert();
        module.decreaseVettedSigningKeysCount(
            bytes.concat(bytes8(uint64(firstNoId)), bytes8(uint64(secondNoId))),
            bytes.concat(bytes16(uint128(newVettedFirst)))
        );
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedEqOld()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 10;

        vm.expectRevert(ICSModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedGreaterOld()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(ICSModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NewVettedLowerTotalDeposited()
        public
    {
        uint256 noId = createNodeOperator(10);
        module.obtainDepositData(5, "");
        uint256 newVetted = 4;

        vm.expectRevert(ICSModule.InvalidVetKeysPointer.selector);
        unvetKeys(noId, newVetted);
    }

    function test_decreaseVettedSigningKeysCount_RevertWhen_NodeOperatorDoesNotExist()
        public
    {
        uint256 noId = createNodeOperator(10);
        uint256 newVetted = 15;

        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        unvetKeys(noId + 1, newVetted);
    }
}

abstract contract ModuleGetSigningKeys is ModuleFixtures {
    function test_getSigningKeys() public assertInvariants brutalizeMemory {
        bytes memory keys = randomBytes(48 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });

        assertEq(obtainedKeys, keys, "unexpected keys");
    }

    function test_getSigningKeys_getNonExistingKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
    }

    function test_getSigningKeys_getKeysFromOffset()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory wantedKey = randomBytes(48);
        bytes memory keys = bytes.concat(
            randomBytes(48),
            wantedKey,
            randomBytes(48)
        );

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: randomBytes(96 * 3)
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 1
        });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
    }

    function test_getSigningKeys_WhenNoNodeOperator()
        public
        assertInvariants
        brutalizeMemory
    {
        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeys(0, 0, 1);
    }
}

abstract contract ModuleGetSigningKeysWithSignatures is ModuleFixtures {
    function test_getSigningKeysWithSignatures()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48 * 3);
        bytes memory signatures = randomBytes(96 * 3);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .getSigningKeysWithSignatures({
                nodeOperatorId: noId,
                startIndex: 0,
                keysCount: 3
            });

        assertEq(obtainedKeys, keys, "unexpected keys");
        assertEq(obtainedSignatures, signatures, "unexpected signatures");
    }

    function test_getSigningKeysWithSignatures_getNonExistingKeys()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = randomBytes(48);
        bytes memory signatures = randomBytes(96);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: signatures
        });

        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
    }

    function test_getSigningKeysWithSignatures_getKeysFromOffset()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory wantedKey = randomBytes(48);
        bytes memory wantedSignature = randomBytes(96);
        bytes memory keys = bytes.concat(
            randomBytes(48),
            wantedKey,
            randomBytes(48)
        );
        bytes memory signatures = bytes.concat(
            randomBytes(96),
            wantedSignature,
            randomBytes(96)
        );

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 3,
            keys: keys,
            signatures: signatures
        });

        (bytes memory obtainedKeys, bytes memory obtainedSignatures) = module
            .getSigningKeysWithSignatures({
                nodeOperatorId: noId,
                startIndex: 1,
                keysCount: 1
            });

        assertEq(obtainedKeys, wantedKey, "unexpected key at position 1");
        assertEq(
            obtainedSignatures,
            wantedSignature,
            "unexpected sitnature at position 1"
        );
    }

    function test_getSigningKeysWithSignatures_WhenNoNodeOperator()
        public
        assertInvariants
        brutalizeMemory
    {
        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.getSigningKeysWithSignatures(0, 0, 1);
    }
}

abstract contract ModuleRemoveKeys is ModuleFixtures {
    bytes key0 = randomBytes(48);
    bytes key1 = randomBytes(48);
    bytes key2 = randomBytes(48);
    bytes key3 = randomBytes(48);
    bytes key4 = randomBytes(48);

    function test_singleKeyRemoval() public assertInvariants brutalizeMemory {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        // at the beginning
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 4);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
        /*
            key4
            key1
            key2
            key3
        */

        // in between
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 3);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 1
        });
        /*
            key4
            key3
            key2
        */

        // at the end
        {
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 2);
        }
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 2,
            keysCount: 1
        });
        /*
            key4
            key3
        */

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });
        assertEq(obtainedKeys, bytes.concat(key4, key3), "unexpected keys");

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 2);
    }

    function test_multipleKeysRemovalFromStart()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key0);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key3, key4, key2),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalInBetween()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key2);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key1);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 1,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key0, key3, key4),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_multipleKeysRemovalFromEnd()
        public
        assertInvariants
        brutalizeMemory
    {
        bytes memory keys = bytes.concat(key0, key1, key2, key3, key4);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: keys,
            signatures: randomBytes(96 * 5)
        });

        {
            // NOTE: keys are being removed in reverse order to keep an original order of keys at the end of the list
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key4);
            vm.expectEmit(address(module));
            emit IStakingModule.SigningKeyRemoved(noId, key3);

            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 3);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 3,
            keysCount: 2
        });

        bytes memory obtainedKeys = module.getSigningKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 3
        });
        assertEq(
            obtainedKeys,
            bytes.concat(key0, key1, key2),
            "unexpected keys"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 3);
    }

    function test_removeAllKeys() public assertInvariants brutalizeMemory {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 5,
            keys: randomBytes(48 * 5),
            signatures: randomBytes(96 * 5)
        });

        {
            vm.expectEmit(address(module));
            emit ICSModule.TotalSigningKeysCountChanged(noId, 0);
        }

        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 5
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 0);
    }

    function test_removeKeys_nonceChanged() public assertInvariants {
        bytes memory keys = bytes.concat(key0);

        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1,
            keys: keys,
            signatures: randomBytes(96)
        });

        uint256 nonce = module.getNonce();
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
        assertEq(module.getNonce(), nonce + 1);
    }
}

abstract contract ModuleRemoveKeysChargeFee is ModuleFixtures {
    function test_removeKeys_chargeFee() public assertInvariants {
        uint256 noId = createNodeOperator(3);

        uint256 amountToCharge = module
            .PARAMETERS_REGISTRY()
            .getKeyRemovalCharge(0) * 2;

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                amountToCharge
            ),
            1
        );

        vm.expectEmit(address(module));
        emit ICSModule.KeyRemovalChargeApplied(noId);

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the charge is fully paid.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_removeKeys_chargeFeeMoreThanBond() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        vm.prank(admin);
        module.PARAMETERS_REGISTRY().setKeyRemovalCharge(
            0,
            BOND_SIZE + 1 ether
        );

        vm.prank(nodeOperator);
        module.removeKeys(noId, 0, 1);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 0);
        // Target limit should be set to 0 and mode to 2 if the charge is more than bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_removeKeys_withNoFee() public assertInvariants {
        vm.prank(admin);
        module.PARAMETERS_REGISTRY().setKeyRemovalCharge(0, 0);

        uint256 noId = createNodeOperator(3);

        vm.recordLogs();

        vm.prank(nodeOperator);
        module.removeKeys(noId, 1, 2);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertNotEq(
                entries[i].topics[0],
                ICSModule.KeyRemovalChargeApplied.selector
            );
        }

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalAddedKeys, 1);
        // There should be no target limit if the is no charge.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }
}

abstract contract ModuleRemoveKeysReverts is ModuleFixtures {
    function test_removeKeys_RevertWhen_NoNodeOperator()
        public
        assertInvariants
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.removeKeys({ nodeOperatorId: 0, startIndex: 0, keysCount: 1 });
    }

    function test_removeKeys_RevertWhen_MoreThanAdded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 2
        });
    }

    function test_removeKeys_RevertWhen_LessThanDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 2
        });

        module.obtainDepositData(1, "");

        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
    }

    function test_removeKeys_RevertWhen_NotEligible() public assertInvariants {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.prank(stranger);
        vm.expectRevert(ICSModule.SenderIsNotEligible.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 1
        });
    }

    function test_removeKeys_RevertWhen_NoKeys() public assertInvariants {
        uint256 noId = createNodeOperator({
            managerAddress: address(this),
            keysCount: 1
        });

        vm.expectRevert(SigningKeys.InvalidKeysCount.selector);
        module.removeKeys({
            nodeOperatorId: noId,
            startIndex: 0,
            keysCount: 0
        });
    }
}

abstract contract ModuleGetNodeOperatorNonWithdrawnKeys is ModuleFixtures {
    function test_getNodeOperatorNonWithdrawnKeys() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(noId);
        assertEq(keys, 3);
    }

    function test_getNodeOperatorNonWithdrawnKeys_WithdrawnKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            0,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        module.submitWithdrawals(withdrawalInfo);
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(noId);
        assertEq(keys, 2);
    }

    function test_getNodeOperatorNonWithdrawnKeys_ZeroWhenNoNodeOperator()
        public
        view
    {
        uint256 keys = module.getNodeOperatorNonWithdrawnKeys(0);
        assertEq(keys, 0);
    }
}

abstract contract ModuleGetNodeOperatorSummary is ModuleFixtures {
    function test_getNodeOperatorSummary_defaultValues()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0);
        assertEq(summary.targetValidatorsCount, 0); // ?
        assertEq(summary.stuckValidatorsCount, 0);
        assertEq(summary.refundedValidatorsCount, 0);
        assertEq(summary.stuckPenaltyEndTimestamp, 0);
        assertEq(summary.totalExitedValidators, 0);
        assertEq(summary.totalDepositedValidators, 0);
        assertEq(summary.depositableValidatorsCount, 1);
    }

    function test_getNodeOperatorSummary_depositedKey()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(2);

        module.obtainDepositData(1, "");

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.depositableValidatorsCount, 1);
        assertEq(summary.totalDepositedValidators, 1);
    }

    function test_getNodeOperatorSummary_softTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitAndDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitAboveTotalKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 5);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            5,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 2, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitAndDeposited()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 2, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitAboveTotalKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 2, 5);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            5,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitEqualToDepositedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitLowerThanDepositedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitLowerThanVettedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            2,
            "depositableValidatorsCount mismatch"
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 3); // Should NOT be unvetted.
    }

    function test_getNodeOperatorSummary_targetLimitHigherThanVettedKeys()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.updateTargetValidatorsLimits(noId, 1, 9);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            9,
            "targetValidatorsCount mismatch"
        );
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_noTargetLimitDueToLockedBond()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(3, "");

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitDueToUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_noTargetLimitDueToUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_targetLimitDueToAllUnbonded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);

        module.obtainDepositData(2, "");

        penalize(noId, BOND_SIZE * 3);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitLowerThanUnbonded()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitLowerThanUnbonded_deposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(1, "");

        module.updateTargetValidatorsLimits(noId, 2, 2);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            2,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitGreaterThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitGreaterThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(4, "");

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            3,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_hardTargetLimitEqualUnbonded()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 2, 4);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            4,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitLowerThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 1, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            1,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitLowerThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(5, "");

        module.updateTargetValidatorsLimits(noId, 1, 1);

        penalize(noId, BOND_SIZE / 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            1,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitGreaterThanUnbondedNonDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.updateTargetValidatorsLimits(noId, 1, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            4,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 1, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_softTargetLimitGreaterThanUnbondedDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(4, "");

        module.updateTargetValidatorsLimits(noId, 1, 4);

        penalize(noId, BOND_SIZE + 100 wei);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            3,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedGreaterThanTotalMinusDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE * 3);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedEqualToTotalMinusDeposited()
        public
    {
        uint256 noId = createNodeOperator(5);

        module.obtainDepositData(3, "");

        penalize(noId, BOND_SIZE * 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedGreaterThanTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 4);

        penalize(noId, BOND_SIZE * 2);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedEqualToTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 4);

        penalize(noId, BOND_SIZE);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            4,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_getNodeOperatorSummary_unbondedLessThanTotalMinusVetted()
        public
    {
        uint256 noId = createNodeOperator(5);

        unvetKeys(noId, 3);

        penalize(noId, BOND_SIZE);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.depositableValidatorsCount,
            3,
            "depositableValidatorsCount mismatch"
        );
    }
}

abstract contract ModuleGetNodeOperator is ModuleFixtures {
    function test_getNodeOperator() public assertInvariants {
        uint256 noId = createNodeOperator();
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.managerAddress, nodeOperator);
        assertEq(no.rewardAddress, nodeOperator);
    }

    function test_getNodeOperator_WhenNoNodeOperator() public assertInvariants {
        NodeOperator memory no = module.getNodeOperator(0);
        assertEq(no.managerAddress, address(0));
        assertEq(no.rewardAddress, address(0));
    }
}

abstract contract ModuleUpdateTargetValidatorsLimits is ModuleFixtures {
    function test_updateTargetValidatorsLimits() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_updateTargetValidatorsLimits_sameValues()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 1, 1);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetLimitMode, 1);
        assertEq(summary.targetValidatorsCount, 1);
    }

    function test_updateTargetValidatorsLimits_limitIsZero()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 1, 0);
        module.updateTargetValidatorsLimits(noId, 1, 0);
    }

    function test_updateTargetValidatorsLimits_FromDisabledToDisabled_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.targetLimit, 0);
    }

    function test_updateTargetValidatorsLimits_enableSoftLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 1, 10);
        module.updateTargetValidatorsLimits(noId, 1, 10);
    }

    function test_updateTargetValidatorsLimits_enableHardLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 0, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 2, 10);
        module.updateTargetValidatorsLimits(noId, 2, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableSoftLimit_withZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withNonZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 10);
    }

    function test_updateTargetValidatorsLimits_disableHardLimit_withZeroTargetLimit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 0, 0);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_updateTargetValidatorsLimits_switchFromHardToSoftLimit()
        public
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 2, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 1, 5);
        module.updateTargetValidatorsLimits(noId, 1, 5);
    }

    function test_updateTargetValidatorsLimits_switchFromSoftToHardLimit()
        public
    {
        uint256 noId = createNodeOperator();
        module.updateTargetValidatorsLimits(noId, 1, 10);

        vm.expectEmit(address(module));
        emit ICSModule.TargetValidatorsCountChanged(noId, 2, 5);
        module.updateTargetValidatorsLimits(noId, 2, 5);
    }

    function test_updateTargetValidatorsLimits_NoUnvetKeysWhenLimitDisabled()
        public
    {
        uint256 noId = createNodeOperator(2);
        module.updateTargetValidatorsLimits(noId, 1, 1);
        module.updateTargetValidatorsLimits(noId, 0, 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalVettedKeys, 2);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.updateTargetValidatorsLimits(0, 1, 1);
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitExceedsUint32()
        public
    {
        createNodeOperator(1);
        vm.expectRevert(ICSModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(
            0,
            1,
            uint256(type(uint32).max) + 1
        );
    }

    function test_updateTargetValidatorsLimits_RevertWhen_TargetLimitModeExceedsMax()
        public
    {
        createNodeOperator(1);
        vm.expectRevert(ICSModule.InvalidInput.selector);
        module.updateTargetValidatorsLimits(0, 3, 1);
    }
}

abstract contract ModuleUpdateExitedValidatorsCount is ModuleFixtures {
    function test_updateExitedValidatorsCount_NonZero()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ExitedSigningKeysCountChanged(noId, 1);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 1, "totalExitedKeys not increased");

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_updateExitedValidatorsCount_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
    }

    function test_updateExitedValidatorsCount_RevertWhen_CountMoreThanDeposited()
        public
    {
        createNodeOperator(1);

        vm.expectRevert(ICSModule.ExitedKeysHigherThanTotalDeposited.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
    }

    function test_updateExitedValidatorsCount_RevertWhen_ExitedKeysDecrease()
        public
    {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.expectRevert(ICSModule.ExitedKeysDecrease.selector);
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000000))
        );
    }

    function test_updateExitedValidatorsCount_NoEventIfSameValue()
        public
        assertInvariants
    {
        createNodeOperator(1);
        module.obtainDepositData(1, "");

        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );

        vm.recordLogs();
        module.updateExitedValidatorsCount(
            bytes.concat(bytes8(0x0000000000000000)),
            bytes.concat(bytes16(0x00000000000000000000000000000001))
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // One event is NonceChanged
        assertEq(logs.length, 1);
    }
}

abstract contract ModuleUnsafeUpdateValidatorsCount is ModuleFixtures {
    function test_unsafeUpdateValidatorsCount_NonZero()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(5);
        module.obtainDepositData(5, "");
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ExitedSigningKeysCountChanged(noId, 1);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 1, "totalExitedKeys not increased");
        assertEq(
            no.stuckValidatorsCount,
            0,
            "stuckValidatorsCount not increased"
        );

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: 100500,
            exitedValidatorsKeysCount: 1
        });
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_NotStakingRouter()
        public
    {
        expectRoleRevert(stranger, module.STAKING_ROUTER_ROLE());
        vm.prank(stranger);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: 100500,
            exitedValidatorsKeysCount: 1
        });
    }

    function test_unsafeUpdateValidatorsCount_RevertWhen_ExitedCountMoreThanDeposited()
        public
    {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(ICSModule.ExitedKeysHigherThanTotalDeposited.selector);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 100500
        });
    }

    function test_unsafeUpdateValidatorsCount_DecreaseExitedKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        setExited(0, 1);

        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 0
        });

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalExitedKeys, 0, "totalExitedKeys should be zero");
    }

    function test_unsafeUpdateValidatorsCount_NoEventIfSameValue()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });

        vm.recordLogs();
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // One event is NonceChanged
        assertEq(logs.length, 1);
    }
}

abstract contract ModuleReportELRewardsStealingPenalty is ModuleFixtures {
    function test_reportELRewardsStealingPenalty_HappyPath()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltyReported(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            BOND_SIZE /
                2 +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_reportELRewardsStealingPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.reportELRewardsStealingPenalty(
            0,
            blockhash(block.number),
            1 ether
        );
    }

    function test_reportELRewardsStealingPenalty_RevertWhen_ZeroAmount()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(ICSModule.InvalidAmount.selector);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            0 ether
        );
    }

    function test_reportELRewardsStealingPenalty_NoNonceChange()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        vm.deal(nodeOperator, 32 ether);
        vm.prank(nodeOperator);
        accounting.depositETH{ value: 32 ether }(0);

        uint256 nonce = module.getNonce();

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        assertEq(module.getNonce(), nonce);
    }

    function test_reportELRewardsStealingPenalty_EnqueueAfterUnlock()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            BOND_SIZE /
                2 +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);

        createNodeOperator();
        module.obtainDepositData(1, "");

        vm.warp(accounting.getBondLockPeriod() + 1);

        vm.expectEmit(address(module));
        emit ICSModule.BatchEnqueued(module.QUEUE_LOWEST_PRIORITY(), noId, 1);
        module.updateDepositableValidatorsCount(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);
    }
}

abstract contract ModuleCancelELRewardsStealingPenalty is ModuleFixtures {
    function test_cancelELRewardsStealingPenalty_HappyPath()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltyCancelled(
            noId,
            BOND_SIZE /
                2 +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
        module.cancelELRewardsStealingPenalty(
            noId,
            BOND_SIZE /
                2 +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(lockedBond, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_cancelELRewardsStealingPenalty_Partial()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE / 2
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltyCancelled(noId, BOND_SIZE / 2);
        module.cancelELRewardsStealingPenalty(noId, BOND_SIZE / 2);

        uint256 lockedBond = accounting.getActualLockedBond(noId);
        assertEq(
            lockedBond,
            module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(0)
        );
        // nonce should not change due to no changes in the depositable validators
        assertEq(module.getNonce(), nonce);
    }

    function test_cancelELRewardsStealingPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.cancelELRewardsStealingPenalty(0, 1 ether);
    }
}

abstract contract ModuleSettleELRewardsStealingPenaltyBasic is ModuleFixtures {
    function test_settleELRewardsStealingPenalty() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(noId);
        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        // If the penalty is settled the targetValidatorsCount should be 0
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 2, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            0,
            "depositableValidatorsCount mismatch"
        );
    }

    function test_settleELRewardsStealingPenalty_revertWhen_InvalidInput()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );

        vm.expectRevert(ICSModule.InvalidInput.selector);
        module.settleELRewardsStealingPenalty(idsToSettle, new uint256[](0));
    }

    function test_settleELRewardsStealingPenalty_lockedGreaterThanAllowedToSettle()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary
            .depositableValidatorsCount;

        module.settleELRewardsStealingPenalty(idsToSettle, UintArr(amount));
        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(noId);
        assertEq(
            lock.amount,
            amount +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleELRewardsStealingPenalty_multipleNOs()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        module.reportELRewardsStealingPenalty(
            firstNoId,
            blockhash(block.number),
            1 ether
        );
        module.reportELRewardsStealingPenalty(
            secondNoId,
            blockhash(block.number),
            BOND_SIZE
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(firstNoId);
        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(secondNoId);
        module.settleELRewardsStealingPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        lock = accounting.getLockedBondInfo(secondNoId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleELRewardsStealingPenalty_multipleNOs_oneWithLockedGreaterThanAllowedToSettle()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](2);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        uint256 amount = 1 ether;
        module.reportELRewardsStealingPenalty(
            firstNoId,
            blockhash(block.number),
            amount
        );
        module.reportELRewardsStealingPenalty(
            secondNoId,
            blockhash(block.number),
            BOND_SIZE
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(secondNoId);
        module.settleELRewardsStealingPenalty(
            idsToSettle,
            UintArr(amount, type(uint256).max)
        );

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(
            lock.amount,
            amount +
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        lock = accounting.getLockedBondInfo(secondNoId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleELRewardsStealingPenalty_NoLock()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary
            .depositableValidatorsCount;
        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(
            summary.targetValidatorsCount,
            0,
            "targetValidatorsCount mismatch"
        );
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleELRewardsStealingPenalty_multipleNOs_NoLock()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.settleELRewardsStealingPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        CSBondLock.BondLock memory firstLock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        CSBondLock.BondLock memory secondLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleELRewardsStealingPenalty_multipleNOs_oneWithNoLock()
        public
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.reportELRewardsStealingPenalty(
            secondNoId,
            blockhash(block.number),
            1 ether
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(secondNoId);
        module.settleELRewardsStealingPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        CSBondLock.BondLock memory firstLock = accounting.getLockedBondInfo(
            firstNoId
        );
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        CSBondLock.BondLock memory secondLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleELRewardsStealingPenalty_withDuplicates() public {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](3);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        idsToSettle[2] = secondNoId;

        uint256 bondBalanceBefore = accounting.getBond(secondNoId);

        uint256 lockAmount = 1 ether;
        module.reportELRewardsStealingPenalty(
            secondNoId,
            blockhash(block.number),
            lockAmount
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(secondNoId);
        module.settleELRewardsStealingPenalty(
            idsToSettle,
            UintArr(type(uint256).max, type(uint256).max, type(uint256).max)
        );

        uint256 bondBalanceAfter = accounting.getBond(secondNoId);

        CSBondLock.BondLock memory currentLock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(currentLock.amount, 0 ether);
        assertEq(currentLock.until, 0);
        assertEq(
            bondBalanceAfter,
            bondBalanceBefore -
                lockAmount -
                module.PARAMETERS_REGISTRY().getElRewardsStealingAdditionalFine(
                    0
                )
        );
    }

    function test_settleELRewardsStealingPenalty_RevertWhen_NoExistingNodeOperator()
        public
    {
        uint256 noId = createNodeOperator();

        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.settleELRewardsStealingPenalty(
            UintArr(noId + 1),
            UintArr(type(uint256).max)
        );
    }
}

abstract contract ModuleSettleELRewardsStealingPenaltyAdvanced is
    ModuleFixtures
{
    function test_settleELRewardsStealingPenalty_PeriodIsExpired() public {
        uint256 noId = createNodeOperator();
        uint256 period = accounting.getBondLockPeriod();
        uint256 amount = 1 ether;

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );

        vm.warp(block.timestamp + period + 1 seconds);

        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );

        assertEq(accounting.getActualLockedBond(noId), 0);
    }

    function test_settleELRewardsStealingPenalty_multipleNOs_oneExpired()
        public
    {
        uint256 period = accounting.getBondLockPeriod();
        uint256 firstNoId = createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(2);
        module.reportELRewardsStealingPenalty(
            firstNoId,
            blockhash(block.number),
            1 ether
        );
        vm.warp(block.timestamp + period + 1 seconds);
        module.reportELRewardsStealingPenalty(
            secondNoId,
            blockhash(block.number),
            BOND_SIZE
        );

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(secondNoId);
        module.settleELRewardsStealingPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        assertEq(accounting.getActualLockedBond(firstNoId), 0);

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(
            secondNoId
        );
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleELRewardsStealingPenalty_NoBond()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 amount = accounting.getBond(noId) + 1 ether;

        // penalize all current bond to make an edge case when there is no bond but a new lock is applied
        penalize(noId, amount);

        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );
        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltySettled(noId);
        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }
}

abstract contract ModuleCompensateELRewardsStealingPenalty is ModuleFixtures {
    function test_compensateELRewardsStealingPenalty() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getElRewardsStealingAdditionalFine(0);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltyCompensated(noId, amount + fine);

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.compensateLockedBondETH.selector,
                noId
            )
        );
        vm.deal(nodeOperator, amount + fine);
        vm.prank(nodeOperator);
        module.compensateELRewardsStealingPenalty{ value: amount + fine }(noId);

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_compensateELRewardsStealingPenalty_Partial()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getElRewardsStealingAdditionalFine(0);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit ICSModule.ELRewardsStealingPenaltyCompensated(noId, amount);

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.compensateLockedBondETH.selector,
                noId
            )
        );
        vm.deal(nodeOperator, amount);
        vm.prank(nodeOperator);
        module.compensateELRewardsStealingPenalty{ value: amount }(noId);

        CSBondLock.BondLock memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, fine);
        assertEq(module.getNonce(), nonce);
    }

    function test_compensateELRewardsStealingPenalty_depositableValidatorsChanged()
        public
    {
        uint256 noId = createNodeOperator(2);
        uint256 amount = 1 ether;
        uint256 fine = module
            .PARAMETERS_REGISTRY()
            .getElRewardsStealingAdditionalFine(0);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            amount
        );
        module.obtainDepositData(1, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        vm.deal(nodeOperator, amount + fine);
        vm.prank(nodeOperator);
        module.compensateELRewardsStealingPenalty{ value: amount + fine }(noId);
        uint256 depositableAfter = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;
        assertEq(depositableAfter, depositableBefore + 1);

        BatchInfo[] memory exp = new BatchInfo[](1);
        exp[0] = BatchInfo({ nodeOperatorId: noId, count: 1 });
        _assertQueueState(module.QUEUE_LOWEST_PRIORITY(), exp);
    }

    function test_compensateELRewardsStealingPenalty_RevertWhen_NoNodeOperator()
        public
    {
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.compensateELRewardsStealingPenalty{ value: 1 ether }(0);
    }

    function test_compensateELRewardsStealingPenalty_RevertWhen_NotManager()
        public
    {
        uint256 noId = createNodeOperator();
        vm.expectRevert(ICSModule.SenderIsNotEligible.selector);
        module.compensateELRewardsStealingPenalty{ value: 1 ether }(noId);
    }
}

abstract contract ModuleSubmitWithdrawals is ModuleFixtures {
    function test_submitWithdrawals() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectEmit(address(module));
        emit ICSModule.WithdrawalSubmitted(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0,
            pubkey
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        bool withdrawn = module.isValidatorWithdrawn(noId, keyIndex);
        assertTrue(withdrawn);

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_submitWithdrawals_changeNonce() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        vm.expectEmit(address(module));
        emit ICSModule.WithdrawalSubmitted(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0,
            pubkey
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        // depositable decrease should
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_submitWithdrawals_lowExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_superLowExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE + 1 ether;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_exitDelayPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_hugeExitDelayPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_exitDelayPenaltyWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(penalty, true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_exitDelayPenaltyAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = type(uint248).max;
        uint256 multiplier = module.MAX_PENALTY_MULTIPLIER();

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(penalty, true),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1000 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_strikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_hugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_strikesPenaltyWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_strikesPenaltyAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = type(uint248).max;
        uint256 multiplier = module.MAX_PENALTY_MULTIPLIER();

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1000 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_allPenalties() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = (BOND_SIZE - 1 ether) / 3;
        uint256 exitDelayPenaltyAmount = (BOND_SIZE - 1 ether) / 3;
        uint256 strikesPenaltyAmount = (BOND_SIZE - 1 ether) / 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage + exitDelayPenaltyAmount + strikesPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_allPenaltiesHugeSum()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = (BOND_SIZE + 1 ether) / 3;
        uint256 exitDelayPenaltyAmount = (BOND_SIZE + 1 ether) / 3;
        uint256 strikesPenaltyAmount = (BOND_SIZE + 1 ether) / 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage + exitDelayPenaltyAmount + strikesPenaltyAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_allPenaltiesWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 delayPenalty = 2 ether;
        uint248 strikesPenalty = 3 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(delayPenalty, true),
                strikesPenalty: MarkedUint248(strikesPenalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                delayPenalty * multiplier + strikesPenalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_allPenaltiesAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 delayPenalty = type(uint248).max;
        uint248 strikesPenalty = type(uint248).max;
        uint256 multiplier = module.MAX_PENALTY_MULTIPLIER();

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(delayPenalty, true),
                strikesPenalty: MarkedUint248(strikesPenalty, true),
                withdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier + 1000 ether,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                delayPenalty * multiplier + strikesPenalty * multiplier
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_slashingPenaltyApplied()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 5 ether;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            slashingPenalty
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_slashingPenaltyOverridesExitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 5 ether;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - 11 ether,
            slashingPenalty
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_slashingPenaltyNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 7 ether;
        uint256 multiplier = 5;

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier,
            slashingPenalty
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_DelayPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE -
            exitDelayPenaltyAmount -
            0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_hugeDelayPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are covered by the bond but the penalties are not.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeHugeWithdrawalFee_DelayPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE -
            strikesPenaltyAmount -
            0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_HugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are covered by the bond but the penalties are not.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeHugeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_DelayAndStrikesPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = (BOND_SIZE - 1 ether) / 2;
        uint256 strikesPenaltyAmount = (BOND_SIZE - 1 ether) / 2;
        uint256 withdrawalRequestFeeAmount = strikesPenaltyAmount - 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount + strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_DelayAndStrikesPenalties_AllHuge()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(
                    uint248(exitDelayPenaltyAmount),
                    true
                ),
                strikesPenalty: MarkedUint248(
                    uint248(strikesPenaltyAmount),
                    true
                ),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                exitDelayPenaltyAmount + strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeWithdrawalFee_zeroPenaltyValue()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_chargeHugeWithdrawalFee_zeroPenaltyValue()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_submitWithdrawals_chargeWithdrawalFeeNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 withdrawalRequestFee = 0.1 ether;
        uint256 multiplier = 5;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                withdrawalRequestFee: MarkedUint248(withdrawalRequestFee, true)
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() * multiplier,
            0
        );

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFee
            )
        );
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_dontChargeWithdrawalFee_noPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if there were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_dontChargeWithdrawalFee_exitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;
        uint256 balanceShortage = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayPenalty: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                withdrawalRequestFee: MarkedUint248(
                    uint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);

        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            keyIndex,
            module.MIN_ACTIVATION_BALANCE() - balanceShortage,
            0
        );

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.submitWithdrawals(withdrawalInfo);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_submitWithdrawals_unbondedKeys() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(noId, keyIndex, 1 ether, 0);

        module.submitWithdrawals(withdrawalInfo);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_submitWithdrawals_RevertWhen_ZeroExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(noId, keyIndex, 0, 0);

        vm.expectRevert(ICSModule.ZeroExitBalance.selector);
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_RevertWhen_NoNodeOperator()
        public
        assertInvariants
    {
        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(0, 0, 32 ether, 0);

        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_RevertWhen_InvalidKeyIndexOffset()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(noId, 0, 32 ether, 0);

        vm.expectRevert(ICSModule.SigningKeysInvalidOffset.selector);
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_submitWithdrawals_alreadyWithdrawn() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            0,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );

        module.submitWithdrawals(withdrawalInfo);

        uint256 nonceBefore = module.getNonce();
        module.submitWithdrawals(withdrawalInfo);
        assertEq(
            module.getNonce(),
            nonceBefore,
            "Nonce should not change when trying to withdraw already withdrawn key"
        );
    }

    function test_submitWithdrawals_nonceIncrementsOnceForManyWithdrawals()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");
        uint256 nonceBefore = module.getNonce();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](3);
        for (uint256 i = 0; i < 3; ++i) {
            withdrawalInfo[i] = ValidatorWithdrawalInfo(
                noId,
                i,
                module.MIN_ACTIVATION_BALANCE(),
                0
            );
        }
        module.submitWithdrawals(withdrawalInfo);
        assertEq(
            module.getNonce(),
            nonceBefore + 1,
            "Module nonce should increment only once for batch withdrawals"
        );
    }
}

abstract contract ModuleGetStakingModuleSummary is ModuleFixtures {
    function test_getStakingModuleSummary_depositableValidators()
        public
        assertInvariants
    {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(2);
        StakingModuleSummary memory summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.depositableValidatorsCount, 1);
        assertEq(secondNo.depositableValidatorsCount, 2);
        assertEq(summary.depositableValidatorsCount, 3);
    }

    function test_getStakingModuleSummary_depositedValidators()
        public
        assertInvariants
    {
        uint256 first = createNodeOperator(1);
        uint256 second = createNodeOperator(2);
        StakingModuleSummary memory summary = getStakingModuleSummary();
        assertEq(summary.totalDepositedValidators, 0);

        module.obtainDepositData(3, "");

        summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.totalDepositedKeys, 1);
        assertEq(secondNo.totalDepositedKeys, 2);
        assertEq(summary.totalDepositedValidators, 3);
    }

    function test_getStakingModuleSummary_exitedValidators()
        public
        assertInvariants
    {
        uint256 first = createNodeOperator(2);
        uint256 second = createNodeOperator(2);
        module.obtainDepositData(4, "");
        StakingModuleSummary memory summary = getStakingModuleSummary();
        assertEq(summary.totalExitedValidators, 0);

        module.updateExitedValidatorsCount(
            bytes.concat(
                bytes8(0x0000000000000000),
                bytes8(0x0000000000000001)
            ),
            bytes.concat(
                bytes16(0x00000000000000000000000000000001),
                bytes16(0x00000000000000000000000000000002)
            )
        );

        summary = getStakingModuleSummary();
        NodeOperator memory firstNo = module.getNodeOperator(first);
        NodeOperator memory secondNo = module.getNodeOperator(second);

        assertEq(firstNo.totalExitedKeys, 1);
        assertEq(secondNo.totalExitedKeys, 2);
        assertEq(summary.totalExitedValidators, 3);
    }
}

abstract contract ModuleAccessControl is ModuleFixtures {
    function test_adminRole() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            _accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        _enableInitializers(address(csm));
        csm.initialize(actor);

        bytes32 role = csm.DEFAULT_ADMIN_ROLE();
        vm.prank(actor);
        csm.grantRole(role, stranger);
        assertTrue(csm.hasRole(role, stranger));

        vm.prank(actor);
        csm.revokeRole(role, stranger);
        assertFalse(csm.hasRole(role, stranger));
    }

    function test_adminRole_revert() public {
        CSModule csm = new CSModule({
            moduleType: "community-staking-module",
            lidoLocator: address(locator),
            parametersRegistry: address(parametersRegistry),
            _accounting: address(accounting),
            exitPenalties: address(exitPenalties)
        });
        bytes32 role = csm.DEFAULT_ADMIN_ROLE();
        bytes32 adminRole = csm.DEFAULT_ADMIN_ROLE();

        vm.startPrank(stranger);
        expectRoleRevert(stranger, adminRole);
        csm.grantRole(role, stranger);
    }

    function test_createNodeOperatorRole() public {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_createNodeOperatorRole_revert() public {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.createNodeOperator(
            nodeOperator,
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            address(0)
        );
    }

    function test_reportELRewardsStealingPenaltyRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_EL_REWARDS_STEALING_PENALTY_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            1 ether
        );
    }

    function test_reportELRewardsStealingPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.REPORT_EL_REWARDS_STEALING_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            1 ether
        );
    }

    function test_settleELRewardsStealingPenaltyRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }

    function test_settleELRewardsStealingPenaltyRole_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.settleELRewardsStealingPenalty(
            UintArr(noId),
            UintArr(type(uint256).max)
        );
    }

    function test_verifierRole_submitWithdrawals() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.VERIFIER_ROLE();

        vm.startPrank(admin);
        module.grantRole(role, actor);
        module.grantRole(module.STAKING_ROUTER_ROLE(), admin);
        module.obtainDepositData(1, "");
        vm.stopPrank();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(noId, 0, 1 ether, 0);

        vm.prank(actor);
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_verifierRole_submitWithdrawals_revert() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.VERIFIER_ROLE();

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](1);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(noId, 0, 1 ether, 0);

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.submitWithdrawals(withdrawalInfo);
    }

    function test_recovererRole() public {
        bytes32 role = module.RECOVERER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.recoverEther();
    }

    function test_recovererRole_revert() public {
        bytes32 role = module.RECOVERER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.recoverEther();
    }
}

abstract contract ModuleStakingRouterAccessControl is ModuleFixtures {
    function test_stakingRouterRole_onRewardsMinted() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onRewardsMinted(0);
    }

    function test_stakingRouterRole_onRewardsMinted_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.onRewardsMinted(0);
    }

    function test_stakingRouterRole_updateExitedValidatorsCount() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.updateExitedValidatorsCount("", "");
    }

    function test_stakingRouterRole_updateExitedValidatorsCount_revert()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.updateExitedValidatorsCount("", "");
    }

    function test_stakingRouterRole_updateTargetValidatorsLimits() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_stakingRouterRole_updateTargetValidatorsLimits_revert()
        public
    {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.updateTargetValidatorsLimits(noId, 0, 0);
    }

    function test_stakingRouterRole_onExitedAndStuckValidatorsCountsUpdated()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.onExitedAndStuckValidatorsCountsUpdated();
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        uint256 nonceBefore = module.getNonce();
        vm.prank(actor);
        module.onWithdrawalCredentialsChanged();
        assertEq(
            module.getNonce(),
            nonceBefore + 1,
            "Module nonce should increment by 1"
        );
    }

    function test_stakingRouterRole_onWithdrawalCredentialsChanged_revert()
        public
    {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.onWithdrawalCredentialsChanged();
    }

    function test_stakingRouterRole_obtainDepositData() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.obtainDepositData(0, "");
    }

    function test_stakingRouterRole_obtainDepositData_revert() public {
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.obtainDepositData(0, "");
    }

    function test_stakingRouterRole_unsafeUpdateValidatorsCountRole() public {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.unsafeUpdateValidatorsCount(noId, 0);
    }

    function test_stakingRouterRole_unsafeUpdateValidatorsCountRole_revert()
        public
    {
        uint256 noId = createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.unsafeUpdateValidatorsCount(noId, 0);
    }

    function test_stakingRouterRole_unvetKeys() public {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();
        vm.prank(admin);
        module.grantRole(role, actor);

        vm.prank(actor);
        module.decreaseVettedSigningKeysCount(new bytes(0), new bytes(0));
    }

    function test_stakingRouterRole_unvetKeys_revert() public {
        createNodeOperator();
        bytes32 role = module.STAKING_ROUTER_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.decreaseVettedSigningKeysCount(new bytes(0), new bytes(0));
    }
}

abstract contract ModuleDepositableValidatorsCount is ModuleFixtures {
    function test_depositableValidatorsCountChanges_OnDeposit()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 7);
        module.obtainDepositData(3, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 4);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 4);
    }

    function test_depositableValidatorsCountChanges_OnUnsafeUpdateExitedValidators()
        public
    {
        uint256 noId = createNodeOperator(7);
        createNodeOperator(2);
        module.obtainDepositData(4, "");

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 1
        });
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
    }

    function test_depositableValidatorsCountDoesntChange_OnUnsafeUpdateStuckValidators()
        public
    {
        uint256 noId = createNodeOperator(7);
        createNodeOperator(2);
        module.obtainDepositData(4, "");

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
        module.unsafeUpdateValidatorsCount({
            nodeOperatorId: noId,
            exitedValidatorsKeysCount: 0
        });
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 5);
    }

    function test_depositableValidatorsCountChanges_OnUnvetKeys()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 nonce = module.getNonce();
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 7);
        unvetKeys(noId, 3);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_depositableValidatorsCountChanges_OnWithdrawal()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);

        penalize(noId, BOND_SIZE * 3);

        ValidatorWithdrawalInfo[]
            memory withdrawalInfo = new ValidatorWithdrawalInfo[](3);
        withdrawalInfo[0] = ValidatorWithdrawalInfo(
            noId,
            0,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );
        withdrawalInfo[1] = ValidatorWithdrawalInfo(
            noId,
            1,
            module.MIN_ACTIVATION_BALANCE(),
            0
        );
        withdrawalInfo[2] = ValidatorWithdrawalInfo(
            noId,
            2,
            module.MIN_ACTIVATION_BALANCE() - BOND_SIZE,
            0
        ); // Large CL balance drop, that doesn't change the unbonded count.

        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 0);
        module.submitWithdrawals(withdrawalInfo);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 2);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 2);
    }

    function test_depositableValidatorsCountChanges_OnReportStealing()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            (BOND_SIZE * 3) / 2
        ); // Lock bond to unbond 2 validators.
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 1);
    }

    function test_depositableValidatorsCountChanges_OnReleaseStealingPenalty()
        public
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        module.reportELRewardsStealingPenalty(
            noId,
            blockhash(block.number),
            BOND_SIZE
        ); // Lock bond to unbond 2 validators (there's stealing fine).
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 1);
        module.cancelELRewardsStealingPenalty(
            noId,
            accounting.getLockedBondInfo(noId).amount
        );
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3); // Stealing fine is applied so
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 3);
    }

    function test_depositableValidatorsCountChanges_OnRemoveUnvetted()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        unvetKeys(noId, 3);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 3);
        vm.prank(nodeOperator);
        module.removeKeys(noId, 3, 1); // Removal charge is applied, hence one key is unbonded.
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 6);
        assertEq(getStakingModuleSummary().depositableValidatorsCount, 6);
    }
}

abstract contract ModuleNodeOperatorStateAfterUpdateCurve is ModuleFixtures {
    function updateToBetterCurve() public {
        accounting.updateBondCurve(0, 1.5 ether);
    }

    function updateToWorseCurve() public {
        accounting.updateBondCurve(0, 2.5 ether);
    }

    function test_depositedOnly_UpdateToBetterCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_depositedOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after normalization"
        );
    }

    function test_depositableOnly_UpdateToWorseCurve() public assertInvariants {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedDepositedOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 0);

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_partiallyUnbondedDepositedOnly_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(7, "");

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after curve update"
        );
        assertEq(accounting.getUnbondedKeysCount(noId), 2);

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            0,
            "Depositables should not change after normalization"
        );
    }

    function test_partiallyUnbondedDepositableOnly_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedDepositableOnly_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToBetterCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToBetterCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredBefore,
            requiredAfter,
            "Required bond should decrease"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            0,
            "Should be no unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore,
            "Depositables should be increased after normalization"
        );
    }

    function test_partiallyUnbondedPartiallyDeposited_UpdateToWorseCurve()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(7);
        module.obtainDepositData(4, "");
        uint256 depositableBefore = module
            .getNodeOperator(noId)
            .depositableValidatorsCount;

        penalize(noId, BOND_SIZE / 2);

        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should decrease after penalization"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            1,
            "Should be unbonded keys after penalization"
        );

        (, uint256 requiredBefore) = accounting.getBondSummary(noId);
        updateToWorseCurve();
        (, uint256 requiredAfter) = accounting.getBondSummary(noId);

        assertGt(
            requiredAfter,
            requiredBefore,
            "Required bond should increase"
        );
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 1,
            "Depositables should not change after curve update"
        );
        assertEq(
            accounting.getUnbondedKeysCount(noId),
            2,
            "Should be unbonded keys after curve update"
        );

        module.updateDepositableValidatorsCount(noId);
        assertEq(
            module.getNodeOperator(noId).depositableValidatorsCount,
            depositableBefore - 2,
            "Depositables should decrease after normalization"
        );
    }
}

abstract contract ModuleOnRewardsMinted is ModuleFixtures {
    function test_onRewardsMinted() public assertInvariants {
        uint256 reportShares = 100000;
        uint256 someDustShares = 100;

        stETH.mintShares(address(module), someDustShares);
        stETH.mintShares(address(module), reportShares);

        vm.prank(stakingRouter);
        module.onRewardsMinted(reportShares);

        assertEq(stETH.sharesOf(address(module)), someDustShares);
        assertEq(stETH.sharesOf(address(feeDistributor)), reportShares);
    }
}

abstract contract ModuleRecoverERC20 is ModuleFixtures {
    function test_recoverERC20() public assertInvariants {
        vm.startPrank(admin);
        module.grantRole(module.RECOVERER_ROLE(), stranger);
        vm.stopPrank();

        ERC20Testable token = new ERC20Testable();
        token.mint(address(module), 1000);

        vm.prank(stranger);
        vm.expectEmit(address(module));
        emit IAssetRecovererLib.ERC20Recovered(address(token), stranger, 1000);
        module.recoverERC20(address(token), 1000);

        assertEq(token.balanceOf(address(module)), 0);
        assertEq(token.balanceOf(stranger), 1000);
    }
}

abstract contract ModuleMisc is ModuleFixtures {
    function test_getInitializedVersion() public view {
        assertEq(module.getInitializedVersion(), 2);
    }

    function test_getActiveNodeOperatorsCount_OneOperator()
        public
        assertInvariants
    {
        createNodeOperator();
        uint256 noCount = module.getNodeOperatorsCount();
        assertEq(noCount, 1);
    }

    function test_getActiveNodeOperatorsCount_MultipleOperators()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();
        uint256 noCount = module.getNodeOperatorsCount();
        assertEq(noCount, 3);
    }

    function test_getNodeOperatorIsActive() public assertInvariants {
        uint256 noId = createNodeOperator();
        bool active = module.getNodeOperatorIsActive(noId);
        assertTrue(active);
    }

    function test_getNodeOperatorIds() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();

        uint256[] memory noIds = new uint256[](3);
        noIds[0] = firstNoId;
        noIds[1] = secondNoId;
        noIds[2] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(0, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_Offset() public assertInvariants {
        createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = secondNoId;
        noIds[1] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(1, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_OffsetEqualsNodeOperatorsCount()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(3, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_OffsetHigherThanNodeOperatorsCount()
        public
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(4, 5);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_ZeroLimit() public assertInvariants {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](0);
        noIdsActual = module.getNodeOperatorIds(0, 0);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_ZeroLimitAndOffsetHigherThanNodeOperatorsCount()
        public
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](0);

        uint256[] memory noIdsActual = new uint256[](0);
        noIdsActual = module.getNodeOperatorIds(4, 0);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_Limit() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = firstNoId;
        noIds[1] = secondNoId;

        uint256[] memory noIdsActual = new uint256[](2);
        noIdsActual = module.getNodeOperatorIds(0, 2);

        assertEq(noIdsActual, noIds);
    }

    function test_getNodeOperatorIds_LimitAndOffset() public assertInvariants {
        createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256 thirdNoId = createNodeOperator();
        createNodeOperator();

        uint256[] memory noIds = new uint256[](2);
        noIds[0] = secondNoId;
        noIds[1] = thirdNoId;

        uint256[] memory noIdsActual = new uint256[](5);
        noIdsActual = module.getNodeOperatorIds(1, 2);

        assertEq(noIdsActual, noIds);
    }

    function test_getActiveNodeOperatorsCount_One() public assertInvariants {
        createNodeOperator();

        uint256 activeCount = module.getActiveNodeOperatorsCount();

        assertEq(activeCount, 1);
    }

    function test_getActiveNodeOperatorsCount_Multiple()
        public
        assertInvariants
    {
        createNodeOperator();
        createNodeOperator();
        createNodeOperator();

        uint256 activeCount = module.getActiveNodeOperatorsCount();

        assertEq(activeCount, 3);
    }

    function test_getNodeOperatorTotalDepositedKeys() public assertInvariants {
        uint256 noId = createNodeOperator();

        uint256 depositedCount = module.getNodeOperatorTotalDepositedKeys(noId);
        assertEq(depositedCount, 0);

        module.obtainDepositData(1, "");

        depositedCount = module.getNodeOperatorTotalDepositedKeys(noId);
        assertEq(depositedCount, 1);
    }

    function test_getNodeOperatorManagementProperties()
        public
        assertInvariants
    {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = true;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        NodeOperatorManagementProperties memory props = module
            .getNodeOperatorManagementProperties(noId);
        assertEq(props.managerAddress, manager);
        assertEq(props.rewardAddress, reward);
        assertEq(props.extendedManagerPermissions, extended);
    }

    function test_getNodeOperatorOwner() public assertInvariants {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = false;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        assertEq(module.getNodeOperatorOwner(noId), reward);
    }

    function test_getNodeOperatorOwner_ExtendedPermissions()
        public
        assertInvariants
    {
        address manager = nextAddress();
        address reward = nextAddress();
        bool extended = true;

        uint256 noId = module.createNodeOperator(
            manager,
            NodeOperatorManagementProperties({
                managerAddress: manager,
                rewardAddress: reward,
                extendedManagerPermissions: extended
            }),
            address(0)
        );

        assertEq(module.getNodeOperatorOwner(noId), manager);
    }
}

abstract contract ModuleExitDeadlineThreshold is ModuleFixtures {
    function test_exitDeadlineThreshold() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        assertEq(exitDeadlineThreshold, parametersRegistry.allowedExitDelay());
    }

    function test_exitDeadlineThreshold_RevertWhenNoNodeOperator()
        public
        assertInvariants
    {
        uint256 noId = 0;
        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.exitDeadlineThreshold(noId);
    }
}

abstract contract ModuleIsValidatorExitDelayPenaltyApplicable is
    ModuleFixtures
{
    function test_isValidatorExitDelayPenaltyApplicable_notApplicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(false);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                ICSExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable);
    }

    function test_isValidatorExitDelayPenaltyApplicable_applicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(true);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                ICSExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
        assertTrue(applicable);
    }
}

abstract contract ModuleReportValidatorExitDelay is ModuleFixtures {
    function test_reportValidatorExitDelay() public {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                ICSExitPenalties.processExitDelayReport.selector,
                noId,
                publicKey,
                exitDeadlineThreshold
            )
        );
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDeadlineThreshold
        );
    }

    function test_reportValidatorExitDelay_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 exitDelay = parametersRegistry.allowedExitDelay();

        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDelay
        );
    }
}

abstract contract ModuleOnValidatorExitTriggered is ModuleFixtures {
    function test_onValidatorExitTriggered() public assertInvariants {
        uint256 noId = createNodeOperator();
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                ICSExitPenalties.processTriggeredExit.selector,
                noId,
                publicKey,
                paidFee,
                exitType
            )
        );
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
    }

    function test_onValidatorExitTriggered_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectRevert(ICSModule.NodeOperatorDoesNotExist.selector);
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
    }
}

abstract contract ModuleCreateNodeOperators is ModuleFixtures {
    function createMultipleOperatorsWithKeysETH(
        uint256 operators,
        uint256 keysCount,
        address managerAddress
    ) external payable {
        for (uint256 i; i < operators; i++) {
            uint256 noId = module.createNodeOperator(
                managerAddress,
                NodeOperatorManagementProperties({
                    managerAddress: address(0),
                    rewardAddress: address(0),
                    extendedManagerPermissions: false
                }),
                address(0)
            );
            uint256 amount = module.accounting().getRequiredBondForNextKeys(
                noId,
                keysCount
            );
            (bytes memory keys, bytes memory signatures) = keysSignatures(
                keysCount
            );
            module.addValidatorKeysETH{ value: amount }(
                managerAddress,
                noId,
                keysCount,
                keys,
                signatures
            );
        }
    }
}
