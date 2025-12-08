// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { BaseTest } from "./_Base.t.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";

contract PauseTest is BaseTest {
    function test_notPausedByDefault() public view {
        assertFalse(accounting.isPaused());
    }

    function test_pauseFor() public {
        vm.prank(admin);
        accounting.pauseFor(1 days);
        assertTrue(accounting.isPaused());
    }

    function test_resume() public {
        vm.prank(admin);
        accounting.pauseFor(1 days);

        vm.prank(admin);
        accounting.resume();
        assertFalse(accounting.isPaused());
    }

    function test_auto_resume() public {
        vm.prank(admin);
        accounting.pauseFor(1 days);
        assertTrue(accounting.isPaused());
        vm.warp(block.timestamp + 1 days + 1 seconds);
        assertFalse(accounting.isPaused());
    }

    function test_pause_RevertWhen_notAdmin() public {
        expectRoleRevert(stranger, accounting.PAUSE_ROLE());
        vm.prank(stranger);
        accounting.pauseFor(1 days);
    }

    function test_resume_RevertWhen_notAdmin() public {
        vm.prank(admin);
        accounting.pauseFor(1 days);

        expectRoleRevert(stranger, accounting.RESUME_ROLE());
        vm.prank(stranger);
        accounting.resume();
    }
}

contract PauseAffectingTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        accounting.pauseFor(1 days);
    }

    function test_depositETH_RevertWhen_Paused() public {
        vm.deal(address(stakingModule), 1 ether);
        vm.prank(address(stakingModule));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.depositETH{ value: 1 ether }(address(user), 0);
    }

    function test_depositStETH_RevertWhen_Paused() public {
        vm.prank(address(stakingModule));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.depositStETH(
            address(user),
            0,
            1 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_depositWstETH_RevertWhen_Paused() public {
        vm.prank(address(stakingModule));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.depositWstETH(
            address(user),
            0,
            1 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );
    }

    function test_claimRewardsStETH_RevertWhen_Paused() public {
        vm.prank(address(user));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.claimRewardsStETH(0, 1 ether, 1 ether, new bytes32[](1));
    }

    function test_claimRewardsWstETH_RevertWhen_Paused() public {
        vm.prank(address(user));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.claimRewardsWstETH(0, 1 ether, 1 ether, new bytes32[](1));
    }

    function test_claimRewardsUnstETH_RevertWhen_Paused() public {
        vm.prank(address(user));
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        accounting.claimRewardsUnstETH(0, 1 ether, 1 ether, new bytes32[](1));
    }
}
