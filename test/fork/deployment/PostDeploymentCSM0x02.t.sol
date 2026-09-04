// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { DeployCSM0x02Params } from "script/csm0x02/DeployCSM0x02Base.s.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    DeployCSM0x02Params internal deployParams;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Community0x02)
            vm.skip(true, "Current deployment is not Community0x02 module type");
        deployParams = parseDeployParams0x02(env.DEPLOY_CONFIG);
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(module.getInitializedVersion(), 3);
        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 0);
    }

    function test_slotsReusedForMappingsAreClean_onlyFull() public {
        bytes32 slot3 = vm.load(address(module), bytes32(uint256(3)));
        assertEq(slot3, bytes32(0), "assert slot3 is clean");

        bytes32 slot4 = vm.load(address(module), bytes32(uint256(4)));
        assertEq(slot4, bytes32(0), "assert slot4 is clean");
    }

    function test_roles_onlyFull() public view {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        assertEq(module.getRoleMemberCount(role), 1);
        assertTrue(module.hasRole(role, address(permissionlessGate)));

        role = module.REWIND_TOP_UP_QUEUE_ROLE();
        assertEq(module.getRoleMemberCount(role), 1);
        assertTrue(module.hasRole(role, deployParams.rewindTopUpQueueRoleHolder));
    }

    function test_topUpQueueConfig() public view {
        assertGt(deployParams.topUpQueueLimit, 0, "top-up queue limit in config must be non-zero");

        (bool enabled, uint256 limit, , ) = module.getTopUpQueue();
        assertTrue(enabled, "top-up queue is disabled");
        assertEq(limit, deployParams.topUpQueueLimit, "top-up queue limit mismatch");
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: deployParams.topUpQueueLimit });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        moduleImpl.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: deployParams.topUpQueueLimit });
    }

    function test_proxy_onlyFull() public view {
        _assertProxy(address(module), address(moduleImpl), deployParams.proxyAdmin, "module");
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

    function test_bondCurves_scratch_onlyFull() public view {
        _assertBondCurve(accounting, accounting.DEFAULT_BOND_CURVE_ID(), deployParams.defaultBondCurve);

        for (uint256 i; i < deployParams.extraBondCurves.length; ++i) {
            _assertBondCurve(accounting, accounting.DEFAULT_BOND_CURVE_ID() + i + 1, deployParams.extraBondCurves[i]);
        }
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
    function test_pausables_afterVote() public {
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
        _checkAdminRole(address(permissionlessGate), deployParams.aragonAgent, deployParams.secondAdminAddress);
        assertEq(permissionlessGate.getRoleMemberCount(permissionlessGate.RECOVERER_ROLE()), 0);
    }
}
