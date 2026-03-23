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
import { ITriggerableWithdrawalsGateway } from "../../../src/interfaces/ITriggerableWithdrawalsGateway.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";

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
        assertEq(module.getRoleMemberCount(module.CREATE_NODE_OPERATOR_ROLE()), 2);

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

        assertFalse(module.hasRole(module.PAUSE_ROLE(), deploymentConfig.gateSeal));
        assertTrue(module.hasRole(module.PAUSE_ROLE(), deploymentConfig.gateSealV3));
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
        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 2);
        assertFalse(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(permissionlessGate)));
        assertFalse(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(module)));

        assertFalse(accounting.hasRole(accounting.PAUSE_ROLE(), deploymentConfig.gateSeal));
        assertTrue(accounting.hasRole(accounting.PAUSE_ROLE(), deploymentConfig.gateSealV3));
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

        assertEq(curvesCountBefore, curvesCountAfter, "curvesCount");
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

        assertFalse(oracle.hasRole(oracle.PAUSE_ROLE(), deploymentConfig.gateSeal));
        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), deploymentConfig.gateSealV3));

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

        assertTrue(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), deploymentConfig.gateSeal));
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

        assertFalse(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), deploymentConfig.gateSeal));
        assertTrue(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), deploymentConfig.gateSealV3));
        assertFalse(vettedGate.hasRole(START_REFERRAL_SEASON_ROLE, deployParams.aragonAgent));
        assertFalse(vettedGate.hasRole(END_REFERRAL_SEASON_ROLE, deployParams.identifiedCommunityStakersGateManager));
        assertEq(vettedGate.getRoleMemberCount(START_REFERRAL_SEASON_ROLE), 0);
        assertEq(vettedGate.getRoleMemberCount(END_REFERRAL_SEASON_ROLE), 0);
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
