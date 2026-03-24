// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStakingModuleV2 } from "src/interfaces/IStakingModule.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IBaseModule, NodeOperator } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { Vm } from "forge-std/Vm.sol";

import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";
import { StakingRouterIntegrationTestBase } from "../common/StakingRouter.t.sol";

contract StakingRouterIntegrationTestCSM0x02 is StakingRouterIntegrationTestBase, CSM0x02IntegrationBase {
    uint256 internal constant KEY_BALANCE_CAP =
        ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE - ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;
    uint256 internal constant TOP_UP_ALLOCATION_PROBE_AMOUNT = 100_000 ether;

    address internal topUpGateway;

    function setUp() public override {
        super.setUp();
        if (!isStakingRouterUpgraded) {
            // Skip: this suite depends on router/core v2 APIs and is not executable on the old router version.
            vm.skip(true, "Suite requires upgraded staking router version for router/core v2 APIs");
        }

        topUpGateway = locator.topUpGateway();
        module.grantRole(module.VERIFIER_ROLE(), address(this));
        module.grantRole(module.REWIND_TOP_UP_QUEUE_ROLE(), address(this));

        _maximizeModuleShare(moduleId);
        _disableDepositsForOtherModules(moduleId);
        hugeDeposit();
        _ensureStakingRouterCanDeposit(moduleId);
    }

    function test_routerDeposit_happyPath_callsObtainDepositDataAndUsesReturnedCount() public assertInvariants {
        (uint256 noId, ) = integrationHelpers.getDepositableNodeOperator(nextAddress());
        NodeOperator memory noBefore = module.getNodeOperator(noId);
        assertGt(noBefore.depositableValidatorsCount, 0);

        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();

        uint256 requestedDeposits = _getExpectedRouterDepositRequestCount();
        assertGt(requestedDeposits, 0);
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(module.obtainDepositData.selector, requestedDeposits, "")
        );
        vm.prank(locator.depositSecurityModule());
        stakingRouter.deposit(moduleId, "");

        (, uint256 depositedAfter, ) = module.getStakingModuleSummary();
        uint256 actualDeposits = depositedAfter - depositedBefore;
        assertEq(depositedAfter - depositedBefore, actualDeposits);
        assertEq(actualDeposits, requestedDeposits);

        NodeOperator memory noAfter = module.getNodeOperator(noId);
        uint256 depositedDelta = noAfter.totalDepositedKeys - noBefore.totalDepositedKeys;
        uint256 depositableDelta = noBefore.depositableValidatorsCount - noAfter.depositableValidatorsCount;
        assertGt(depositedDelta, 0);
        assertEq(depositedDelta, depositableDelta);
    }

    function test_routerTopUp_callsAllocateDeposits() public assertInvariants {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        (uint256 expectedMaxDepositAmount, ) = stakingRouter.getTopUpAllocation(TOP_UP_ALLOCATION_PROBE_AMOUNT);
        uint256 nonceBefore = module.getNonce();

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, 1 ether);

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                IStakingModuleV2.allocateDeposits.selector,
                expectedMaxDepositAmount,
                pubkeys,
                keyIndices,
                operatorIds,
                topUpLimits
            )
        );

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        assertEq(module.getNonce(), nonceBefore + 1);
    }

    function test_routerTopUp_updatesKeyAllocatedBalance() public assertInvariants {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        uint256 topUpLimit = 1 ether;
        (uint256 expectedMaxDepositAmount, ) = stakingRouter.getTopUpAllocation(TOP_UP_ALLOCATION_PROBE_AMOUNT);
        uint256 keyAllocatedBalanceBefore = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        uint256 remainingCapacity = _remainingTopUpCapacity(noId, keyIndex);
        uint256 cappedLimit = topUpLimit < remainingCapacity ? topUpLimit : remainingCapacity;
        uint256 expectedAllocation = expectedMaxDepositAmount < cappedLimit ? expectedMaxDepositAmount : cappedLimit;

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, topUpLimit);

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        uint256 keyAllocatedBalanceAfter = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        assertEq(keyAllocatedBalanceAfter - keyAllocatedBalanceBefore, expectedAllocation);
    }

    function test_routerTopUp_fullTopUpDequeuesOneQueueItem() public assertInvariants {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        uint256 topUpLimit = 1;
        (uint256 expectedMaxDepositAmount, ) = stakingRouter.getTopUpAllocation(TOP_UP_ALLOCATION_PROBE_AMOUNT);
        assertGt(expectedMaxDepositAmount, 0);

        (, , uint256 queueLengthBefore, ) = module.getTopUpQueue();
        assertGt(queueLengthBefore, 0);

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, topUpLimit);

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        (, , uint256 queueLengthAfter, ) = module.getTopUpQueue();
        assertEq(queueLengthAfter + 1, queueLengthBefore);
    }

    function test_routerTopUp_queueLimitUtilization_unblocksSingleDepositSlot() public assertInvariants {
        uint256 appliedLimit = _forceTopUpQueueOneFreeSlot();
        uint256 depositedAfterFirst = _depositOneThroughRouterAndAssertRequestedOne();

        (, , uint256 queueLengthAfterFirst, ) = module.getTopUpQueue();
        assertEq(queueLengthAfterFirst, appliedLimit);

        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );
        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, 1 ether);

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

        (, , uint256 queueLengthAfterTopUp, ) = module.getTopUpQueue();
        assertEq(queueLengthAfterTopUp + 1, queueLengthAfterFirst);

        uint256 depositedAfterSecond = _depositOneThroughRouterAndAssertRequestedOne();
        assertEq(depositedAfterSecond, depositedAfterFirst + 1);

        (, , uint256 queueLengthAfterSecond, ) = module.getTopUpQueue();
        assertEq(queueLengthAfterSecond, appliedLimit);
    }

    function test_routerTopUp_revertsOnInvalidSigningKey() public {
        (uint256 noId, uint256 keyIndex, ) = integrationHelpers.getDepositableTopUpNodeOperator(nextAddress());
        bytes memory invalidPubkey = new bytes(48);
        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, invalidPubkey, 1 ether);

        vm.expectRevert(SigningKeys.InvalidSigningKey.selector);
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);
    }

    function test_routerTopUp_revertsOnInvalidTopUpOrder() public {
        (uint256 queueNoId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(queueNoId + 1, keyIndex, pubkey, 1 ether);

        vm.expectRevert(ICSModule.InvalidTopUpOrder.selector);
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);
    }

    function test_routerTopUp_revertsOnUnexpectedExtraKey() public {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );

        uint256 remainingCapacity = _remainingTopUpCapacity(noId, keyIndex);
        assertGt(remainingCapacity, 0);

        uint256 topUpLimit = remainingCapacity + 1 ether;
        uint256 mockedDepositableEther = remainingCapacity > 1 ether ? remainingCapacity - 1 ether : 0;
        vm.mockCall(
            address(lido),
            abi.encodeWithSelector(lido.getDepositableEther.selector),
            abi.encode(mockedDepositableEther)
        );

        uint256[] memory keyIndices = new uint256[](2);
        keyIndices[0] = keyIndex;
        keyIndices[1] = keyIndex;

        uint256[] memory operatorIds = new uint256[](2);
        operatorIds[0] = noId;
        operatorIds[1] = noId;

        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = pubkey;
        pubkeys[1] = pubkey;

        uint256[] memory topUpLimits = new uint256[](2);
        topUpLimits[0] = topUpLimit;
        topUpLimits[1] = topUpLimit;

        vm.expectRevert(ICSModule.UnexpectedExtraKey.selector);
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);
    }

    function test_routerTopUp_deepRewind_noAllocationForFullyToppedKey() public assertInvariants {
        (
            uint256[] memory noIds,
            uint256[] memory keyIdxs,
            bytes[] memory pubs,
            uint256 checkedAt
        ) = _topUpAndDeepRewind(type(uint256).max);

        uint256 keyAllocatedBalanceBefore = module.getKeyAllocatedBalances(noIds[checkedAt], keyIdxs[checkedAt], 1)[0];
        assertEq(_remainingTopUpCapacity(noIds[checkedAt], keyIdxs[checkedAt]), 0);

        (, , uint256 queueLengthBefore, ) = module.getTopUpQueue();

        uint256[] memory topUpLimits = new uint256[](noIds.length);
        for (uint256 i; i < noIds.length; i++) {
            topUpLimits[i] = 1 ether;
        }

        vm.recordLogs();
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIdxs, noIds, pubs, topUpLimits);

        assertEq(_countKeyAllocatedBalanceChangedEvents(), 0);
        assertEq(module.getKeyAllocatedBalances(noIds[checkedAt], keyIdxs[checkedAt], 1)[0], keyAllocatedBalanceBefore);
        (, , uint256 queueLengthAfter, ) = module.getTopUpQueue();
        assertEq(queueLengthAfter + noIds.length, queueLengthBefore);
    }

    function test_routerTopUp_deepRewind_continuesToppedUpKeyToFullCap() public assertInvariants {
        (
            uint256[] memory noIds,
            uint256[] memory keyIdxs,
            bytes[] memory pubs,
            uint256 checkedAt
        ) = _topUpAndDeepRewind(1 ether);

        uint256 keyAllocatedBalanceBefore = module.getKeyAllocatedBalances(noIds[checkedAt], keyIdxs[checkedAt], 1)[0];
        uint256 remainingCapacity = _remainingTopUpCapacity(noIds[checkedAt], keyIdxs[checkedAt]);
        assertGt(remainingCapacity, 0);

        (, , uint256 queueLengthBefore, ) = module.getTopUpQueue();

        uint256[] memory topUpLimits = new uint256[](noIds.length);
        for (uint256 i; i < noIds.length; i++) {
            topUpLimits[i] = (i == checkedAt) ? remainingCapacity : 1 ether;
        }

        vm.recordLogs();
        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIdxs, noIds, pubs, topUpLimits);

        assertEq(_countKeyAllocatedBalanceChangedEvents(), 1);
        assertEq(
            module.getKeyAllocatedBalances(noIds[checkedAt], keyIdxs[checkedAt], 1)[0],
            keyAllocatedBalanceBefore + remainingCapacity
        );
        (, , uint256 queueLengthAfter, ) = module.getTopUpQueue();
        assertEq(queueLengthAfter + noIds.length, queueLengthBefore);
    }

    uint256 internal constant DEEP_REWIND_CAP = 128;

    /// @dev Tops up one queue item with the given `topUpLimit`, then deep-rewinds up to
    ///      `DEEP_REWIND_CAP` positions back, covering pre-existing topped-up items in the module.
    ///      Returns arrays for all items from the rewind target through the topped-up item,
    ///      and the index of the explicitly topped-up item.
    function _topUpAndDeepRewind(
        uint256 topUpLimit
    ) internal returns (uint256[] memory noIds, uint256[] memory keyIdxs, bytes[] memory pubs, uint256 checkedAt) {
        (, , , uint256 initialHead) = module.getTopUpQueue();

        _topUpHeadItem(topUpLimit);

        // Deep rewind up to DEEP_REWIND_CAP positions back, capped at position 0
        uint256 rewindTo = initialHead < DEEP_REWIND_CAP ? 0 : initialHead + 1 - DEEP_REWIND_CAP;
        module.rewindTopUpQueue(rewindTo);

        // Read all items from rewindTo through the topped-up item
        uint256 totalCount = initialHead + 1 - rewindTo;
        checkedAt = totalCount - 1;
        noIds = new uint256[](totalCount);
        keyIdxs = new uint256[](totalCount);
        pubs = new bytes[](totalCount);

        for (uint256 i; i < totalCount; i++) {
            (noIds[i], keyIdxs[i]) = module.getTopUpQueueItem(i);
            pubs[i] = module.getSigningKeys(noIds[i], keyIdxs[i], 1);
        }
    }

    /// @dev Tops up the current head item of the top-up queue with the given limit.
    function _topUpHeadItem(uint256 topUpLimit) internal {
        (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
            nextAddress()
        );
        uint256 remaining = _remainingTopUpCapacity(noId, keyIndex);
        uint256 limit = topUpLimit < remaining ? topUpLimit : remaining;

        (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        ) = _singleTopUpArrays(noId, keyIndex, pubkey, limit);

        vm.prank(topUpGateway);
        stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);
    }

    function _countKeyAllocatedBalanceChangedEvents() internal returns (uint256 count) {
        bytes32 topic = IBaseModule.KeyAllocatedBalanceChanged.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) count++;
        }
    }

    function _remainingTopUpCapacity(uint256 noId, uint256 keyIndex) internal view returns (uint256) {
        uint256 keyAllocatedBalance = module.getKeyAllocatedBalances(noId, keyIndex, 1)[0];
        if (keyAllocatedBalance >= KEY_BALANCE_CAP) return 0;
        return KEY_BALANCE_CAP - keyAllocatedBalance;
    }

    function _forceTopUpQueueOneFreeSlot() internal returns (uint256 appliedLimit) {
        integrationHelpers.getDepositableNodeOperator(nextAddress());

        bool enabled;
        uint256 queueLimit;
        uint256 queueLengthBefore;
        (enabled, queueLimit, queueLengthBefore, ) = module.getTopUpQueue();
        assertTrue(enabled);

        if (queueLengthBefore == type(uint8).max) {
            (uint256 noId, uint256 keyIndex, bytes memory pubkey) = integrationHelpers.getDepositableTopUpNodeOperator(
                nextAddress()
            );
            (
                uint256[] memory keyIndices,
                uint256[] memory operatorIds,
                bytes[] memory pubkeys,
                uint256[] memory topUpLimits
            ) = _singleTopUpArrays(noId, keyIndex, pubkey, 1 ether);

            vm.prank(topUpGateway);
            stakingRouter.topUp(moduleId, keyIndices, operatorIds, pubkeys, topUpLimits);

            (, queueLimit, queueLengthBefore, ) = module.getTopUpQueue();
        }

        uint256 targetLimit = queueLengthBefore + 1;
        if (queueLimit != targetLimit) {
            if (!module.hasRole(module.MANAGE_TOP_UP_QUEUE_ROLE(), address(this))) {
                module.grantRole(module.MANAGE_TOP_UP_QUEUE_ROLE(), address(this));
            }
            module.setTopUpQueueLimit(targetLimit);
        }

        uint256 queueLengthStart;
        (, appliedLimit, queueLengthStart, ) = module.getTopUpQueue();
        assertEq(appliedLimit, targetLimit);
        assertEq(queueLengthStart + 1, appliedLimit);
    }

    function _depositOneThroughRouterAndAssertRequestedOne() internal returns (uint256 depositedAfter) {
        (, uint256 depositedBefore, ) = module.getStakingModuleSummary();
        uint256 requestedDeposits = _getExpectedRouterDepositRequestCount();
        assertEq(requestedDeposits, 1);
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(module.obtainDepositData.selector, requestedDeposits, "")
        );
        vm.prank(locator.depositSecurityModule());
        stakingRouter.deposit(moduleId, "");
        (, depositedAfter, ) = module.getStakingModuleSummary();
        assertEq(depositedAfter, depositedBefore + 1);
    }

    function _singleTopUpArrays(
        uint256 noId,
        uint256 keyIndex,
        bytes memory pubkey,
        uint256 topUpLimit
    )
        internal
        pure
        returns (
            uint256[] memory keyIndices,
            uint256[] memory operatorIds,
            bytes[] memory pubkeys,
            uint256[] memory topUpLimits
        )
    {
        keyIndices = new uint256[](1);
        keyIndices[0] = keyIndex;

        operatorIds = new uint256[](1);
        operatorIds[0] = noId;

        pubkeys = new bytes[](1);
        pubkeys[0] = pubkey;

        topUpLimits = new uint256[](1);
        topUpLimits[0] = topUpLimit;
    }
}
