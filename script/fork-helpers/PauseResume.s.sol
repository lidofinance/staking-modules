// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script } from "forge-std/Script.sol";
import { DeploymentFixtures } from "test/helpers/Fixtures.sol";
import { ForkHelpersCommon } from "./Common.sol";

contract PauseResume is Script, DeploymentFixtures, ForkHelpersCommon {
    address internal moduleAdmin;
    address internal accountingAdmin;

    modifier broadcastCSMAdmin() {
        _setUp();
        moduleAdmin = _prepareAdmin(address(module));
        vm.startBroadcast(moduleAdmin);
        _;
        vm.stopBroadcast();
    }

    modifier broadcastAccountingAdmin() {
        _setUp();
        accountingAdmin = _prepareAdmin(address(accounting));
        vm.startBroadcast(accountingAdmin);
        _;
        vm.stopBroadcast();
    }

    function pauseCSM() external broadcastCSMAdmin {
        module.grantRole(module.PAUSE_ROLE(), moduleAdmin);
        module.pauseFor(type(uint256).max);

        assertTrue(module.isPaused());
    }

    function resumeCSM() external broadcastCSMAdmin {
        module.grantRole(module.RESUME_ROLE(), moduleAdmin);
        module.resume();

        assertFalse(module.isPaused());
    }

    function pauseAccounting() external broadcastAccountingAdmin {
        accounting.grantRole(accounting.PAUSE_ROLE(), accountingAdmin);
        accounting.pauseFor(type(uint256).max);

        assertTrue(accounting.isPaused());
    }

    function resumeAccounting() external broadcastAccountingAdmin {
        accounting.grantRole(accounting.RESUME_ROLE(), accountingAdmin);
        accounting.resume();

        assertFalse(accounting.isPaused());
    }
}
