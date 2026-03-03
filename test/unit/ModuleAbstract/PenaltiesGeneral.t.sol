// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Test.sol";

import { BondLock } from "src/abstract/BondLock.sol";
import { IBaseModule, NodeOperator } from "src/interfaces/IBaseModule.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleReportGeneralDelayedPenalty is ModuleFixtures {
    function test_reportGeneralDelayedPenalty_HappyPath() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();
        uint256 fine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyReported(
            noId,
            bytes32(abi.encode(1)),
            BOND_SIZE / 2,
            fine,
            "Test penalty"
        );
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, BOND_SIZE / 2 + module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0));
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_NoNodeOperator() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportGeneralDelayedPenalty(0, bytes32(abi.encode(1)), 1 ether, "Test penalty");
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_ZeroAmountAndZeroAdditionalFine() public {
        uint256 noId = createNodeOperator();
        module.PARAMETERS_REGISTRY().setGeneralDelayedPenaltyAdditionalFine(0, 0);
        vm.expectRevert(IBaseModule.InvalidAmount.selector);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), 0 ether, "Test penalty");
    }

    function test_reportGeneralDelayedPenalty_ZeroAmountWithAdditionalFine() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 fine = 1 ether;

        module.PARAMETERS_REGISTRY().setGeneralDelayedPenaltyAdditionalFine(0, fine);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyReported(noId, bytes32(abi.encode(1)), 0, fine, "Test penalty");
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), 0, "Test penalty");

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, fine);
    }

    function test_reportGeneralDelayedPenalty_RevertWhen_ZeroPenaltyType() public {
        uint256 noId = createNodeOperator();
        vm.expectRevert(IBaseModule.ZeroPenaltyType.selector);
        module.reportGeneralDelayedPenalty(noId, bytes32(0), 0 ether, "Test penalty");
    }

    function test_reportGeneralDelayedPenalty_NoNonceChange() public assertInvariants {
        uint256 noId = createNodeOperator();

        vm.deal(nodeOperator, 32 ether);
        vm.prank(nodeOperator);
        accounting.depositETH{ value: 32 ether }(0);

        uint256 nonce = module.getNonce();

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        assertEq(module.getNonce(), nonce);
    }

    function test_reportGeneralDelayedPenalty_UpdatesDepositableAfterUnlock() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 nonce = module.getNonce();

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, BOND_SIZE / 2 + module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0));
        assertEq(module.getNonce(), nonce + 1);
        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 0);

        createNodeOperator();
        module.obtainDepositData(1, "");

        vm.warp(accounting.getBondLockPeriod() + 1);
        accounting.unlockExpiredLock(noId);

        no = module.getNodeOperator(noId);
        assertEq(no.depositableValidatorsCount, 1);
    }
}

abstract contract ModuleCancelGeneralDelayedPenalty is ModuleFixtures {
    function test_cancelGeneralDelayedPenalty_HappyPath() public assertInvariants {
        uint256 noId = createNodeOperator();

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyCancelled(
            noId,
            BOND_SIZE / 2 + module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0)
        );
        module.cancelGeneralDelayedPenalty(
            noId,
            BOND_SIZE / 2 + module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0)
        );

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_cancelGeneralDelayedPenalty_Partial() public assertInvariants {
        uint256 noId = createNodeOperator();

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        uint256 nonce = module.getNonce();

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyCancelled(noId, BOND_SIZE / 2);
        module.cancelGeneralDelayedPenalty(noId, BOND_SIZE / 2);

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0));
        // nonce should not change due to no changes in the depositable validators
        assertEq(module.getNonce(), nonce);
    }

    function test_cancelGeneralDelayedPenalty_ExpiredLock_depositableValidatorsChanged() public assertInvariants {
        uint256 noId = createNodeOperator(5);

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), BOND_SIZE / 2, "Test penalty");

        uint256 nonce = module.getNonce();
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1 seconds);

        module.cancelGeneralDelayedPenalty(noId, BOND_SIZE / 2);

        uint256 lockedBond = accounting.getLockedBond(noId);
        assertEq(lockedBond, 0);
        assertEq(module.getNonce(), nonce + 1);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 5);
    }

    function test_cancelGeneralDelayedPenalty_RevertWhen_NoNodeOperator() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.cancelGeneralDelayedPenalty(0, 1 ether);
    }
}

abstract contract ModuleSettleGeneralDelayedPenaltyBasic is ModuleFixtures {
    function test_settleGeneralDelayedPenalty() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        uint256 amount = 1 ether;
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(noId, lock.amount);
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));

        lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetValidatorsCount, 0, "targetValidatorsCount mismatch");
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(summary.depositableValidatorsCount, 2, "depositableValidatorsCount mismatch");
    }

    function test_settleGeneralDelayedPenalty_revertWhen_InvalidInput() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        vm.expectRevert(IBaseModule.InvalidInput.selector);
        module.settleGeneralDelayedPenalty(idsToSettle, new uint256[](0));
    }

    function test_settleGeneralDelayedPenalty_lockedGreaterThanAllowedToSettle() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        uint256 amount = 1 ether;
        uint256[] memory idsToSettle = new uint256[](1);
        idsToSettle[0] = noId;
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary.depositableValidatorsCount;

        module.settleGeneralDelayedPenalty(idsToSettle, UintArr(amount));
        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0));
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetValidatorsCount, 0, "targetValidatorsCount mismatch");
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(summary.depositableValidatorsCount, 2, "depositableValidatorsCount mismatch");
    }

    function test_settleGeneralDelayedPenalty_multipleNOs() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        module.reportGeneralDelayedPenalty(firstNoId, bytes32(abi.encode(1)), 1 ether, "Test penalty");
        module.reportGeneralDelayedPenalty(secondNoId, bytes32(abi.encode(1)), BOND_SIZE, "Test penalty");

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(firstNoId);
        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(secondNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(firstNoId, firstLock.amount);
        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(secondNoId, secondLock.amount);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        firstLock = accounting.getLockedBondInfo(firstNoId);
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);

        secondLock = accounting.getLockedBondInfo(secondNoId);
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneWithLockedGreaterThanAllowedToSettle()
        public
        assertInvariants
    {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](2);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        uint256 amount = 1 ether;
        module.reportGeneralDelayedPenalty(firstNoId, bytes32(abi.encode(1)), amount, "Test penalty");
        module.reportGeneralDelayedPenalty(secondNoId, bytes32(abi.encode(1)), BOND_SIZE, "Test penalty");

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(firstNoId);
        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(secondNoId);
        uint256 firstRemainingLock = firstLock.amount - amount;

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(firstNoId, amount);
        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(secondNoId, secondLock.amount);
        module.settleGeneralDelayedPenalty(idsToSettle, UintArr(amount, type(uint256).max));

        firstLock = accounting.getLockedBondInfo(firstNoId);
        assertEq(firstLock.amount, firstRemainingLock);
        assertEq(firstLock.until, accounting.getBondLockPeriod() + block.timestamp);

        secondLock = accounting.getLockedBondInfo(secondNoId);
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_NoLock() public assertInvariants {
        uint256 noId = createNodeOperator();
        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary.depositableValidatorsCount;

        vm.recordLogs();
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetValidatorsCount, 0, "targetValidatorsCount mismatch");
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleGeneralDelayedPenalty_MaxAmountIsZero() public assertInvariants {
        uint256 noId = createNodeOperator();

        uint256 amount = 1 ether;
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        NodeOperatorSummary memory summary = getNodeOperatorSummary(noId);
        uint256 depositableValidatorsCountBefore = summary.depositableValidatorsCount;

        vm.recordLogs();
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, amount + module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0));
        assertEq(lock.until, accounting.getBondLockPeriod() + block.timestamp);

        // If there is nothing to settle, the targetLimitMode should be 0
        summary = getNodeOperatorSummary(noId);
        assertEq(summary.targetValidatorsCount, 0, "targetValidatorsCount mismatch");
        assertEq(summary.targetLimitMode, 0, "targetLimitMode mismatch");
        assertEq(
            summary.depositableValidatorsCount,
            depositableValidatorsCountBefore,
            "depositableValidatorsCount should not change"
        );
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_NoLock() public assertInvariants {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(firstNoId);
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(secondNoId);
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneWithNoLock() public {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();

        module.reportGeneralDelayedPenalty(secondNoId, bytes32(abi.encode(1)), 1 ether, "Test penalty");

        BondLock.BondLockData memory secondLock = accounting.getLockedBondInfo(secondNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(secondNoId, secondLock.amount);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        BondLock.BondLockData memory firstLock = accounting.getLockedBondInfo(firstNoId);
        assertEq(firstLock.amount, 0 ether);
        assertEq(firstLock.until, 0);
        secondLock = accounting.getLockedBondInfo(secondNoId);
        assertEq(secondLock.amount, 0 ether);
        assertEq(secondLock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_withDuplicates() public {
        uint256 firstNoId = createNodeOperator();
        uint256 secondNoId = createNodeOperator();
        uint256[] memory idsToSettle = new uint256[](3);
        idsToSettle[0] = firstNoId;
        idsToSettle[1] = secondNoId;
        idsToSettle[2] = secondNoId;

        uint256 bondBalanceBefore = accounting.getBond(secondNoId);

        uint256 lockAmount = 1 ether;
        module.reportGeneralDelayedPenalty(secondNoId, bytes32(abi.encode(1)), lockAmount, "Test penalty");

        BondLock.BondLockData memory currentLock = accounting.getLockedBondInfo(secondNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(secondNoId, currentLock.amount);
        module.settleGeneralDelayedPenalty(
            idsToSettle,
            UintArr(type(uint256).max, type(uint256).max, type(uint256).max)
        );

        uint256 bondBalanceAfter = accounting.getBond(secondNoId);

        currentLock = accounting.getLockedBondInfo(secondNoId);
        assertEq(currentLock.amount, 0 ether);
        assertEq(currentLock.until, 0);
        assertEq(
            bondBalanceAfter,
            bondBalanceBefore - lockAmount - module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0)
        );
    }

    function test_settleGeneralDelayedPenalty_RevertWhen_NoExistingNodeOperator() public {
        uint256 noId = createNodeOperator();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.settleGeneralDelayedPenalty(UintArr(noId + 1), UintArr(type(uint256).max));
    }
}

abstract contract ModuleSettleGeneralDelayedPenaltyAdvanced is ModuleFixtures {
    function test_settleGeneralDelayedPenalty_PeriodIsExpired_depositableValidatorsChanged() public {
        uint256 noId = createNodeOperator(5);
        uint256 period = accounting.getBondLockPeriod();
        uint256 amount = 1 ether;

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        uint256 nonce = module.getNonce();

        vm.warp(block.timestamp + period + 1 seconds);

        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));

        assertEq(accounting.getLockedBond(noId), 0);
        assertEq(module.getNodeOperator(noId).depositableValidatorsCount, 5);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_settleGeneralDelayedPenalty_multipleNOs_oneExpired() public {
        uint256 period = accounting.getBondLockPeriod();
        uint256 firstNoId = createNodeOperator(2);
        uint256 secondNoId = createNodeOperator(2);
        module.reportGeneralDelayedPenalty(firstNoId, bytes32(abi.encode(1)), 1 ether, "Test penalty");
        vm.warp(block.timestamp + period + 1 seconds);
        module.reportGeneralDelayedPenalty(secondNoId, bytes32(abi.encode(1)), BOND_SIZE, "Test penalty");

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(secondNoId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(secondNoId, lock.amount);
        module.settleGeneralDelayedPenalty(
            UintArr(firstNoId, secondNoId),
            UintArr(type(uint256).max, type(uint256).max)
        );

        assertEq(accounting.getLockedBond(firstNoId), 0);

        lock = accounting.getLockedBondInfo(secondNoId);
        assertEq(lock.amount, 0 ether);
        assertEq(lock.until, 0);
    }

    function test_settleGeneralDelayedPenalty_NoBond() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = accounting.getBond(noId) + 1 ether;

        // penalize all current bond to make an edge case when there is no bond but a new lock is applied
        penalize(noId, amount);

        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltySettled(noId, lock.amount);
        module.settleGeneralDelayedPenalty(UintArr(noId), UintArr(type(uint256).max));
    }
}

abstract contract ModuleCompensateGeneralDelayedPenalty is ModuleFixtures {
    function test_compensateGeneralDelayedPenalty() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        uint256 nonce = module.getNonce();

        addBond(noId, amount + fine);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyCompensated(noId, amount + fine);

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.compensateLockedBond.selector, noId));
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty(noId);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_compensateGeneralDelayedPenalty_Partial() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 amount = 1 ether;
        uint256 fine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        uint256 nonce = module.getNonce();

        addBond(noId, amount);

        vm.expectEmit(address(module));
        emit IBaseModule.GeneralDelayedPenaltyCompensated(noId, amount);

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.compensateLockedBond.selector, noId));
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty(noId);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, fine);
        assertEq(module.getNonce(), nonce);
    }

    function test_compensateGeneralDelayedPenalty_NothingCompensatedDueToNoLock() public assertInvariants {
        uint256 noId = createNodeOperator();

        uint256 nonce = module.getNonce();

        vm.recordLogs();
        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty(noId);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0);
        assertEq(module.getNonce(), nonce);
    }

    function test_compensateGeneralDelayedPenalty_NothingCompensatedDueToLockExpiry_depositableValidatorsChanged()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(5);
        uint256 amount = 1 ether;
        uint256 fine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");

        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableBefore, 4);

        uint256 nonce = module.getNonce();

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1);

        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty(noId);

        BondLock.BondLockData memory lock = accounting.getLockedBondInfo(noId);
        assertEq(lock.amount, 0);
        assertEq(module.getNonce(), nonce + 1);

        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, 5);
    }

    function test_compensateGeneralDelayedPenalty_depositableValidatorsChanged() public {
        uint256 noId = createNodeOperator(2);
        uint256 amount = 1 ether;
        uint256 fine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(0);
        module.reportGeneralDelayedPenalty(noId, bytes32(abi.encode(1)), amount, "Test penalty");
        module.obtainDepositData(1, "");
        uint256 depositableBefore = module.getNodeOperator(noId).depositableValidatorsCount;

        addBond(noId, amount + fine);

        vm.prank(nodeOperator);
        module.compensateGeneralDelayedPenalty(noId);
        uint256 depositableAfter = module.getNodeOperator(noId).depositableValidatorsCount;
        assertEq(depositableAfter, depositableBefore + 1);
    }

    function test_compensateGeneralDelayedPenalty_RevertWhen_NoNodeOperator() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.compensateGeneralDelayedPenalty(0);
    }

    function test_compensateGeneralDelayedPenalty_RevertWhen_NotManager() public {
        uint256 noId = createNodeOperator();
        vm.expectRevert(IBaseModule.SenderIsNotEligible.selector);
        module.compensateGeneralDelayedPenalty(noId);
    }
}
