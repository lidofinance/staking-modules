// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract GloasVerifierUpgradeTest is Test, DeploymentFixtures {
    uint256 internal forkIdBeforeUpgrade;
    uint256 internal forkIdAfterUpgrade;
    address internal oldVerifier;

    function setUp() public {
        Env memory env = envVars();
        forkIdAfterUpgrade = vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        uint256 votePrevBlock = vm.envUint("VOTE_PREV_BLOCK");
        assertNotEq(votePrevBlock, 0, "VOTE_PREV_BLOCK not set");
        forkIdBeforeUpgrade = vm.createFork(env.RPC_URL, votePrevBlock);

        string memory artifact = vm.readFile(env.DEPLOY_CONFIG);
        oldVerifier = vm.parseJsonAddress(
            artifact,
            vm.keyExistsJson(artifact, ".VerifierV3") ? ".VerifierV3" : ".Verifier"
        );
    }

    function test_verifierChanges() public {
        vm.selectFork(forkIdBeforeUpgrade);
        address pauser = circuitBreaker.getPauser(oldVerifier);
        assertTrue(module.hasRole(module.VERIFIER_ROLE(), oldVerifier));
        assertTrue(module.hasRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), oldVerifier));

        vm.selectFork(forkIdAfterUpgrade);
        assertFalse(module.hasRole(module.VERIFIER_ROLE(), oldVerifier));
        assertFalse(module.hasRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), oldVerifier));
        assertTrue(module.hasRole(module.VERIFIER_ROLE(), address(verifier)));
        assertTrue(module.hasRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), address(verifier)));
        assertEq(circuitBreaker.getPauser(address(verifier)), pauser);
        assertEq(circuitBreaker.getPauser(oldVerifier), address(0));
    }
}
