// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract GateSealTest is Test, Utilities, DeploymentFixtures {
    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_sealAll() public {
        address[] memory sealables = new address[](5);
        sealables[0] = address(module);
        sealables[1] = address(accounting);
        sealables[2] = address(oracle);
        sealables[3] = address(verifier);
        sealables[4] = address(vettedGate);

        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(module.isPaused());
        assertTrue(accounting.isPaused());
        assertTrue(oracle.isPaused());
        assertTrue(verifier.isPaused());
        assertTrue(vettedGate.isPaused());
    }

    function test_sealCSM() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(module);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_sealAccounting() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(accounting);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(accounting.isPaused());
        assertFalse(module.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_sealOracle() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(oracle);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(oracle.isPaused());
        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_sealVerifier() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(verifier);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(verifier.isPaused());
        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_sealVettedGate() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(vettedGate);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(vettedGate.isPaused());
        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
    }
}
