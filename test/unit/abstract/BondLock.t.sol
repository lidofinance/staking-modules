// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test, Vm } from "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BondLock } from "src/abstract/BondLock.sol";
import { IBondLock } from "src/interfaces/IBondLock.sol";

contract BondLockTestable is BondLock(4 weeks, 365 days) {
    function initialize(uint256 period) public initializer {
        BondLock.__BondLock_init(period);
    }

    function setBondLockPeriod(uint256 period) external {
        _setBondLockPeriod(period);
    }

    function lock(uint256 nodeOperatorId, uint256 amount) external {
        _lock(nodeOperatorId, amount);
    }

    function unlock(uint256 nodeOperatorId, uint256 amount) external {
        _unlock(nodeOperatorId, amount);
    }

    function remove(uint256 nodeOperatorId) external {
        _changeBondLock(nodeOperatorId, 0, 0);
    }
}

contract BondLockTest is Test {
    BondLockTestable public bondLock;

    function setUp() public {
        bondLock = new BondLockTestable();
        bondLock.initialize(8 weeks);
    }

    function test_setBondLockPeriod() public {
        uint256 period = 4 weeks;

        vm.expectEmit(address(bondLock));
        emit IBondLock.BondLockPeriodChanged(period);

        bondLock.setBondLockPeriod(period);

        uint256 _period = bondLock.getBondLockPeriod();
        assertEq(_period, period);
    }

    function test_setBondLockPeriod_samePeriodNoEvent() public {
        uint256 period = bondLock.getBondLockPeriod();

        vm.recordLogs();

        bondLock.setBondLockPeriod(period);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        uint256 _period = bondLock.getBondLockPeriod();
        assertEq(_period, period);
    }

    function test_setBondLockPeriod_RevertWhen_LessThanMin() public {
        uint256 min = bondLock.MIN_BOND_LOCK_PERIOD();
        vm.expectRevert(IBondLock.InvalidBondLockPeriod.selector);
        bondLock.setBondLockPeriod(min - 1 seconds);
    }

    function test_setBondLockPeriod_RevertWhen_GreaterThanMax() public {
        uint256 max = bondLock.MAX_BOND_LOCK_PERIOD();
        vm.expectRevert(IBondLock.InvalidBondLockPeriod.selector);
        bondLock.setBondLockPeriod(max + 1 seconds);
    }

    function test_getActualLockedBond() public {
        uint256 noId = 0;
        uint256 amount = 1 ether;
        bondLock.lock(noId, amount);

        uint256 value = bondLock.getActualLockedBond(noId);
        assertEq(value, amount);
    }

    function test_getActualLockedBond_WhenOnUntil() public {
        uint256 noId = 0;
        uint256 amount = 1 ether;
        bondLock.lock(noId, amount);

        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        vm.warp(lock.until);

        uint256 value = bondLock.getActualLockedBond(noId);
        assertEq(value, 0);
    }

    function test_getActualLockedBond_WhenPeriodIsPassed() public {
        uint256 period = bondLock.getBondLockPeriod();
        uint256 noId = 0;
        uint256 amount = 1 ether;
        bondLock.lock(noId, amount);

        vm.warp(block.timestamp + period + 1 seconds);

        uint256 value = bondLock.getActualLockedBond(noId);
        assertEq(value, 0);
    }

    function test_lock() public {
        uint256 period = bondLock.getBondLockPeriod();
        uint256 noId = 0;
        uint256 amount = 1 ether;
        uint256 until = block.timestamp + period;

        vm.expectEmit(address(bondLock));
        emit IBondLock.BondLockChanged(noId, amount, until);

        bondLock.lock(noId, amount);

        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        assertEq(lock.amount, amount);
        assertEq(lock.until, until);
    }

    function test_lock_secondLock() public {
        uint256 noId = 0;

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lockBefore = bondLock.getLockedBondInfo(
            noId
        );
        vm.warp(block.timestamp + 1 hours);

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        assertEq(lock.amount, 2 ether);
        assertEq(lock.until, lockBefore.until + 1 hours);
    }

    function test_lock_WhenSecondLockOnUntil() public {
        uint256 noId = 0;
        uint256 period = bondLock.getBondLockPeriod();

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lockBefore = bondLock.getLockedBondInfo(
            noId
        );
        vm.warp(lockBefore.until);

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        assertEq(lock.amount, 1 ether);
        assertEq(lock.until, lockBefore.until + period);
    }

    function test_lock_WhenSecondLockAfterFirstExpired() public {
        uint256 noId = 0;
        uint256 period = bondLock.getBondLockPeriod();

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lockBefore = bondLock.getLockedBondInfo(
            noId
        );
        vm.warp(lockBefore.until + 1 hours);

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        assertEq(lock.amount, 1 ether);
        assertEq(lock.until, block.timestamp + period);
    }

    function test_lock_secondLockWithShorterPeriod_keepsPreviousUntil() public {
        uint256 noId = 0;

        bondLock.lock(noId, 1 ether);
        BondLock.BondLockData memory lockBefore = bondLock.getLockedBondInfo(
            noId
        );

        bondLock.setBondLockPeriod(4 weeks);

        vm.warp(block.timestamp + 1 days);

        bondLock.lock(noId, 2 ether);
        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(noId);
        assertEq(lock.amount, 3 ether);
        assertEq(lock.until, lockBefore.until);
    }

    function test_lock_RevertWhen_ZeroAmount() public {
        vm.expectRevert(IBondLock.InvalidBondLockAmount.selector);
        bondLock.lock(0, 0);
    }

    function test_lock_RevertWhen_AmountExceedsMax() public {
        uint256 lock = uint256(type(uint128).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                128,
                lock
            )
        );
        bondLock.lock(0, lock);
    }

    function test_unlock_WhenFull() public {
        uint256 noId = 0;
        uint256 amount = 100 ether;

        bondLock.lock(noId, amount);

        vm.expectEmit(address(bondLock));
        emit IBondLock.BondLockRemoved(noId);

        bondLock.unlock(noId, amount);

        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(0);
        assertEq(lock.amount, 0);
        assertEq(lock.until, 0);
    }

    function test_unlock_WhenPartial() public {
        uint256 period = bondLock.getBondLockPeriod();
        uint256 noId = 0;
        uint256 amount = 100 ether;

        bondLock.lock(noId, amount);
        uint256 periodWhenLock = block.timestamp + period;

        uint256 toRelease = 10 ether;
        uint256 rest = amount - toRelease;

        vm.warp(block.timestamp + 1 seconds);

        vm.expectEmit(address(bondLock));
        emit IBondLock.BondLockChanged(noId, rest, periodWhenLock);

        bondLock.unlock(noId, toRelease);

        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(0);
        assertEq(lock.amount, rest);
        assertEq(lock.until, periodWhenLock);
    }

    function test_unlock_RevertWhen_ZeroAmount() public {
        vm.expectRevert(IBondLock.InvalidBondLockAmount.selector);
        bondLock.unlock(0, 0);
    }

    function test_unlock_RevertWhen_GreaterThanLock() public {
        uint256 noId = 0;
        uint256 amount = 100 ether;

        bondLock.lock(noId, amount);

        vm.expectRevert(IBondLock.InvalidBondLockAmount.selector);
        bondLock.unlock(noId, amount + 1 ether);
    }

    function test_remove() public {
        uint256 noId = 0;
        uint256 amount = 100 ether;

        bondLock.lock(noId, amount);

        vm.expectEmit(address(bondLock));
        emit IBondLock.BondLockRemoved(noId);

        bondLock.remove(noId);

        BondLock.BondLockData memory lock = bondLock.getLockedBondInfo(0);
        assertEq(lock.amount, 0);
        assertEq(lock.until, 0);
    }
}
