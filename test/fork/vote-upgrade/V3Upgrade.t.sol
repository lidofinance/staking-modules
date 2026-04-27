// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { DeployParams } from "../../../script/csm/DeployBase.s.sol";
import { OssifiableProxy } from "../../../src/lib/proxy/OssifiableProxy.sol";
import { NodeOperator } from "../../../src/interfaces/IBaseModule.sol";
import { IBondLock } from "../../../src/interfaces/IBondLock.sol";
import { IBondCurve } from "../../../src/interfaces/IBondCurve.sol";
import { IParametersRegistry } from "../../../src/interfaces/IParametersRegistry.sol";
import { ITriggerableWithdrawalsGateway } from "../../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { ICircuitBreaker } from "../../../src/interfaces/ICircuitBreaker.sol";
import { Verifier } from "../../../src/Verifier.sol";
import { Ejector } from "../../../src/Ejector.sol";
import { VettedGate } from "../../../src/VettedGate.sol";
import { OneShotCurveSetup } from "../../../src/utils/OneShotCurveSetup.sol";

interface IPrevCSParametersRegistry {
    function defaultElRewardsStealingAdditionalFine() external returns (uint256);

    function defaultExitDelayPenalty() external returns (uint256);
}

interface IParametersRegistryV2 {
    function defaultMaxWithdrawalRequestFee() external view returns (uint256);
}

contract V3UpgradeTestBase is Test, Utilities, DeploymentFixtures, InvariantAsserts {
    bytes32 internal constant REPORT_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("REPORT_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 internal constant SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE =
        keccak256("SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE");
    bytes32 internal constant START_REFERRAL_SEASON_ROLE = keccak256("START_REFERRAL_SEASON_ROLE");
    bytes32 internal constant END_REFERRAL_SEASON_ROLE = keccak256("END_REFERRAL_SEASON_ROLE");

    uint256 internal forkIdBeforeUpgrade;
    uint256 internal forkIdAfterUpgrade;

    DeploymentConfig internal deploymentConfig;
    DeployParams internal deployParams;

    error UpdateConfigRequired();

    function setUp() public {
        Env memory env = envVars();
        assertNotEq(env.VOTE_PREV_BLOCK, 0, "VOTE_PREV_BLOCK not set");
        forkIdBeforeUpgrade = vm.createFork(env.RPC_URL, env.VOTE_PREV_BLOCK);
        forkIdAfterUpgrade = vm.createSelectFork(env.RPC_URL);

        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        if (vm.keyExistsJson(config, ".CuratedModule")) {
            vm.skip(true, "Curated deployment config detected; this suite targets CSM upgrade flow");
        }
        if (
            vm.parseJsonAddress(config, ".VettedGateFactory") == address(0) &&
            vm.parseJsonAddress(config, ".VettedGate") == address(0) &&
            vm.parseJsonAddress(config, ".VettedGateImpl") == address(0)
        ) {
            vm.skip(true, "CSM0x02 deployment config detected; this suite targets legacy CSM upgrade flow");
        }
        deploymentConfig = parseDeploymentConfig(config);
        deployParams = parseDeployParams(env.DEPLOY_CONFIG);

        initializeFromDeployment();
    }
}

contract VoteChangesTest is V3UpgradeTestBase {
    function test_csmChanges() public {
        OssifiableProxy csmProxy = OssifiableProxy(payable(address(module)));

        vm.selectFork(forkIdBeforeUpgrade);
        address member0 = module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 0);
        address member1 = module.getRoleMember(module.CREATE_NODE_OPERATOR_ROLE(), 1);
        address oldPermissionlessGate = member0 == address(vettedGate) ? member1 : member0;
        address implBefore = csmProxy.proxy__getImplementation();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = csmProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(moduleImpl));

        assertEq(module.getInitializedVersion(), 3);

        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(permissionlessGate)));
        assertNotEq(oldPermissionlessGate, address(permissionlessGate));
        assertFalse(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), oldPermissionlessGate));
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate)));
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(identifiedDVTClusterGate)));
        assertEq(module.getRoleMemberCount(module.CREATE_NODE_OPERATOR_ROLE()), 3);

        assertFalse(module.hasRole(module.VERIFIER_ROLE(), deploymentConfig.verifier));
        assertTrue(module.hasRole(module.VERIFIER_ROLE(), deploymentConfig.verifierV3));
        assertEq(module.getRoleMemberCount(module.VERIFIER_ROLE()), 1);

        assertTrue(module.hasRole(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), deploymentConfig.verifierV3));
        assertEq(module.getRoleMemberCount(module.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE()), 1);

        assertTrue(
            module.hasRole(module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(), deployParams.easyTrackEVMScriptExecutor)
        );
        assertEq(module.getRoleMemberCount(module.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE()), 1);

        assertTrue(
            module.hasRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.generalDelayedPenaltyReporter)
        );
        assertEq(module.getRoleMemberCount(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE()), 1);

        assertTrue(
            module.hasRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.easyTrackEVMScriptExecutor)
        );
        assertEq(module.getRoleMemberCount(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE()), 1);

        assertEq(module.getRoleMemberCount(REPORT_EL_REWARDS_STEALING_PENALTY_ROLE), 0);
        assertEq(module.getRoleMemberCount(SETTLE_EL_REWARDS_STEALING_PENALTY_ROLE), 0);

        // TODO: Tighten to the final exact count once CircuitBreaker is live and migration is done.
        _assertCircuitBreakerPauseRoleState(
            address(module),
            deploymentConfig.circuitBreaker,
            _expectedPauseRoleMembersWithoutCb(true)
        );
    }

    function test_burnerRoleChanges() public {
        vm.selectFork(forkIdBeforeUpgrade);
        assertTrue(burner.hasRole(burner.REQUEST_BURN_SHARES_ROLE(), address(accounting)));
        assertFalse(burner.hasRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting)));

        vm.selectFork(forkIdAfterUpgrade);
        assertFalse(burner.hasRole(burner.REQUEST_BURN_SHARES_ROLE(), address(accounting)));
        assertTrue(burner.hasRole(burner.REQUEST_BURN_MY_STETH_ROLE(), address(accounting)));
    }

    function test_csmState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        address accountingBefore = address(module.ACCOUNTING());
        uint256 nonceBefore = module.getNonce();
        (
            uint256 totalExitedValidatorsBefore,
            uint256 totalDepositedValidatorsBefore,
            uint256 depositableValidatorsCountBefore
        ) = module.getStakingModuleSummary();
        uint256 totalNodeOperatorsBefore = module.getNodeOperatorsCount();

        vm.selectFork(forkIdAfterUpgrade);
        address accountingAfter = address(module.ACCOUNTING());
        uint256 nonceAfter = module.getNonce();
        (
            uint256 totalExitedValidatorsAfter,
            uint256 totalDepositedValidatorsAfter,
            uint256 depositableValidatorsCountAfter
        ) = module.getStakingModuleSummary();
        uint256 totalNodeOperatorsAfter = module.getNodeOperatorsCount();

        assertEq(accountingBefore, accountingAfter);
        assertEq(nonceBefore, nonceAfter);
        assertEq(totalExitedValidatorsBefore, totalExitedValidatorsAfter);
        assertEq(totalDepositedValidatorsBefore, totalDepositedValidatorsAfter);
        assertEq(depositableValidatorsCountBefore, depositableValidatorsCountAfter);
        assertEq(totalNodeOperatorsBefore, totalNodeOperatorsAfter);

        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 0);
    }

    function test_csmQueuePriorityRange() public {
        vm.selectFork(forkIdBeforeUpgrade);
        uint256 queueLowestPriorityBefore = parametersRegistry.QUEUE_LOWEST_PRIORITY();

        vm.selectFork(forkIdAfterUpgrade);
        uint256 queueLowestPriorityAfter = parametersRegistry.QUEUE_LOWEST_PRIORITY();

        assertGe(queueLowestPriorityAfter, queueLowestPriorityBefore, "queue priority range shrunk");
    }

    function test_csmStorageSlotsBeforeUpgrade() public {
        vm.selectFork(forkIdBeforeUpgrade);

        bytes32 slot2 = vm.load(address(module), bytes32(uint256(2)));

        assertEq(slot2, bytes32(0), "assert ModuleLinearStorage.keyConfirmedBalance slot is empty before upgrade");
    }

    function test_csmNodeOperatorsState() public {
        if (skipLongForkTest()) return;
        NodeOperator memory noBefore;
        NodeOperator memory noAfter;
        for (uint256 noId = 0; noId < module.getNodeOperatorsCount(); noId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            noBefore = module.getNodeOperator(noId);
            vm.selectFork(forkIdAfterUpgrade);
            noAfter = module.getNodeOperator(noId);

            assertEq(noBefore.totalAddedKeys, noAfter.totalAddedKeys, "totalAddedKeys");
            assertEq(noBefore.totalWithdrawnKeys, noAfter.totalWithdrawnKeys, "totalWithdrawnKeys");
            assertEq(noBefore.totalDepositedKeys, noAfter.totalDepositedKeys, "totalDepositedKeys");
            assertEq(noBefore.totalVettedKeys, noAfter.totalVettedKeys, "totalVettedKeys");
            assertEq(noBefore.stuckValidatorsCount, noAfter.stuckValidatorsCount, "stuckValidatorsCount");
            assertEq(
                noBefore.depositableValidatorsCount,
                noAfter.depositableValidatorsCount,
                "depositableValidatorsCount"
            );
            assertEq(noBefore.targetLimit, noAfter.targetLimit, "targetLimit");
            assertEq(noBefore.targetLimitMode, noAfter.targetLimitMode, "targetLimitMode");
            assertEq(noBefore.totalExitedKeys, noAfter.totalExitedKeys, "totalExitedKeys");
            assertEq(noBefore.enqueuedCount, noAfter.enqueuedCount, "enqueuedCount");
            assertEq(noBefore.managerAddress, noAfter.managerAddress, "managerAddress");
            assertEq(noBefore.proposedManagerAddress, noAfter.proposedManagerAddress, "proposedManagerAddress");
            assertEq(noBefore.rewardAddress, noAfter.rewardAddress, "rewardAddress");
            assertEq(noBefore.proposedRewardAddress, noAfter.proposedRewardAddress, "proposedRewardAddress");
            assertEq(
                noBefore.extendedManagerPermissions,
                noAfter.extendedManagerPermissions,
                "extendedManagerPermissions"
            );
        }
    }

    function test_parametersRegistryChanges() public {
        OssifiableProxy parametersRegistryProxy = OssifiableProxy(payable(address(parametersRegistry)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = parametersRegistryProxy.proxy__getImplementation();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = parametersRegistryProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(parametersRegistryImpl));
        assertEq(parametersRegistry.getInitializedVersion(), 3);
    }

    function test_parametersRegistryState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        uint256 beforeValue;
        uint256 afterValue;

        beforeValue = parametersRegistry.QUEUE_LOWEST_PRIORITY();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.QUEUE_LOWEST_PRIORITY();
        assertGe(afterValue, beforeValue, "queueLowestPriority");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultKeyRemovalCharge();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultKeyRemovalCharge();
        assertEq(beforeValue, afterValue, "defaultKeyRemovalCharge");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = IPrevCSParametersRegistry(address(parametersRegistry)).defaultElRewardsStealingAdditionalFine();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultGeneralDelayedPenaltyAdditionalFine();
        assertEq(beforeValue, afterValue, "defaultGeneralDelayedPenaltyAdditionalFine");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultKeysLimit();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultKeysLimit();
        assertEq(beforeValue, afterValue, "defaultKeysLimit");

        {
            uint32 beforePriority;
            uint32 beforeMaxDeposits;
            uint32 afterPriority;
            uint32 afterMaxDeposits;
            vm.selectFork(forkIdBeforeUpgrade);
            (beforePriority, beforeMaxDeposits) = parametersRegistry.defaultQueueConfig();
            vm.selectFork(forkIdAfterUpgrade);
            (afterPriority, afterMaxDeposits) = parametersRegistry.defaultQueueConfig();
            assertEq(beforePriority, afterPriority, "defaultQueuePriority");
            assertEq(beforeMaxDeposits, afterMaxDeposits, "defaultQueueMaxDeposits");
        }

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultRewardShare();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultRewardShare();
        assertEq(beforeValue, afterValue, "defaultRewardShare");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultPerformanceLeeway();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultPerformanceLeeway();
        assertEq(beforeValue, afterValue, "defaultPerformanceLeeway");

        {
            uint32 beforeLifetime;
            uint32 beforeThreshold;
            uint32 afterLifetime;
            uint32 afterThreshold;
            vm.selectFork(forkIdBeforeUpgrade);
            (beforeLifetime, beforeThreshold) = parametersRegistry.defaultStrikesParams();
            vm.selectFork(forkIdAfterUpgrade);
            (afterLifetime, afterThreshold) = parametersRegistry.defaultStrikesParams();
            assertEq(beforeLifetime, afterLifetime, "defaultStrikesLifetime");
            assertEq(beforeThreshold, afterThreshold, "defaultStrikesThreshold");
        }

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultBadPerformancePenalty();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultBadPerformancePenalty();
        assertEq(beforeValue, afterValue, "defaultBadPerformancePenalty");

        {
            uint32 beforeAttestationsWeight;
            uint32 beforeBlocksWeight;
            uint32 beforeSyncWeight;
            uint32 afterAttestationsWeight;
            uint32 afterBlocksWeight;
            uint32 afterSyncWeight;
            vm.selectFork(forkIdBeforeUpgrade);
            (beforeAttestationsWeight, beforeBlocksWeight, beforeSyncWeight) = parametersRegistry
                .defaultPerformanceCoefficients();
            vm.selectFork(forkIdAfterUpgrade);
            (afterAttestationsWeight, afterBlocksWeight, afterSyncWeight) = parametersRegistry
                .defaultPerformanceCoefficients();
            assertEq(beforeAttestationsWeight, afterAttestationsWeight, "defaultAttestationsWeight");
            assertEq(beforeBlocksWeight, afterBlocksWeight, "defaultBlocksWeight");
            assertEq(beforeSyncWeight, afterSyncWeight, "defaultSyncWeight");
        }

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = parametersRegistry.defaultAllowedExitDelay();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultAllowedExitDelay();
        assertEq(beforeValue, afterValue, "defaultAllowedExitDelay");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = IPrevCSParametersRegistry(address(parametersRegistry)).defaultExitDelayPenalty();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultExitDelayFee();
        assertEq(beforeValue, afterValue, "defaultExitDelayFee");

        vm.selectFork(forkIdBeforeUpgrade);
        beforeValue = IParametersRegistryV2(address(parametersRegistry)).defaultMaxWithdrawalRequestFee();
        vm.selectFork(forkIdAfterUpgrade);
        afterValue = parametersRegistry.defaultMaxElWithdrawalRequestFee();
        assertEq(beforeValue, afterValue, "defaultMaxElWithdrawalRequestFee");
    }

    function test_proxyAdminsUnchanged() public {
        _assertProxyAdminUnchanged(deploymentConfig.csm, "csm");
        _assertProxyAdminUnchanged(deploymentConfig.accounting, "accounting");
        _assertProxyAdminUnchanged(deploymentConfig.feeDistributor, "feeDistributor");
        _assertProxyAdminUnchanged(deploymentConfig.oracle, "feeOracle");
        _assertProxyAdminUnchanged(deploymentConfig.strikes, "strikes");
        _assertProxyAdminUnchanged(deploymentConfig.exitPenalties, "exitPenalties");
        _assertProxyAdminUnchanged(deploymentConfig.parametersRegistry, "parametersRegistry");
        _assertProxyAdminUnchanged(deploymentConfig.vettedGate, "vettedGate");
    }

    function _assertProxyAdminUnchanged(address proxyAddress, string memory prefix) internal {
        OssifiableProxy proxy = OssifiableProxy(payable(proxyAddress));

        vm.selectFork(forkIdBeforeUpgrade);
        address adminBefore = proxy.proxy__getAdmin();

        vm.selectFork(forkIdAfterUpgrade);
        assertEq(proxy.proxy__getAdmin(), adminBefore, string.concat(prefix, " proxy admin changed"));
        assertEq(proxy.proxy__getAdmin(), deployParams.proxyAdmin, string.concat(prefix, " proxy admin mismatch"));
    }

    function test_accountingChanges() public {
        OssifiableProxy accountingProxy = OssifiableProxy(payable(address(accounting)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = accountingProxy.proxy__getImplementation();
        uint64 versionBefore = accounting.getInitializedVersion();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = accountingProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(accountingImpl));
        assertEq(versionBefore + 1, accounting.getInitializedVersion());

        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), deployParams.setResetBondCurveAddress));
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(vettedGate)));
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(identifiedDVTClusterGate)));
        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 3);
        assertFalse(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(permissionlessGate)));
        assertFalse(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(module)));

        // TODO: Tighten to the final exact count once CircuitBreaker is live and migration is done.
        _assertCircuitBreakerPauseRoleState(
            address(accounting),
            deploymentConfig.circuitBreaker,
            _expectedPauseRoleMembersWithoutCb(true)
        );
    }

    function test_accountingState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        address feeDistributorBefore = address(accounting.FEE_DISTRIBUTOR());
        address chargePenaltyRecipientBefore = address(accounting.chargePenaltyRecipient());
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.selectFork(forkIdAfterUpgrade);
        address feeDistributorAfter = address(accounting.FEE_DISTRIBUTOR());
        address chargePenaltyRecipientAfter = address(accounting.chargePenaltyRecipient());
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(feeDistributorBefore, feeDistributorAfter);
        assertEq(chargePenaltyRecipientBefore, chargePenaltyRecipientAfter);
        assertEq(totalBondSharesBefore, totalBondSharesAfter);
    }

    function test_accountingCurvesState() public {
        if (skipLongForkTest()) return;
        vm.selectFork(forkIdBeforeUpgrade);
        uint256 curvesCountBefore = accounting.getCurvesCount();

        vm.selectFork(forkIdAfterUpgrade);
        uint256 curvesCountAfter = accounting.getCurvesCount();

        assertEq(curvesCountAfter, curvesCountBefore + 1, "curvesCount");
        for (uint256 curveId = 0; curveId < curvesCountBefore; curveId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            IBondCurve.BondCurveData memory curveBefore = accounting.getCurveInfo(curveId);
            vm.selectFork(forkIdAfterUpgrade);
            IBondCurve.BondCurveData memory curveAfter = accounting.getCurveInfo(curveId);

            assertEq(curveBefore.intervals.length, curveAfter.intervals.length, "curve intervals length");
            for (uint256 intervalId = 0; intervalId < curveBefore.intervals.length; intervalId++) {
                IBondCurve.BondCurveInterval memory beforeInterval = curveBefore.intervals[intervalId];
                IBondCurve.BondCurveInterval memory afterInterval = curveAfter.intervals[intervalId];
                assertEq(beforeInterval.minKeysCount, afterInterval.minKeysCount, "curve interval minKeysCount");
                assertEq(beforeInterval.minBond, afterInterval.minBond, "curve interval minBond");
                assertEq(beforeInterval.trend, afterInterval.trend, "curve interval trend");
            }
        }
    }

    function test_identifiedDVTClusterCurveSetup() public {
        assertNotEq(deploymentConfig.identifiedDVTClusterCurveSetup, address(0), "IdentifiedDVTClusterCurveSetup");

        vm.selectFork(forkIdBeforeUpgrade);
        uint256 curvesCountBefore = accounting.getCurvesCount();

        vm.selectFork(forkIdAfterUpgrade);
        OneShotCurveSetup curveSetup = OneShotCurveSetup(deploymentConfig.identifiedDVTClusterCurveSetup);
        uint256 curveId = curveSetup.deployedCurveId();

        assertTrue(curveSetup.executed(), "curve setup not executed");
        assertEq(curveId, curvesCountBefore, "curve id");
        assertEq(curveId, deployParams.identifiedDVTClusterBondCurveId, "configured curve id");
        assertFalse(
            accounting.hasRole(accounting.MANAGE_BOND_CURVES_ROLE(), address(curveSetup)),
            "accounting role not renounced"
        );
        assertFalse(
            parametersRegistry.hasRole(parametersRegistry.MANAGE_CURVE_PARAMETERS_ROLE(), address(curveSetup)),
            "parameters role not renounced"
        );

        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo(curveId);
        assertEq(curve.intervals.length, deployParams.identifiedDVTClusterBondCurve.length, "curve intervals length");
        uint256 minBond;
        for (uint256 i; i < curve.intervals.length; ++i) {
            uint256 minKeysCount = deployParams.identifiedDVTClusterBondCurve[i][0];
            uint256 trend = deployParams.identifiedDVTClusterBondCurve[i][1];
            if (i == 0) {
                minBond = trend;
            } else {
                uint256 prevMinKeysCount = deployParams.identifiedDVTClusterBondCurve[i - 1][0];
                uint256 prevTrend = deployParams.identifiedDVTClusterBondCurve[i - 1][1];
                minBond += trend + (minKeysCount - prevMinKeysCount - 1) * prevTrend;
            }
            assertEq(curve.intervals[i].minKeysCount, minKeysCount, "curve interval min keys");
            assertEq(curve.intervals[i].minBond, minBond, "curve interval min bond");
            assertEq(curve.intervals[i].trend, trend, "curve interval trend");
        }
        assertEq(
            accounting.getBondAmountByKeysCount(1, curveId),
            deployParams.identifiedDVTClusterBondCurve[0][1],
            "first key bond"
        );
        assertEq(
            accounting.getBondAmountByKeysCount(2, curveId),
            deployParams.identifiedDVTClusterBondCurve[0][1] + deployParams.identifiedDVTClusterBondCurve[1][1],
            "second key bond"
        );

        (uint32 priority, uint32 maxDeposits) = parametersRegistry.getQueueConfig(curveId);
        assertEq(priority, deployParams.identifiedDVTClusterQueuePriority, "queue priority");
        assertEq(maxDeposits, deployParams.identifiedDVTClusterQueueMaxDeposits, "queue max deposits");

        IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
            curveId
        );
        assertEq(
            rewardShareData.length,
            deployParams.identifiedDVTClusterRewardShareData.length,
            "reward share length"
        );
        for (uint256 i; i < rewardShareData.length; ++i) {
            assertEq(
                rewardShareData[i].minKeyNumber,
                deployParams.identifiedDVTClusterRewardShareData[i][0],
                "reward share min key"
            );
            assertEq(rewardShareData[i].value, deployParams.identifiedDVTClusterRewardShareData[i][1], "reward share");
        }

        assertEq(
            parametersRegistry.getKeyRemovalCharge(curveId),
            deployParams.identifiedDVTClusterKeyRemovalCharge,
            "key removal charge"
        );
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(curveId),
            deployParams.identifiedDVTClusterGeneralDelayedPenaltyAdditionalFine,
            "delayed penalty fine"
        );
        assertEq(
            parametersRegistry.getAllowedExitDelay(curveId),
            deployParams.identifiedDVTClusterAllowedExitDelay,
            "allowed exit delay"
        );
        assertEq(
            parametersRegistry.getExitDelayFee(curveId),
            deployParams.identifiedDVTClusterExitDelayFee,
            "exit delay fee"
        );

        (uint256 lifetime, uint256 threshold) = parametersRegistry.getStrikesParams(curveId);
        assertEq(lifetime, deployParams.defaultStrikesLifetimeFrames, "strikes lifetime");
        assertEq(threshold, deployParams.defaultStrikesThreshold, "strikes threshold");
        assertEq(
            parametersRegistry.getBadPerformancePenalty(curveId),
            deployParams.defaultBadPerformancePenalty,
            "bad performance penalty"
        );
        assertEq(parametersRegistry.getKeysLimit(curveId), deployParams.defaultKeysLimit, "keys limit");
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(curveId),
            deployParams.defaultMaxElWithdrawalRequestFee,
            "max withdrawal request fee"
        );

        IParametersRegistry.KeyNumberValueInterval[] memory performanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(curveId);
        assertEq(performanceLeewayData.length, 1, "performance leeway length");
        assertEq(performanceLeewayData[0].minKeyNumber, 1, "performance leeway min key");
        assertEq(performanceLeewayData[0].value, deployParams.defaultAvgPerfLeewayBP, "performance leeway");

        (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
            .getPerformanceCoefficients(curveId);
        assertEq(attestationsWeight, deployParams.defaultAttestationsWeight, "attestations weight");
        assertEq(blocksWeight, deployParams.defaultBlocksWeight, "blocks weight");
        assertEq(syncWeight, deployParams.defaultSyncWeight, "sync weight");
    }

    function test_identifiedDVTClusterGateChanges() public view {
        uint256 adminsCount = deployParams.secondAdminAddress == address(0) ? 1 : 2;
        VettedGate gate = identifiedDVTClusterGate;

        OssifiableProxy gateProxy = OssifiableProxy(payable(address(gate)));
        assertEq(gateProxy.proxy__getImplementation(), address(vettedGateImpl), "gate implementation");
        assertEq(gateProxy.proxy__getAdmin(), deployParams.proxyAdmin, "gate proxy admin");

        assertFalse(gate.isPaused(), "gate paused");
        assertEq(gate.getInitializedVersion(), 1, "gate initialized version");
        assertEq(address(gate.MODULE()), address(module), "gate module");
        assertEq(address(gate.ACCOUNTING()), address(accounting), "gate accounting");
        assertEq(gate.curveId(), deployParams.identifiedDVTClusterBondCurveId, "gate curve id");
        assertEq(gate.treeRoot(), deployParams.identifiedDVTClusterGateTreeRoot, "gate tree root");
        assertEq(
            keccak256(bytes(gate.treeCid())),
            keccak256(bytes(deployParams.identifiedDVTClusterGateTreeCid)),
            "gate tree cid"
        );

        assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "gate aragon admin");
        if (deployParams.secondAdminAddress != address(0)) {
            assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), deployParams.secondAdminAddress), "gate second admin");
        }
        assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), adminsCount, "gate admin count");

        assertTrue(gate.hasRole(gate.SET_TREE_ROLE(), deployParams.easyTrackEVMScriptExecutor), "gate set tree role");
        assertEq(gate.getRoleMemberCount(gate.SET_TREE_ROLE()), 1, "gate set tree count");

        assertTrue(gate.hasRole(gate.PAUSE_ROLE(), deployParams.resealManager), "gate pause role");
        if (_isCircuitBreakerConfigured(deploymentConfig.circuitBreaker)) {
            assertTrue(
                gate.hasRole(gate.PAUSE_ROLE(), deploymentConfig.circuitBreaker),
                "gate circuit breaker pause role"
            );
            assertEq(gate.getRoleMemberCount(gate.PAUSE_ROLE()), 2, "gate pause count");
        } else {
            assertEq(gate.getRoleMemberCount(gate.PAUSE_ROLE()), 1, "gate pause count");
        }

        assertTrue(gate.hasRole(gate.RESUME_ROLE(), deployParams.resealManager), "gate resume role");
        assertEq(gate.getRoleMemberCount(gate.RESUME_ROLE()), 1, "gate resume count");

        assertEq(gate.getRoleMemberCount(gate.RECOVERER_ROLE()), 0, "gate recoverer count");
    }

    function test_accountingNodeOperatorsState() public {
        if (skipLongForkTest()) return;
        uint256 curveBefore;
        uint256 curveAfter;
        uint256 bondBefore;
        uint256 requiredBefore;
        uint256 bondAfter;
        uint256 requiredAfter;
        IBondLock.BondLockData memory bondLockBefore;
        IBondLock.BondLockData memory bondLockAfter;
        for (uint256 noId = 0; noId < module.getNodeOperatorsCount(); noId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            curveBefore = accounting.getBondCurveId(noId);
            (bondBefore, requiredBefore) = accounting.getBondSummary(noId);
            bondLockBefore = accounting.getLockedBondInfo(noId);

            vm.selectFork(forkIdAfterUpgrade);
            curveAfter = accounting.getBondCurveId(noId);
            (bondAfter, requiredAfter) = accounting.getBondSummary(noId);
            bondLockAfter = accounting.getLockedBondInfo(noId);

            assertEq(curveBefore, curveAfter, "bond curve");
            assertEq(bondBefore, bondAfter, "bond amount");
            assertEq(requiredBefore, requiredAfter, "required bond amount");
            assertEq(bondLockBefore.amount, bondLockAfter.amount, "bond lock amount");
            assertEq(bondLockBefore.until, bondLockAfter.until, "bond lock until");
        }
    }

    function test_feeDistributorChanges() public {
        OssifiableProxy feeDistributorProxy = OssifiableProxy(payable(address(feeDistributor)));
        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = feeDistributorProxy.proxy__getImplementation();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = feeDistributorProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(feeDistributorImpl));

        assertEq(feeDistributor.getInitializedVersion(), 3);
        assertEq(feeDistributor.rebateRecipient(), locator.treasury());
    }

    function test_feeDistributorState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        bytes32 treeRootBefore = feeDistributor.treeRoot();
        string memory treeCidBefore = feeDistributor.treeCid();
        string memory logCidBefore = feeDistributor.logCid();
        uint256 totalClaimableSharesBefore = feeDistributor.totalClaimableShares();

        vm.selectFork(forkIdAfterUpgrade);
        bytes32 treeRootAfter = feeDistributor.treeRoot();
        string memory treeCidAfter = feeDistributor.treeCid();
        string memory logCidAfter = feeDistributor.logCid();
        uint256 totalClaimableSharesAfter = feeDistributor.totalClaimableShares();

        assertEq(treeRootBefore, treeRootAfter);
        assertEq(keccak256(bytes(treeCidBefore)), keccak256(bytes(treeCidAfter)));
        assertEq(keccak256(bytes(logCidBefore)), keccak256(bytes(logCidAfter)));
        assertEq(totalClaimableSharesBefore, totalClaimableSharesAfter);
    }

    function test_feeDistributorNodeOperatorState() public {
        if (skipLongForkTest()) return;
        uint256 distributedSharesBefore;
        uint256 distributedSharesAfter;
        for (uint256 noId = 0; noId < module.getNodeOperatorsCount(); noId++) {
            vm.selectFork(forkIdBeforeUpgrade);
            distributedSharesBefore = feeDistributor.distributedShares(noId);

            vm.selectFork(forkIdAfterUpgrade);
            distributedSharesAfter = feeDistributor.distributedShares(noId);

            assertEq(distributedSharesBefore, distributedSharesAfter, "distributed shares");
        }
    }

    function test_feeOracleChanges() public {
        OssifiableProxy oracleProxy = OssifiableProxy(payable(address(oracle)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = oracleProxy.proxy__getImplementation();
        uint256 contractVersionBefore = oracle.getContractVersion();
        uint256 consensusVersionBefore = oracle.getConsensusVersion();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = oracleProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(oracleImpl));

        // TODO: Tighten to the final exact count once CircuitBreaker is live and migration is done.
        _assertCircuitBreakerPauseRoleState(
            address(oracle),
            deploymentConfig.circuitBreaker,
            _expectedPauseRoleMembersWithoutCb(true)
        );

        assertEq(oracle.getContractVersion(), contractVersionBefore + 1);
        assertEq(oracle.getConsensusVersion(), consensusVersionBefore + 1);
        assertEq(oracle.getConsensusVersion(), deployParams.consensusVersion);
    }

    function test_validatorStrikesChanges() public {
        OssifiableProxy strikesProxy = OssifiableProxy(payable(address(strikes)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = strikesProxy.proxy__getImplementation();
        bytes32 treeRootBefore = strikes.treeRoot();
        string memory treeCidBefore = strikes.treeCid();
        address ejectorBefore = address(strikes.ejector());

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = strikesProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(strikesImpl));
        assertEq(strikes.treeRoot(), treeRootBefore);
        assertEq(keccak256(bytes(strikes.treeCid())), keccak256(bytes(treeCidBefore)));

        assertEq(address(strikes.ejector()), deploymentConfig.ejector);
        assertNotEq(address(strikes.ejector()), ejectorBefore);

        ITriggerableWithdrawalsGateway twg = ITriggerableWithdrawalsGateway(locator.triggerableWithdrawalsGateway());

        vm.selectFork(forkIdBeforeUpgrade);
        assertTrue(twg.hasRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), ejectorBefore));

        vm.selectFork(forkIdAfterUpgrade);
        assertFalse(twg.hasRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), ejectorBefore));
        assertTrue(twg.hasRole(twg.ADD_FULL_WITHDRAWAL_REQUEST_ROLE(), deploymentConfig.ejector));
    }

    function test_vettedGateChanges() public {
        OssifiableProxy vettedGateProxy = OssifiableProxy(payable(address(vettedGate)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = vettedGateProxy.proxy__getImplementation();
        bytes32 treeRootBefore = vettedGate.treeRoot();
        string memory treeCidBefore = vettedGate.treeCid();
        uint64 versionBefore = vettedGate.getInitializedVersion();
        uint256 startReferralRoleMembersBefore = vettedGate.getRoleMemberCount(START_REFERRAL_SEASON_ROLE);
        uint256 endReferralRoleMembersBefore = vettedGate.getRoleMemberCount(END_REFERRAL_SEASON_ROLE);

        assertTrue(vettedGate.hasRole(START_REFERRAL_SEASON_ROLE, deployParams.aragonAgent));
        assertTrue(vettedGate.hasRole(END_REFERRAL_SEASON_ROLE, deployParams.identifiedCommunityStakersGateManager));
        assertEq(startReferralRoleMembersBefore, 1);
        assertEq(endReferralRoleMembersBefore, 1);

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = vettedGateProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(vettedGateImpl));
        assertEq(vettedGate.getInitializedVersion(), versionBefore);
        assertEq(vettedGate.treeRoot(), treeRootBefore);
        assertEq(keccak256(bytes(vettedGate.treeCid())), keccak256(bytes(treeCidBefore)));

        // TODO: Tighten to the final exact count once CircuitBreaker is live and migration is done.
        _assertCircuitBreakerPauseRoleState(
            address(vettedGate),
            deploymentConfig.circuitBreaker,
            _expectedPauseRoleMembersWithoutCb(true)
        );
        assertFalse(vettedGate.hasRole(START_REFERRAL_SEASON_ROLE, deployParams.aragonAgent));
        assertFalse(vettedGate.hasRole(END_REFERRAL_SEASON_ROLE, deployParams.identifiedCommunityStakersGateManager));
        assertEq(vettedGate.getRoleMemberCount(START_REFERRAL_SEASON_ROLE), 0);
        assertEq(vettedGate.getRoleMemberCount(END_REFERRAL_SEASON_ROLE), 0);
    }

    function test_circuitBreakerChanges() public {
        vm.skip(!_isCircuitBreakerDeployed(deploymentConfig.circuitBreaker), "CircuitBreaker is not deployed");
        vm.selectFork(forkIdAfterUpgrade);
        ICircuitBreaker cb = ICircuitBreaker(deploymentConfig.circuitBreaker);

        // PAUSE_ROLE granted to CircuitBreaker
        assertTrue(module.hasRole(module.PAUSE_ROLE(), deploymentConfig.circuitBreaker));
        assertTrue(accounting.hasRole(accounting.PAUSE_ROLE(), deploymentConfig.circuitBreaker));
        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), deploymentConfig.circuitBreaker));
        assertTrue(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), deploymentConfig.circuitBreaker));
        assertTrue(
            identifiedDVTClusterGate.hasRole(identifiedDVTClusterGate.PAUSE_ROLE(), deploymentConfig.circuitBreaker)
        );
        Verifier verifierV3Contract = Verifier(deploymentConfig.verifierV3);
        assertTrue(verifierV3Contract.hasRole(verifierV3Contract.PAUSE_ROLE(), deploymentConfig.circuitBreaker));
        Ejector ejectorContract = Ejector(payable(deploymentConfig.ejector));
        assertTrue(ejectorContract.hasRole(ejectorContract.PAUSE_ROLE(), deploymentConfig.circuitBreaker));

        // Pausers registered in CircuitBreaker
        assertEq(cb.getPauser(address(module)), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(address(accounting)), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(address(oracle)), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(address(vettedGate)), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(address(identifiedDVTClusterGate)), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(deploymentConfig.verifierV3), deployParams.circuitBreakerPauser);
        assertEq(cb.getPauser(deploymentConfig.ejector), deployParams.circuitBreakerPauser);
    }

    function test_exitPenaltiesChanges() public {
        OssifiableProxy exitPenaltiesProxy = OssifiableProxy(payable(address(exitPenalties)));

        vm.selectFork(forkIdBeforeUpgrade);
        address implBefore = exitPenaltiesProxy.proxy__getImplementation();
        address moduleBefore = address(exitPenalties.MODULE());
        address accountingBefore = address(exitPenalties.ACCOUNTING());
        address strikesBefore = exitPenalties.STRIKES();

        vm.selectFork(forkIdAfterUpgrade);
        address implAfter = exitPenaltiesProxy.proxy__getImplementation();

        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(exitPenaltiesImpl));
        assertEq(address(exitPenalties.MODULE()), moduleBefore);
        assertEq(address(exitPenalties.ACCOUNTING()), accountingBefore);
        assertEq(exitPenalties.STRIKES(), strikesBefore);
    }
}
