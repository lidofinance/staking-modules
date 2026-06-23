// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract CircuitBreakerTest is CSMIntegrationBase {
    function setUp() public {
        _setUpModule();
        vm.skip(!_isCircuitBreakerDeployed(address(circuitBreaker)), "CircuitBreaker is not deployed");
    }

    function _pause(address pausable) internal {
        vm.prank(circuitBreaker.getPauser(pausable));
        circuitBreaker.pause(pausable);
    }

    function test_pauseAll() public {
        address[] memory pausables = new address[](6);
        pausables[0] = address(module);
        pausables[1] = address(accounting);
        pausables[2] = address(oracle);
        pausables[3] = address(verifier);
        pausables[4] = address(ejector);
        pausables[5] = address(vettedGate);

        for (uint256 i = 0; i < pausables.length; i++) {
            _pause(pausables[i]);
        }

        assertTrue(module.isPaused());
        assertTrue(accounting.isPaused());
        assertTrue(oracle.isPaused());
        assertTrue(verifier.isPaused());
        assertTrue(ejector.isPaused());
        assertTrue(vettedGate.isPaused());
    }

    function test_pauseCSM() public {
        _pause(address(module));

        assertTrue(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(ejector.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_pauseAccounting() public {
        _pause(address(accounting));

        assertFalse(module.isPaused());
        assertTrue(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(ejector.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_pauseOracle() public {
        _pause(address(oracle));

        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertTrue(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(ejector.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_pauseVerifier() public {
        _pause(address(verifier));

        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertTrue(verifier.isPaused());
        assertFalse(ejector.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_pauseEjector() public {
        _pause(address(ejector));

        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertTrue(ejector.isPaused());
        assertFalse(vettedGate.isPaused());
    }

    function test_pauseVettedGate() public {
        _pause(address(vettedGate));

        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
        assertFalse(ejector.isPaused());
        assertTrue(vettedGate.isPaused());
    }
}
