// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BondLockHarness } from "../../../certora/harnesses/BondLockHarness.sol";
import { IBondLock } from "../../../src/interfaces/IBondLock.sol";

/// @notice Concrete and fuzz witnesses for the Certora scene's success paths and edge cases.
/// @dev These tests validate the harness against production code; they are not formal proofs.
contract BondLockVerificationTest is Test {
    BondLockHarness internal target;

    function setUp() public {
        target = new BondLockHarness();
        target.initialize(1 days);
    }

    function testFuzz_liveLockAccumulatesAndDoesNotShortenDeadline(uint128 amount, uint128 extra, uint64 id) public {
        vm.assume(amount > 0 && extra > 0);
        vm.assume(uint256(amount) + extra <= type(uint128).max);

        target.lock(id, amount);
        uint256 until = target.lockUntil(id);
        target.setPeriod(1);
        vm.warp(block.timestamp + 1);
        target.lock(id, extra);

        assertEq(target.getLockedBond(id), uint256(amount) + extra);
        assertEq(target.lockUntil(id), until);
        assertEq(target.getBondLockNonce(id), 2);
    }

    function testFuzz_atExpiryNewLockReplacesOldAmount(uint128 amount, uint128 next, uint64 id) public {
        vm.assume(amount > 0 && next > 0);
        target.lock(id, amount);
        uint256 until = target.lockUntil(id);
        vm.warp(until);

        assertTrue(target.isLockExpired(id));
        assertEq(target.getLockedBond(id), amount);
        target.lock(id, next);

        assertEq(target.getLockedBond(id), next);
        assertEq(target.lockUntil(id), until + 1 days);
        assertEq(target.getBondLockNonce(id), 2);
    }

    function testFuzz_partialThenFullUnlockKeepsNonceAndClearsDeadline(uint128 amount, uint128 part, uint64 id) public {
        vm.assume(amount > 1);
        part = uint128(bound(part, 1, amount - 1));
        target.lock(id, amount);
        uint256 until = target.lockUntil(id);

        target.unlock(id, part);
        assertEq(target.getLockedBond(id), amount - part);
        assertEq(target.lockUntil(id), until);
        assertEq(target.getBondLockNonce(id), 1);

        target.unlock(id, amount - part);
        assertEq(target.getLockedBond(id), 0);
        assertEq(target.lockUntil(id), 0);
        assertEq(target.getBondLockNonce(id), 1);
        assertFalse(target.isLockExpired(id));
    }

    function testFuzz_expiredCleanupPreservesOtherOperatorAndNonce(uint128 amount, uint64 id) public {
        vm.assume(amount > 0);
        uint256 other = uint256(id) + 1;
        target.lock(id, amount);
        target.lock(other, 1);
        uint256 until = target.lockUntil(id);
        vm.warp(until);
        target.unlockExpired(id);

        assertEq(target.getLockedBond(id), 0);
        assertEq(target.lockUntil(id), 0);
        assertEq(target.getBondLockNonce(id), 1);
        assertEq(target.getLockedBond(other), 1);
        assertEq(target.lockUntil(other), until);
        assertEq(target.getBondLockNonce(other), 1);
    }

    function test_nonceWrapsModuloUint256() public {
        uint256 id = 7;
        // The nonce mapping is the third field of the production ERC-7201 BondLock namespace.
        bytes32 location = 0x78c5a36767279da056404c09083fca30cf3ea61c442cfaba6669f76a37393f00;
        bytes32 slot = keccak256(abi.encode(id, uint256(location) + 2));
        vm.store(address(target), slot, bytes32(type(uint256).max));

        target.lock(id, 1);

        assertEq(target.getBondLockNonce(id), 0);
        assertEq(target.getLockedBond(id), 1);
    }

    function test_cleanupBeforeExpiryRevertsAndAtExpirySucceeds() public {
        target.lock(0, 1);
        uint256 until = target.lockUntil(0);
        vm.warp(until - 1);
        vm.expectRevert(IBondLock.BondLockNotExpired.selector);
        target.unlockExpired(0);

        vm.warp(until);
        target.unlockExpired(0);
        assertEq(target.getLockedBond(0), 0);
    }

    function test_lockAndPeriodRepresentabilityBoundaries() public {
        target.setPeriod(type(uint64).max);
        target.lock(0, type(uint128).max);
        assertEq(target.getLockedBond(0), type(uint128).max);

        vm.expectRevert();
        target.lock(0, 1);
    }

    function test_initializationCannotRepeat() public {
        vm.expectRevert();
        target.initialize(1 days);
    }
}
