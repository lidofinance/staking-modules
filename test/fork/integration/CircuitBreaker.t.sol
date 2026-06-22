// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract CircuitBreakerTest is Test, Utilities, DeploymentFixtures {
    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        vm.skip(!_isCircuitBreakerDeployed(), "CircuitBreaker is not deployed");
    }

    function _pause(address pausable) internal {
        vm.prank(circuitBreaker.getPauser(pausable));
        circuitBreaker.pause(pausable);
    }

    function test_pauseAll() public {
        address[] memory pausables = new address[](6);
        pausables[0] = address(csm);
        pausables[1] = address(accounting);
        pausables[2] = address(oracle);
        pausables[3] = address(verifier);
        pausables[4] = address(vettedGate);
        pausables[5] = address(ejector);

        for (uint256 i = 0; i < pausables.length; i++) {
            _pause(pausables[i]);
        }

        assertTrue(csm.isPaused());
        assertTrue(accounting.isPaused());
        assertTrue(oracle.isPaused());
        assertTrue(verifier.isPaused());
        assertTrue(vettedGate.isPaused());
        assertTrue(ejector.isPaused());
    }

    function test_pauseCSM() public {
        _pause(address(csm));

        assertTrue(csm.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
        assertFalse(ejector.isPaused());
    }

    function test_pauseAccounting() public {
        _pause(address(accounting));

        assertFalse(csm.isPaused());
        assertTrue(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
        assertFalse(ejector.isPaused());
    }

    function test_pauseOracle() public {
        _pause(address(oracle));

        assertFalse(csm.isPaused());
        assertFalse(accounting.isPaused());
        assertTrue(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
        assertFalse(ejector.isPaused());
    }

    function test_pauseVerifier() public {
        _pause(address(verifier));

        assertFalse(csm.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertTrue(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
        assertFalse(ejector.isPaused());
    }

    function test_pauseVettedGate() public {
        _pause(address(vettedGate));

        assertFalse(csm.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertTrue(vettedGate.isPaused());
        assertFalse(ejector.isPaused());
    }

    function test_pauseEjector() public {
        _pause(address(ejector));

        assertFalse(csm.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(vettedGate.isPaused());
        assertTrue(ejector.isPaused());
    }
}
