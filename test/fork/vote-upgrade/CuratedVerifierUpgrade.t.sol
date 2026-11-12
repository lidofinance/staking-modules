// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { CuratedDeployParams } from "../../../script/curated/DeployBase.s.sol";
import { CuratedVerifier } from "../../../src/CuratedVerifier.sol";
import { GIndex } from "../../../src/lib/GIndex.sol";

contract CuratedVerifierUpgradeTest is Test, DeploymentFixtures {
    uint256 internal forkIdBeforeUpgrade;
    uint256 internal forkIdAfterUpgrade;
    CuratedDeployParams internal deployParams;
    address internal previousVerifier;
    CuratedVerifier internal curatedVerifier;

    function setUp() public {
        Env memory env = envVars();
        forkIdAfterUpgrade = vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) vm.skip(true, "Curated deployment required");

        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        if (!vm.keyExistsJson(config, ".CuratedVerifier")) vm.skip(true, "CuratedVerifier deployment required");
        previousVerifier = vm.parseJsonAddress(config, ".Verifier");
        curatedVerifier = CuratedVerifier(vm.parseJsonAddress(config, ".CuratedVerifier"));

        uint256 votePrevBlock = vm.envUint("VOTE_PREV_BLOCK");
        assertNotEq(votePrevBlock, 0, "VOTE_PREV_BLOCK not set");
        forkIdBeforeUpgrade = vm.createFork(env.RPC_URL, votePrevBlock);

        updateCuratedDeployParams(deployParams, env.DEPLOY_CONFIG);
    }

    function test_curatedVerifierImmutables() public view {
        assertEq(address(curatedVerifier.MODULE()), address(curatedModule), "module");
        assertEq(curatedVerifier.WITHDRAWAL_ADDRESS(), locator.withdrawalVault(), "withdrawal address");
        assertEq(curatedVerifier.SLOTS_PER_EPOCH(), deployParams.slotsPerEpoch, "slots per epoch");
        _assertEq(curatedVerifier.GI_FIRST_VALIDATOR_PREV(), deployParams.gIFirstValidator, "validator prev");
        _assertEq(curatedVerifier.GI_FIRST_VALIDATOR_CURR(), deployParams.gIFirstValidator, "validator curr");
        _assertEq(
            curatedVerifier.GI_FIRST_HISTORICAL_SUMMARY_PREV(),
            deployParams.gIFirstHistoricalSummary,
            "historical summary prev"
        );
        _assertEq(
            curatedVerifier.GI_FIRST_HISTORICAL_SUMMARY_CURR(),
            deployParams.gIFirstHistoricalSummary,
            "historical summary curr"
        );
        _assertEq(curatedVerifier.GI_FIRST_BALANCES_NODE_PREV(), deployParams.gIFirstBalanceNode, "balances prev");
        _assertEq(curatedVerifier.GI_FIRST_BALANCES_NODE_CURR(), deployParams.gIFirstBalanceNode, "balances curr");
        assertEq(
            curatedVerifier.FIRST_SUPPORTED_SLOT().unwrap(),
            deployParams.verifierFirstSupportedSlot,
            "first supported slot"
        );
        assertEq(curatedVerifier.PIVOT_SLOT().unwrap(), deployParams.verifierFirstSupportedSlot, "pivot slot");
        assertEq(curatedVerifier.CAPELLA_SLOT().unwrap(), deployParams.capellaSlot, "capella slot");
    }

    function test_curatedVerifierRoles() public view {
        bytes32 adminRole = curatedVerifier.DEFAULT_ADMIN_ROLE();
        uint256 adminsCount = deployParams.secondAdminAddress == address(0) ? 1 : 2;
        assertEq(curatedVerifier.getRoleMemberCount(adminRole), adminsCount, "admin count");
        assertTrue(curatedVerifier.hasRole(adminRole, deployParams.aragonAgent), "admin");
        if (deployParams.secondAdminAddress != address(0)) {
            assertTrue(curatedVerifier.hasRole(adminRole, deployParams.secondAdminAddress), "second admin");
        }

        bytes32 pauseRole = curatedVerifier.PAUSE_ROLE();
        assertEq(curatedVerifier.getRoleMemberCount(pauseRole), 2, "pause count");
        assertTrue(curatedVerifier.hasRole(pauseRole, deployParams.circuitBreaker), "pause circuit breaker");
        assertTrue(curatedVerifier.hasRole(pauseRole, deployParams.resealManager), "pause reseal manager");

        bytes32 resumeRole = curatedVerifier.RESUME_ROLE();
        assertEq(curatedVerifier.getRoleMemberCount(resumeRole), 1, "resume count");
        assertTrue(curatedVerifier.hasRole(resumeRole, deployParams.resealManager), "resume reseal manager");

        assertFalse(curatedVerifier.isPaused(), "paused");
    }

    function test_curatedModuleVerifierRoles() public {
        bytes32 verifierRole = curatedModule.VERIFIER_ROLE();
        bytes32 reportRole = curatedModule.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE();

        vm.selectFork(forkIdBeforeUpgrade);
        assertEq(curatedModule.getRoleMemberCount(verifierRole), 1, "verifier role count before");
        assertTrue(curatedModule.hasRole(verifierRole, previousVerifier), "verifier role before");
        assertEq(curatedModule.getRoleMemberCount(reportRole), 1, "report role count before");
        assertTrue(curatedModule.hasRole(reportRole, previousVerifier), "report role before");

        vm.selectFork(forkIdAfterUpgrade);
        assertEq(curatedModule.getRoleMemberCount(verifierRole), 1, "verifier role count after");
        assertTrue(curatedModule.hasRole(verifierRole, address(curatedVerifier)), "verifier role after");
        assertEq(curatedModule.getRoleMemberCount(reportRole), 1, "report role count after");
        assertTrue(curatedModule.hasRole(reportRole, address(curatedVerifier)), "report role after");
    }

    function test_circuitBreakerPauser() public {
        vm.selectFork(forkIdBeforeUpgrade);
        assertEq(
            circuitBreaker.getPauser(previousVerifier),
            deployParams.circuitBreakerPauser,
            "previous pauser before"
        );
        assertEq(circuitBreaker.getPauser(address(curatedVerifier)), address(0), "pauser before");

        vm.selectFork(forkIdAfterUpgrade);
        assertEq(circuitBreaker.getPauser(previousVerifier), address(0), "previous pauser");
        assertEq(circuitBreaker.getPauser(address(curatedVerifier)), deployParams.circuitBreakerPauser, "pauser");
    }

    function _assertEq(GIndex actual, GIndex expected, string memory err) internal pure {
        assertEq(GIndex.unwrap(actual), GIndex.unwrap(expected), err);
    }
}
