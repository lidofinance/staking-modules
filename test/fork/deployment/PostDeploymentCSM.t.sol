// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { DeployParams } from "script/csm/DeployBase.s.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { VettedGate } from "src/VettedGate.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    DeployParams internal deployParams;
    uint256 adminsCount;
    bool internal isUpgradeFlow;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Community) vm.skip(true, "Current deployment is not Community module type");
        deployParams = parseDeployParams(env.DEPLOY_CONFIG);
        isUpgradeFlow = env.VOTE_PREV_BLOCK != 0;
        adminsCount = block.chainid == 1 ? 1 : 2;
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
        assertEq(module.getRoleMemberCount(module.CREATE_NODE_OPERATOR_ROLE()), 3);
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate)));
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(identifiedDVTClusterGate)));
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(permissionlessGate)));
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: 0 });

        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));

        assertEq(proxy.proxy__getImplementation(), address(moduleImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        ICSModule moduleImpl = ICSModule(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        moduleImpl.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: 0 });
    }
}

contract AccountingDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), deployParams.setResetBondCurveAddress));
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(vettedGate)));
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(identifiedDVTClusterGate)));
        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 3);
    }

    function test_defaultCurve_scratch_onlyFull() public view {
        _assertBondCurve(accounting.DEFAULT_BOND_CURVE_ID(), deployParams.defaultBondCurve);
    }

    function test_legacyEaCurve_scratch_onlyFull() public view {
        _assertBondCurve(accounting.DEFAULT_BOND_CURVE_ID() + 1, deployParams.legacyEaBondCurve);
    }

    function test_identifiedCommunityStakersCurve_scratch_onlyFull() public view {
        uint256 identifiedCommunityStakersCurveId = vettedGate.curveId();
        assertEq(identifiedCommunityStakersCurveId, deployParams.identifiedCommunityStakersGateCurveId);
        _assertBondCurve(identifiedCommunityStakersCurveId, deployParams.identifiedCommunityStakersGateBondCurve);
    }

    function test_identifiedDVTClusterCurve_scratch_onlyFull() public view {
        uint256 identifiedDVTClusterCurveId = deployParams.identifiedDVTClusterBondCurveId;
        assertEq(identifiedDVTClusterGate.curveId(), identifiedDVTClusterCurveId);
        _assertBondCurve(identifiedDVTClusterCurveId, deployParams.identifiedDVTClusterBondCurve);
    }

    function _assertBondCurve(uint256 curveId, uint256[2][] storage expectedCurve) internal view {
        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo(curveId);
        assertEq(curve.intervals.length, expectedCurve.length);
        uint256 minBond;
        for (uint256 i; i < curve.intervals.length; ++i) {
            uint256 minKeysCount = expectedCurve[i][0];
            uint256 trend = expectedCurve[i][1];
            if (i == 0) {
                minBond = trend;
            } else {
                uint256 prevMinKeysCount = expectedCurve[i - 1][0];
                uint256 prevTrend = expectedCurve[i - 1][1];
                minBond += trend + (minKeysCount - prevMinKeysCount - 1) * prevTrend;
            }
            assertEq(curve.intervals[i].minKeysCount, minKeysCount);
            assertEq(curve.intervals[i].minBond, minBond);
            assertEq(curve.intervals[i].trend, trend);
            assertEq(accounting.getBondAmountByKeysCount(minKeysCount, curveId), minBond);
        }
    }
}

contract ParametersRegistryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
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
        assertEq(parametersRegistry.getInitializedVersion(), 3);
    }

    function test_legacyEaCurve_onlyFull() public view {
        uint256 legacyEaBondCurveId = accounting.DEFAULT_BOND_CURVE_ID() + 1;
        assertEq(parametersRegistry.getKeyRemovalCharge(legacyEaBondCurveId), deployParams.defaultKeyRemovalCharge);
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(legacyEaBondCurveId),
            deployParams.defaultGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(parametersRegistry.getKeysLimit(legacyEaBondCurveId), deployParams.defaultKeysLimit);

        IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
            legacyEaBondCurveId
        );
        assertEq(rewardShareData.length, 1);
        assertEq(rewardShareData[0].minKeyNumber, 1);
        assertEq(rewardShareData[0].value, deployParams.defaultRewardShareBP);

        IParametersRegistry.KeyNumberValueInterval[] memory performanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(legacyEaBondCurveId);
        assertEq(performanceLeewayData.length, 1);
        assertEq(performanceLeewayData[0].minKeyNumber, 1);
        assertEq(performanceLeewayData[0].value, deployParams.defaultAvgPerfLeewayBP);

        (uint256 lifetime, uint256 threshold) = parametersRegistry.getStrikesParams(legacyEaBondCurveId);
        assertEq(lifetime, deployParams.defaultStrikesLifetimeFrames);
        assertEq(threshold, deployParams.defaultStrikesThreshold);

        (uint256 priority, uint256 maxDeposits) = parametersRegistry.getQueueConfig(legacyEaBondCurveId);
        assertEq(priority, deployParams.defaultQueuePriority);
        assertEq(maxDeposits, deployParams.defaultQueueMaxDeposits);

        assertEq(
            parametersRegistry.getBadPerformancePenalty(legacyEaBondCurveId),
            deployParams.defaultBadPerformancePenalty
        );
        (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
            .getPerformanceCoefficients(legacyEaBondCurveId);
        assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
        assertEq(blocksWeight, deployParams.defaultBlocksWeight);
        assertEq(syncWeight, deployParams.defaultSyncWeight);

        assertEq(parametersRegistry.getAllowedExitDelay(legacyEaBondCurveId), deployParams.defaultAllowedExitDelay);
        assertEq(parametersRegistry.getExitDelayFee(legacyEaBondCurveId), deployParams.defaultExitDelayFee);
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(legacyEaBondCurveId),
            deployParams.defaultMaxElWithdrawalRequestFee
        );
    }

    function test_identifiedCommunityStakersCurve_onlyFull() public view {
        uint256 identifiedCommunityStakersGateCurveId = vettedGate.curveId();
        assertEq(
            parametersRegistry.getKeyRemovalCharge(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateKeyRemovalCharge
        );
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(
            parametersRegistry.getKeysLimit(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateKeysLimit
        );

        IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(rewardShareData.length, deployParams.identifiedCommunityStakersGateRewardShareData.length);
        for (uint256 i = 0; i < rewardShareData.length; i++) {
            assertEq(rewardShareData[i].minKeyNumber, deployParams.identifiedCommunityStakersGateRewardShareData[i][0]);
            assertEq(rewardShareData[i].value, deployParams.identifiedCommunityStakersGateRewardShareData[i][1]);
        }
        IParametersRegistry.KeyNumberValueInterval[] memory performanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(identifiedCommunityStakersGateCurveId);
        assertEq(performanceLeewayData.length, deployParams.identifiedCommunityStakersGateAvgPerfLeewayData.length);
        for (uint256 i = 0; i < performanceLeewayData.length; i++) {
            assertEq(
                performanceLeewayData[i].minKeyNumber,
                deployParams.identifiedCommunityStakersGateAvgPerfLeewayData[i][0]
            );
            assertEq(
                performanceLeewayData[i].value,
                deployParams.identifiedCommunityStakersGateAvgPerfLeewayData[i][1]
            );
        }

        (uint256 lifetime, uint256 threshold) = parametersRegistry.getStrikesParams(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(lifetime, deployParams.identifiedCommunityStakersGateStrikesLifetimeFrames);
        assertEq(threshold, deployParams.identifiedCommunityStakersGateStrikesThreshold);

        (uint256 icsPriority, uint256 icsMaxDeposits) = parametersRegistry.getQueueConfig(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(icsPriority, deployParams.identifiedCommunityStakersGateQueuePriority);
        assertEq(icsMaxDeposits, deployParams.identifiedCommunityStakersGateQueueMaxDeposits);

        assertEq(
            parametersRegistry.getBadPerformancePenalty(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateBadPerformancePenalty
        );
        (uint256 icsAttestationsWeight, uint256 icsBlocksWeight, uint256 icsSyncWeight) = parametersRegistry
            .getPerformanceCoefficients(identifiedCommunityStakersGateCurveId);
        assertEq(icsAttestationsWeight, deployParams.identifiedCommunityStakersGateAttestationsWeight);
        assertEq(icsBlocksWeight, deployParams.identifiedCommunityStakersGateBlocksWeight);
        assertEq(icsSyncWeight, deployParams.identifiedCommunityStakersGateSyncWeight);

        assertEq(
            parametersRegistry.getAllowedExitDelay(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateAllowedExitDelay
        );
        assertEq(
            parametersRegistry.getExitDelayFee(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateExitDelayFee
        );
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateMaxElWithdrawalRequestFee
        );
    }

    function test_identifiedDVTClusterCurve_onlyFull() public view {
        uint256 identifiedDVTClusterCurveId = deployParams.identifiedDVTClusterBondCurveId;
        assertEq(identifiedDVTClusterGate.curveId(), identifiedDVTClusterCurveId);

        IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
            identifiedDVTClusterCurveId
        );
        assertEq(rewardShareData.length, deployParams.identifiedDVTClusterRewardShareData.length);
        for (uint256 i; i < rewardShareData.length; ++i) {
            assertEq(rewardShareData[i].minKeyNumber, deployParams.identifiedDVTClusterRewardShareData[i][0]);
            assertEq(rewardShareData[i].value, deployParams.identifiedDVTClusterRewardShareData[i][1]);
        }

        (uint256 priority, uint256 maxDeposits) = parametersRegistry.getQueueConfig(identifiedDVTClusterCurveId);
        assertEq(priority, deployParams.identifiedDVTClusterQueuePriority);
        assertEq(maxDeposits, deployParams.identifiedDVTClusterQueueMaxDeposits);

        assertEq(
            parametersRegistry.getKeyRemovalCharge(identifiedDVTClusterCurveId),
            deployParams.identifiedDVTClusterKeyRemovalCharge
        );
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(identifiedDVTClusterCurveId),
            deployParams.identifiedDVTClusterGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(
            parametersRegistry.getAllowedExitDelay(identifiedDVTClusterCurveId),
            deployParams.identifiedDVTClusterAllowedExitDelay
        );
        assertEq(
            parametersRegistry.getExitDelayFee(identifiedDVTClusterCurveId),
            deployParams.identifiedDVTClusterExitDelayFee
        );

        (uint256 lifetime, uint256 threshold) = parametersRegistry.getStrikesParams(identifiedDVTClusterCurveId);
        assertEq(lifetime, deployParams.defaultStrikesLifetimeFrames);
        assertEq(threshold, deployParams.defaultStrikesThreshold);
        assertEq(
            parametersRegistry.getBadPerformancePenalty(identifiedDVTClusterCurveId),
            deployParams.defaultBadPerformancePenalty
        );
        assertEq(parametersRegistry.getKeysLimit(identifiedDVTClusterCurveId), deployParams.defaultKeysLimit);
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(identifiedDVTClusterCurveId),
            deployParams.defaultMaxElWithdrawalRequestFee
        );

        IParametersRegistry.KeyNumberValueInterval[] memory performanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(identifiedDVTClusterCurveId);
        assertEq(performanceLeewayData.length, 1);
        assertEq(performanceLeewayData[0].minKeyNumber, 1);
        assertEq(performanceLeewayData[0].value, deployParams.defaultAvgPerfLeewayBP);

        (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
            .getPerformanceCoefficients(identifiedDVTClusterCurveId);
        assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
        assertEq(blocksWeight, deployParams.defaultBlocksWeight);
        assertEq(syncWeight, deployParams.defaultSyncWeight);
    }
}

abstract contract VettedGateDeploymentBaseTest is DeploymentBaseTest {
    function _gate() internal view virtual returns (VettedGate);

    function _expectedCurveId() internal view virtual returns (uint256);

    function _expectedTreeRoot() internal view virtual returns (bytes32);

    function _expectedTreeCid() internal view virtual returns (string memory);

    function _expectedPauseRoleMembersWithoutCb() internal view virtual returns (uint256) {
        return 1;
    }

    function test_state() public view {
        VettedGate gate = _gate();

        assertFalse(gate.isPaused());
        assertEq(gate.treeRoot(), _expectedTreeRoot());
        assertEq(gate.treeCid(), _expectedTreeCid());
        assertEq(gate.curveId(), _expectedCurveId());
        assertEq(gate.getInitializedVersion(), 1);
    }

    function test_immutables() public view {
        VettedGate gate = _gate();

        assertEq(address(gate.MODULE()), address(module));
        assertEq(address(gate.ACCOUNTING()), address(accounting));
    }

    function test_roles_onlyFull() public view {
        VettedGate gate = _gate();

        assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent));
        assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), adminsCount);

        assertTrue(gate.hasRole(gate.PAUSE_ROLE(), deployParams.resealManager));
        // TODO: Drop the ICS override once legacy GateSeal PAUSE_ROLE migration is complete.
        _assertCircuitBreakerPauseRoleState(
            address(gate),
            address(circuitBreaker),
            _expectedPauseRoleMembersWithoutCb()
        );

        assertTrue(gate.hasRole(gate.RESUME_ROLE(), deployParams.resealManager));
        assertEq(gate.getRoleMemberCount(gate.RESUME_ROLE()), 1);

        assertEq(gate.getRoleMemberCount(gate.RECOVERER_ROLE()), 0);

        assertTrue(gate.hasRole(gate.SET_TREE_ROLE(), deployParams.easyTrackEVMScriptExecutor));
        assertEq(gate.getRoleMemberCount(gate.SET_TREE_ROLE()), 1);
    }

    function test_proxy_onlyFull() public {
        VettedGate gate = _gate();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        gate.initialize({
            curveId: 1,
            treeRoot: _expectedTreeRoot(),
            treeCid: _expectedTreeCid(),
            admin: deployParams.aragonAgent
        });

        OssifiableProxy proxy = OssifiableProxy(payable(address(gate)));
        assertEq(proxy.proxy__getImplementation(), address(vettedGateImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        VettedGate vettedGateImpl = VettedGate(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vettedGateImpl.initialize({
            curveId: 1,
            treeRoot: _expectedTreeRoot(),
            treeCid: _expectedTreeCid(),
            admin: deployParams.aragonAgent
        });
    }
}

contract IdentifiedCommunityStakersGateDeploymentTest is VettedGateDeploymentBaseTest {
    function _gate() internal view override returns (VettedGate) {
        return vettedGate;
    }

    function _expectedCurveId() internal view override returns (uint256) {
        return deployParams.identifiedCommunityStakersGateCurveId;
    }

    function _expectedTreeRoot() internal view override returns (bytes32) {
        return deployParams.identifiedCommunityStakersGateTreeRoot;
    }

    function _expectedTreeCid() internal view override returns (string memory) {
        return deployParams.identifiedCommunityStakersGateTreeCid;
    }

    function _expectedPauseRoleMembersWithoutCb() internal view override returns (uint256) {
        return _expectedPauseRoleMembersWithoutCb(isUpgradeFlow);
    }
}

contract IdentifiedDVTClusterGateDeploymentTest is VettedGateDeploymentBaseTest {
    function _gate() internal view override returns (VettedGate) {
        return identifiedDVTClusterGate;
    }

    function _expectedCurveId() internal view override returns (uint256) {
        return deployParams.identifiedDVTClusterBondCurveId;
    }

    function _expectedTreeRoot() internal view override returns (bytes32) {
        return deployParams.identifiedDVTClusterGateTreeRoot;
    }

    function _expectedTreeCid() internal view override returns (string memory) {
        return deployParams.identifiedDVTClusterGateTreeCid;
    }
}

contract VettedGateFactoryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertTrue(address(vettedGateFactory) != address(0), "vetted gate factory missing");

        address vettedGateImplementation = OssifiableProxy(payable(address(vettedGate))).proxy__getImplementation();
        assertEq(vettedGateFactory.GATE_IMPL(), vettedGateImplementation, "vetted gate factory impl mismatch");
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
        assertEq(
            circuitBreaker.getPauser(address(vettedGate)),
            deployParams.circuitBreakerPauser,
            "vetted gate pauser"
        );
        assertEq(
            circuitBreaker.getPauser(address(identifiedDVTClusterGate)),
            deployParams.circuitBreakerPauser,
            "idvtc gate pauser"
        );
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
