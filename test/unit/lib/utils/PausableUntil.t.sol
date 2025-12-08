// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { PausableUntil } from "src/lib/utils/PausableUntil.sol";

contract PausableUntilTest is Test {
    PausableUntilImpl pausable;

    function setUp() public {
        pausable = new PausableUntilImpl();
    }

    function test_PAUSE_INFINITELY() public view {
        assertEq(pausable.PAUSE_INFINITELY(), type(uint256).max);
    }

    function test_whenPaused_RevertsIfNotPaused() public {
        vm.expectRevert(PausableUntil.PausedExpected.selector);
        pausable.modifierWhenPaused();
    }

    function test_whenPaused_DoesNotRevertIfPaused() public {
        pausable.exposedPauseFor(1000);
        pausable.modifierWhenPaused();
    }

    function test_whenResumed_RevertsIfPaused() public {
        pausable.exposedPauseFor(1000);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        pausable.modifierWhenResumed();
    }

    function test_whenResumed_DoesNotRevertIfNotPaused() public view {
        pausable.modifierWhenResumed();
    }

    function test_isPaused_ReturnsFalseIfNotPaused() public view {
        assertFalse(pausable.isPaused());
    }

    function test_isPaused_ReturnsTrueIfPaused() public {
        pausable.exposedPauseFor(1000);
        assertTrue(pausable.isPaused());
    }

    function test_getResumeSinceTimestamp_ReturnsZeroIfNotPaused() public view {
        assertEq(pausable.getResumeSinceTimestamp(), 0);
    }

    function test_getResumeSinceTimestamp_ReturnsCorrectTimestamp() public {
        pausable.exposedPauseFor(1000);
        uint256 timestamp = block.timestamp;
        assertEq(pausable.getResumeSinceTimestamp(), timestamp + 1000);
    }

    function test_pauseFor_RevertsIfAlreadyPaused() public {
        pausable.exposedPauseFor(1000);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        pausable.exposedPauseFor(1000);
    }

    function test_pauseFor_RevertsIfZeroDuration() public {
        vm.expectRevert(PausableUntil.ZeroPauseDuration.selector);
        pausable.exposedPauseFor(0);
    }

    function test_pauseFor_PausesCorrectly() public {
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(404);
        pausable.exposedPauseFor(404);
        assertTrue(pausable.isPaused());
    }

    function test_pauseFor_PausesToMaxUint256() public {
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(type(uint256).max);
        pausable.exposedPauseFor(type(uint256).max);
        assertTrue(pausable.isPaused());
    }

    function test_pauseUntil_RevertsIfAlreadyPaused() public {
        pausable.exposedPauseFor(1000);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        pausable.exposedPauseFor(1000);
    }

    function test_pauseUntil_RevertsIfTimestampInPast() public {
        vm.expectRevert(PausableUntil.PauseUntilMustBeInFuture.selector);
        pausable.exposedPauseUntil(0);
    }

    function test_pauseUntil_PausesCorrectly() public {
        uint256 timestamp = block.timestamp;
        vm.expectEmit(address(pausable));
        // we expect +1 because the pauseUntil is inclusive
        emit PausableUntil.Paused(1001);
        pausable.exposedPauseUntil(timestamp + 1000);
        assertTrue(pausable.isPaused());
    }

    function test_pauseUntil_PausesToMaxUint256() public {
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(type(uint256).max);
        pausable.exposedPauseUntil(type(uint256).max);
        assertTrue(pausable.isPaused());
    }

    function test_resume_RevertsIfNotPaused() public {
        vm.expectRevert(PausableUntil.PausedExpected.selector);
        pausable.exposedResume();
    }

    function test_resume_ResumesCorrectly() public {
        pausable.exposedPauseFor(1000);
        vm.expectEmit(address(pausable));
        emit PausableUntil.Resumed();
        pausable.exposedResume();
        assertFalse(pausable.isPaused());
    }

    function test_resume_RevertsIfAlreadyResumed() public {
        pausable.exposedPauseFor(1000);
        pausable.exposedResume();
        vm.expectRevert(PausableUntil.PausedExpected.selector);
        pausable.exposedResume();
    }

    function test_setPausedState_PausesCorrectly() public {
        uint256 timestamp = block.timestamp;
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(1000);
        pausable.exposedSetPauseState(timestamp + 1000);
        assertTrue(pausable.isPaused());
    }

    function test_setPausedState_PausesToMaxUint256() public {
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(type(uint256).max);
        pausable.exposedSetPauseState(type(uint256).max);
        assertTrue(pausable.isPaused());
    }

    function test_setPausedState_ResumesCorrectly() public {
        uint256 timestamp = block.timestamp;
        vm.expectEmit(address(pausable));
        emit PausableUntil.Paused(1);
        pausable.exposedSetPauseState(timestamp + 1);
        vm.warp(timestamp + 1);
        assertFalse(pausable.isPaused());
    }
}

contract PausableUntilImpl is PausableUntil {
    function modifierWhenPaused() external view whenPaused {}

    function modifierWhenResumed() external view whenResumed {}

    function exposedPauseFor(uint256 _duration) external {
        _pauseFor(_duration);
    }

    function exposedPauseUntil(uint256 _pauseUntilInclusive) external {
        _pauseUntil(_pauseUntilInclusive);
    }

    function exposedResume() external {
        _resume();
    }

    function exposedSetPauseState(uint256 _resumeSince) external {
        _setPausedState(_resumeSince);
    }
}
