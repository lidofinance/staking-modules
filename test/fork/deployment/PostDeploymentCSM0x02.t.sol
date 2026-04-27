// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { DeployCSM0x02Params } from "script/csm0x02/DeployCSM0x02Base.s.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    DeployCSM0x02Params internal deployParams;
    uint256 adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Community0x02)
            vm.skip(true, "Current deployment is not Community0x02 module type");
        deployParams = parseDeployParams0x02(env.DEPLOY_CONFIG);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        assertEq(module.getRoleMemberCount(role), 1);
        assertTrue(module.hasRole(role, address(permissionlessGate)));

        role = module.REWIND_TOP_UP_QUEUE_ROLE();
        assertEq(module.getRoleMemberCount(role), 1);
        assertTrue(module.hasRole(role, deployParams.setResetBondCurveAddress));
    }

    function test_topUpQueueConfig() public view {
        assertGt(deployParams.topUpQueueLimit, 0, "top-up queue limit in config must be non-zero");

        (bool enabled, uint256 limit, , ) = module.getTopUpQueue();
        assertTrue(enabled, "top-up queue is disabled");
        assertEq(limit, deployParams.topUpQueueLimit, "top-up queue limit mismatch");
    }
}

contract VettedGateDeploymentTest is DeploymentBaseTest {
    function test_zero_addresses() public view {
        assertEq(address(vettedGateFactory), address(0));
        assertEq(address(vettedGate), address(0));
        assertEq(address(vettedGateImpl), address(0));
    }
}

contract AccountingDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 1);
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), deployParams.setResetBondCurveAddress));
    }
}

contract ParametersRegistryDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        assertEq(parametersRegistry.defaultKeyRemovalCharge(), deployParams.defaultKeyRemovalCharge);
        assertEq(
            parametersRegistry.defaultGeneralDelayedPenaltyAdditionalFine(),
            deployParams.defaultGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(parametersRegistry.defaultKeysLimit(), deployParams.defaultKeysLimit);
        assertEq(parametersRegistry.defaultRewardShare(), deployParams.defaultRewardShareBP);
        assertEq(parametersRegistry.defaultPerformanceLeeway(), deployParams.defaultAvgPerfLeewayBP);
        (uint256 strikesLifetime, uint256 strikesThreshold) = parametersRegistry.defaultStrikesParams();
        assertEq(strikesLifetime, deployParams.defaultStrikesLifetimeFrames);
        assertEq(strikesThreshold, deployParams.defaultStrikesThreshold);

        (uint256 priority, uint256 maxDeposits) = parametersRegistry.defaultQueueConfig();
        assertEq(priority, deployParams.defaultQueuePriority);
        assertEq(maxDeposits, deployParams.defaultQueueMaxDeposits);

        assertEq(parametersRegistry.defaultBadPerformancePenalty(), deployParams.defaultBadPerformancePenalty);

        (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
            .defaultPerformanceCoefficients();
        assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
        assertEq(blocksWeight, deployParams.defaultBlocksWeight);
        assertEq(syncWeight, deployParams.defaultSyncWeight);
        assertEq(parametersRegistry.defaultAllowedExitDelay(), deployParams.defaultAllowedExitDelay);
        assertEq(parametersRegistry.defaultExitDelayFee(), deployParams.defaultExitDelayFee);
        assertEq(parametersRegistry.defaultMaxElWithdrawalRequestFee(), deployParams.defaultMaxElWithdrawalRequestFee);
    }
}

contract CircuitBreakerDeploymentTest is DeploymentBaseTest {
    function test_configuration_afterVote() public {
        vm.skip(!_isCircuitBreakerDeployed(address(circuitBreaker)), "CircuitBreaker is not deployed");
        address pauser = circuitBreaker.getPauser(address(module));
        assertEq(pauser, deployParams.circuitBreakerPauser, "pauser");
    }

    function test_pausables_afterVote() public {
        vm.skip(!_isCircuitBreakerDeployed(address(circuitBreaker)), "CircuitBreaker is not deployed");
        assertEq(circuitBreaker.getPauser(address(module)), deployParams.circuitBreakerPauser, "module pauser");
        assertEq(circuitBreaker.getPauser(address(accounting)), deployParams.circuitBreakerPauser, "accounting pauser");
        assertEq(circuitBreaker.getPauser(address(oracle)), deployParams.circuitBreakerPauser, "oracle pauser");
        assertEq(circuitBreaker.getPauser(address(verifier)), deployParams.circuitBreakerPauser, "verifier pauser");
        assertEq(circuitBreaker.getPauser(address(ejector)), deployParams.circuitBreakerPauser, "ejector pauser");
    }
}

contract PermissionlessGateDeploymentTest is DeploymentBaseTest {
    function test_immutables() public view {
        assertEq(address(permissionlessGate.MODULE()), address(module));
        assertEq(permissionlessGate.CURVE_ID(), accounting.DEFAULT_BOND_CURVE_ID());
    }

    function test_roles() public view {
        assertTrue(permissionlessGate.hasRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent));
        assertEq(permissionlessGate.getRoleMemberCount(permissionlessGate.DEFAULT_ADMIN_ROLE()), adminsCount);
        if (deployParams.secondAdminAddress != address(0)) {
            assertTrue(
                permissionlessGate.hasRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), deployParams.secondAdminAddress)
            );
        }
        assertEq(permissionlessGate.getRoleMemberCount(permissionlessGate.RECOVERER_ROLE()), 0);
    }
}
