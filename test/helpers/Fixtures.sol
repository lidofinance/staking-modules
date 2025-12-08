// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { StdCheats } from "forge-std/StdCheats.sol";
import { LidoMock } from "./mocks/LidoMock.sol";
import { WstETHMock } from "./mocks/WstETHMock.sol";
import { LidoLocatorMock } from "./mocks/LidoLocatorMock.sol";
import { BurnerMock } from "./mocks/BurnerMock.sol";
import { WithdrawalQueueMock } from "./mocks/WithdrawalQueueMock.sol";
import { Stub } from "./mocks/Stub.sol";
import { Test } from "forge-std/Test.sol";
import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";
import { ILido } from "../../src/interfaces/ILido.sol";
import { IBurner } from "../../src/interfaces/IBurner.sol";
import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IGateSeal } from "../../src/interfaces/IGateSeal.sol";
import { NodeOperator, NodeOperatorManagementProperties } from "../../src/interfaces/IBaseModule.sol";
import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { IWithdrawalQueue } from "../../src/interfaces/IWithdrawalQueue.sol";
import { CSModule } from "../../src/CSModule.sol";
import { ParametersRegistry } from "../../src/ParametersRegistry.sol";
import { PermissionlessGate } from "../../src/PermissionlessGate.sol";
import { VettedGate } from "../../src/VettedGate.sol";
import { VettedGateFactory } from "../../src/VettedGateFactory.sol";
import { Accounting } from "../../src/Accounting.sol";
import { FeeOracle } from "../../src/FeeOracle.sol";
import { FeeDistributor } from "../../src/FeeDistributor.sol";
import { Ejector } from "../../src/Ejector.sol";
import { ExitPenalties } from "../../src/ExitPenalties.sol";
import { ValidatorStrikes } from "../../src/ValidatorStrikes.sol";
import { Verifier } from "../../src/Verifier.sol";
import { CuratedModule } from "../../src/CuratedModule.sol";
import { OperatorsData } from "../../src/OperatorsData.sol";
import { CuratedGateFactory } from "../../src/CuratedGateFactory.sol";
import { DeployParams } from "../../script/DeployBase.s.sol";
import { CuratedDeployParams } from "../../script/curated/DeployBase.s.sol";
import { GIndex } from "../../src/lib/GIndex.sol";
import { IACL } from "../../src/interfaces/IACL.sol";
import { IKernel } from "../../src/interfaces/IKernel.sol";
import { Utilities } from "./Utilities.sol";
import { Batch } from "../../src/lib/QueueLib.sol";
import { TWGMock } from "./mocks/TWGMock.sol";

contract Fixtures is StdCheats, Test {
    bytes32 public constant INITIALIZABLE_STORAGE =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    function initLido()
        public
        returns (
            LidoLocatorMock locator,
            WstETHMock wstETH,
            LidoMock stETH,
            BurnerMock burner,
            WithdrawalQueueMock wq
        )
    {
        stETH = new LidoMock({ _totalPooledEther: 8013386371917025835991984 });
        stETH.mintShares({
            _account: address(stETH),
            _sharesAmount: 7059313073779349112833523
        });
        burner = new BurnerMock(address(stETH));
        Stub elVault = new Stub();
        wstETH = new WstETHMock(address(stETH));
        wq = new WithdrawalQueueMock(address(wstETH), address(stETH));
        Stub treasury = new Stub();
        Stub stakingRouter = new Stub();
        TWGMock twg = new TWGMock();
        locator = new LidoLocatorMock(
            address(stETH),
            address(burner),
            address(wq),
            address(elVault),
            address(treasury),
            address(stakingRouter),
            address(twg)
        );
        vm.label(address(stETH), "lido");
        vm.label(address(wstETH), "wstETH");
        vm.label(address(locator), "locator");
        vm.label(address(burner), "burner");
        vm.label(address(wq), "wq");
        vm.label(address(elVault), "elVault");
        vm.label(address(treasury), "treasury");
        vm.label(address(stakingRouter), "stakingRouter");
        vm.label(address(twg), "triggerableWithdrawalsGateway");
    }

    function _enableInitializers(address implementation) internal {
        // cheat to allow implementation initialisation
        vm.store(implementation, INITIALIZABLE_STORAGE, bytes32(0));
    }
}

contract DeploymentHelpers is Test {
    struct Env {
        string RPC_URL;
        string DEPLOY_CONFIG;
        uint256 VOTE_PREV_BLOCK;
    }

    // Intersection of DeployParams and CuratedDeployParams
    struct CommonDeployParams {
        address lidoLocatorAddress;
        address aragonAgent;
        address proxyAdmin;
        address easyTrackEVMScriptExecutor;
        address generalDelayedPenaltyReporter;
        address resealManager;
        address secondAdminAddress;
        address chargePenaltyRecipient;
        address setResetBondCurveAddress;
        uint256 stakingModuleId;
        bytes32 moduleType;
        uint256 queueLowestPriority;
        uint256 bondLockPeriod;
        uint256 minBondLockPeriod;
        uint256 maxBondLockPeriod;
        uint256 secondsPerSlot;
        uint256 slotsPerEpoch;
        uint256 clGenesisTime;
        uint256 oracleReportEpochsPerFrame;
        uint256 fastLaneLengthSlots;
        uint256 consensusVersion;
        address[] oracleMembers;
        uint256 hashConsensusQuorum;
        GIndex gIFirstWithdrawal;
        GIndex gIFirstValidator;
        GIndex gIFirstHistoricalSummary;
        GIndex gIFirstBlockRootInSummary;
        GIndex gIFirstBalanceNode;
        GIndex gIFirstPendingConsolidation;
        uint256 verifierFirstSupportedSlot;
        uint256 capellaSlot;
        uint256[2][] defaultBondCurve;
    }

    struct DeploymentConfig {
        uint256 chainId;
        address csm;
        address csmImpl;
        address permissionlessGate;
        address vettedGateFactory;
        address vettedGate;
        address vettedGateImpl;
        address parametersRegistry;
        address parametersRegistryImpl;
        /// legacy from v1
        address earlyAdoption;
        address accounting;
        address accountingImpl;
        address oracle;
        address oracleImpl;
        address feeDistributor;
        address feeDistributorImpl;
        address ejector;
        address exitPenalties;
        address exitPenaltiesImpl;
        address strikes;
        address strikesImpl;
        address verifier;
        address verifierV2;
        address hashConsensus;
        address lidoLocator;
        address gateSeal;
        address gateSealV2;
    }

    struct CuratedDeploymentConfig {
        uint256 chainId;
        address curatedModule;
        address curatedModuleImpl;
        address parametersRegistry;
        address parametersRegistryImpl;
        address accounting;
        address accountingImpl;
        address oracle;
        address oracleImpl;
        address feeDistributor;
        address feeDistributorImpl;
        address exitPenalties;
        address exitPenaltiesImpl;
        address ejector;
        address strikes;
        address strikesImpl;
        address verifier;
        address hashConsensus;
        address operatorsData;
        address operatorsDataImpl;
        address curatedGateFactory;
        address[] curatedGates;
        address gateSeal;
        address lidoLocator;
    }

    function envVars() public returns (Env memory) {
        Env memory env = Env(
            vm.envOr("RPC_URL", string("")),
            vm.envOr("DEPLOY_CONFIG", string("")),
            vm.envOr("VOTE_PREV_BLOCK", uint256(0))
        );
        vm.skip(_isEmpty(env.RPC_URL));
        vm.skip(_isEmpty(env.DEPLOY_CONFIG));
        return env;
    }

    function parseDeploymentConfig(
        string memory config
    ) public returns (DeploymentConfig memory deploymentConfig) {
        deploymentConfig.chainId = vm.parseJsonUint(config, ".ChainId");

        deploymentConfig.csm = vm.parseJsonAddress(config, ".CSModule");
        vm.label(deploymentConfig.csm, "module");

        deploymentConfig.csmImpl = vm.parseJsonAddress(config, ".CSModuleImpl");
        vm.label(deploymentConfig.csmImpl, "moduleImpl");

        deploymentConfig.permissionlessGate = vm.parseJsonAddress(
            config,
            ".PermissionlessGate"
        );
        vm.label(deploymentConfig.permissionlessGate, "permissionlessGate");

        deploymentConfig.vettedGateFactory = vm.parseJsonAddress(
            config,
            ".VettedGateFactory"
        );
        vm.label(deploymentConfig.vettedGateFactory, "vettedGateFactory");

        deploymentConfig.vettedGate = vm.parseJsonAddress(
            config,
            ".VettedGate"
        );
        vm.label(deploymentConfig.vettedGate, "vettedGate");

        deploymentConfig.vettedGateImpl = vm.parseJsonAddress(
            config,
            ".VettedGateImpl"
        );
        vm.label(deploymentConfig.vettedGateImpl, "vettedGateImpl");

        deploymentConfig.parametersRegistry = vm.parseJsonAddress(
            config,
            ".ParametersRegistry"
        );
        vm.label(deploymentConfig.parametersRegistry, "parametersRegistry");

        deploymentConfig.parametersRegistryImpl = vm.parseJsonAddress(
            config,
            ".ParametersRegistryImpl"
        );
        vm.label(
            deploymentConfig.parametersRegistryImpl,
            "parametersRegistryImpl"
        );

        deploymentConfig.exitPenalties = vm.parseJsonAddress(
            config,
            ".ExitPenalties"
        );
        vm.label(deploymentConfig.exitPenalties, "exitPenalties");

        deploymentConfig.exitPenaltiesImpl = vm.parseJsonAddress(
            config,
            ".ExitPenaltiesImpl"
        );
        vm.label(deploymentConfig.exitPenaltiesImpl, "exitPenaltiesImpl");

        deploymentConfig.strikes = vm.parseJsonAddress(
            config,
            ".ValidatorStrikes"
        );
        vm.label(deploymentConfig.strikes, "strikes");

        deploymentConfig.strikesImpl = vm.parseJsonAddress(
            config,
            ".ValidatorStrikesImpl"
        );
        vm.label(deploymentConfig.strikesImpl, "strikesImpl");

        deploymentConfig.ejector = vm.parseJsonAddress(config, ".Ejector");
        vm.label(deploymentConfig.ejector, "ejector");

        deploymentConfig.accounting = vm.parseJsonAddress(
            config,
            ".Accounting"
        );
        vm.label(deploymentConfig.accounting, "accounting");

        deploymentConfig.accountingImpl = vm.parseJsonAddress(
            config,
            ".AccountingImpl"
        );
        vm.label(deploymentConfig.accounting, "accountingImpl");

        deploymentConfig.oracle = vm.parseJsonAddress(config, ".FeeOracle");
        vm.label(deploymentConfig.oracle, "oracle");

        deploymentConfig.oracleImpl = vm.parseJsonAddress(
            config,
            ".FeeOracleImpl"
        );
        vm.label(deploymentConfig.oracleImpl, "oracleImpl");

        deploymentConfig.feeDistributor = vm.parseJsonAddress(
            config,
            ".FeeDistributor"
        );
        vm.label(deploymentConfig.feeDistributor, "feeDistributor");

        deploymentConfig.feeDistributorImpl = vm.parseJsonAddress(
            config,
            ".FeeDistributorImpl"
        );
        vm.label(deploymentConfig.feeDistributorImpl, "feeDistributorImpl");

        deploymentConfig.verifier = vm.parseJsonAddress(config, ".Verifier");
        if (vm.keyExistsJson(config, ".VerifierV2")) {
            deploymentConfig.verifierV2 = vm.parseJsonAddress(
                config,
                ".VerifierV2"
            );
            vm.label(deploymentConfig.verifierV2, "verifierV2");
        }
        vm.label(deploymentConfig.verifier, "verifier");

        deploymentConfig.hashConsensus = vm.parseJsonAddress(
            config,
            ".HashConsensus"
        );
        vm.label(deploymentConfig.hashConsensus, "hashConsensus");

        deploymentConfig.lidoLocator = vm.parseJsonAddress(
            config,
            ".LidoLocator"
        );
        vm.label(deploymentConfig.lidoLocator, "LidoLocator");

        deploymentConfig.gateSeal = vm.parseJsonAddress(config, ".GateSeal");
        if (vm.keyExistsJson(config, ".GateSealV2")) {
            deploymentConfig.gateSealV2 = vm.parseJsonAddress(
                config,
                ".GateSealV2"
            );
            vm.label(deploymentConfig.gateSealV2, "GateSealV2");
        }
        vm.label(deploymentConfig.gateSeal, "GateSeal");
    }

    function parseCuratedDeploymentConfig(
        string memory config
    ) public returns (CuratedDeploymentConfig memory deploymentConfig) {
        deploymentConfig.chainId = vm.parseJsonUint(config, ".ChainId");

        deploymentConfig.curatedModule = vm.parseJsonAddress(
            config,
            ".CuratedModule"
        );
        vm.label(deploymentConfig.curatedModule, "curatedModule");

        deploymentConfig.curatedModuleImpl = vm.parseJsonAddress(
            config,
            ".CuratedModuleImpl"
        );
        vm.label(deploymentConfig.curatedModuleImpl, "curatedModuleImpl");

        deploymentConfig.parametersRegistry = vm.parseJsonAddress(
            config,
            ".ParametersRegistry"
        );
        vm.label(
            deploymentConfig.parametersRegistry,
            "curatedParametersRegistry"
        );

        deploymentConfig.parametersRegistryImpl = vm.parseJsonAddress(
            config,
            ".ParametersRegistryImpl"
        );
        vm.label(
            deploymentConfig.parametersRegistryImpl,
            "curatedParametersRegistryImpl"
        );

        deploymentConfig.accounting = vm.parseJsonAddress(
            config,
            ".Accounting"
        );
        vm.label(deploymentConfig.accounting, "curatedAccounting");

        deploymentConfig.accountingImpl = vm.parseJsonAddress(
            config,
            ".AccountingImpl"
        );
        vm.label(deploymentConfig.accountingImpl, "curatedAccountingImpl");

        deploymentConfig.oracle = vm.parseJsonAddress(config, ".FeeOracle");
        vm.label(deploymentConfig.oracle, "curatedOracle");

        deploymentConfig.oracleImpl = vm.parseJsonAddress(
            config,
            ".FeeOracleImpl"
        );
        vm.label(deploymentConfig.oracleImpl, "curatedOracleImpl");

        deploymentConfig.feeDistributor = vm.parseJsonAddress(
            config,
            ".FeeDistributor"
        );
        vm.label(deploymentConfig.feeDistributor, "curatedFeeDistributor");

        deploymentConfig.feeDistributorImpl = vm.parseJsonAddress(
            config,
            ".FeeDistributorImpl"
        );
        vm.label(
            deploymentConfig.feeDistributorImpl,
            "curatedFeeDistributorImpl"
        );

        deploymentConfig.exitPenalties = vm.parseJsonAddress(
            config,
            ".ExitPenalties"
        );
        vm.label(deploymentConfig.exitPenalties, "curatedExitPenalties");

        deploymentConfig.exitPenaltiesImpl = vm.parseJsonAddress(
            config,
            ".ExitPenaltiesImpl"
        );
        vm.label(
            deploymentConfig.exitPenaltiesImpl,
            "curatedExitPenaltiesImpl"
        );

        deploymentConfig.ejector = vm.parseJsonAddress(config, ".Ejector");
        vm.label(deploymentConfig.ejector, "curatedEjector");

        deploymentConfig.strikes = vm.parseJsonAddress(
            config,
            ".ValidatorStrikes"
        );
        vm.label(deploymentConfig.strikes, "curatedStrikes");

        deploymentConfig.strikesImpl = vm.parseJsonAddress(
            config,
            ".ValidatorStrikesImpl"
        );
        vm.label(deploymentConfig.strikesImpl, "curatedStrikesImpl");

        deploymentConfig.verifier = vm.parseJsonAddress(config, ".Verifier");
        vm.label(deploymentConfig.verifier, "curatedVerifier");

        deploymentConfig.hashConsensus = vm.parseJsonAddress(
            config,
            ".HashConsensus"
        );
        vm.label(deploymentConfig.hashConsensus, "curatedHashConsensus");

        deploymentConfig.operatorsData = vm.parseJsonAddress(
            config,
            ".OperatorsData"
        );
        vm.label(deploymentConfig.operatorsData, "operatorsData");

        deploymentConfig.operatorsDataImpl = vm.parseJsonAddress(
            config,
            ".OperatorsDataImpl"
        );
        vm.label(deploymentConfig.operatorsDataImpl, "operatorsDataImpl");

        deploymentConfig.curatedGateFactory = vm.parseJsonAddress(
            config,
            ".CuratedGateFactory"
        );
        vm.label(deploymentConfig.curatedGateFactory, "curatedGateFactory");

        if (vm.keyExistsJson(config, ".CuratedGates")) {
            deploymentConfig.curatedGates = vm.parseJsonAddressArray(
                config,
                ".CuratedGates"
            );
            uint256 gatesLength = deploymentConfig.curatedGates.length;
            for (uint256 i = 0; i < gatesLength; ++i) {
                vm.label(deploymentConfig.curatedGates[i], "curatedGate");
            }
        }

        if (vm.keyExistsJson(config, ".GateSeal")) {
            deploymentConfig.gateSeal = vm.parseJsonAddress(
                config,
                ".GateSeal"
            );
            vm.label(deploymentConfig.gateSeal, "curatedGateSeal");
        }

        deploymentConfig.lidoLocator = vm.parseJsonAddress(
            config,
            ".LidoLocator"
        );
        vm.label(deploymentConfig.lidoLocator, "curatedLidoLocator");
    }

    function parseDeployParams(
        string memory deployConfigPath
    ) internal view returns (DeployParams memory) {
        string memory config = vm.readFile(deployConfigPath);
        return
            abi.decode(
                vm.parseJsonBytes(config, ".DeployParams"),
                (DeployParams)
            );
    }

    function updateCuratedDeployParams(
        CuratedDeployParams storage dst,
        string memory deployConfigPath
    ) internal {
        string memory config = vm.readFile(deployConfigPath);
        CuratedDeployParams memory src = abi.decode(
            vm.parseJsonBytes(config, ".DeployParams"),
            (CuratedDeployParams)
        );
        // copy every value separately to avoid `Unimplemented feature` error from solc when copying memory array of structs into storage
        // Lido addresses
        dst.lidoLocatorAddress = src.lidoLocatorAddress;
        dst.aragonAgent = src.aragonAgent;
        dst.easyTrackEVMScriptExecutor = src.easyTrackEVMScriptExecutor;
        dst.proxyAdmin = src.proxyAdmin;

        // Oracle
        dst.secondsPerSlot = src.secondsPerSlot;
        dst.slotsPerEpoch = src.slotsPerEpoch;
        dst.clGenesisTime = src.clGenesisTime;
        dst.oracleReportEpochsPerFrame = src.oracleReportEpochsPerFrame;
        dst.fastLaneLengthSlots = src.fastLaneLengthSlots;
        dst.consensusVersion = src.consensusVersion;

        for (uint256 i; i < src.oracleMembers.length; ++i) {
            dst.oracleMembers.push(src.oracleMembers[i]);
        }

        dst.hashConsensusQuorum = src.hashConsensusQuorum;

        // Verifier
        dst.slotsPerHistoricalRoot = src.slotsPerHistoricalRoot;
        dst.gIFirstWithdrawal = src.gIFirstWithdrawal;
        dst.gIFirstValidator = src.gIFirstValidator;
        dst.gIFirstHistoricalSummary = src.gIFirstHistoricalSummary;
        dst.gIFirstBlockRootInSummary = src.gIFirstBlockRootInSummary;
        dst.gIFirstBalanceNode = src.gIFirstBalanceNode;
        dst.gIFirstPendingConsolidation = src.gIFirstPendingConsolidation;
        dst.verifierFirstSupportedSlot = src.verifierFirstSupportedSlot;
        dst.capellaSlot = src.capellaSlot;

        // Accounting
        for (uint256 i; i < src.defaultBondCurve.length; ++i) {
            dst.defaultBondCurve.push(src.defaultBondCurve[i]);
        }

        dst.minBondLockPeriod = src.minBondLockPeriod;
        dst.maxBondLockPeriod = src.maxBondLockPeriod;
        dst.bondLockPeriod = src.bondLockPeriod;
        dst.setResetBondCurveAddress = src.setResetBondCurveAddress;
        dst.chargePenaltyRecipient = src.chargePenaltyRecipient;

        // Module
        dst.stakingModuleId = src.stakingModuleId;
        dst.moduleType = src.moduleType;
        dst.generalDelayedPenaltyReporter = src.generalDelayedPenaltyReporter;

        // ParametersRegistry
        dst.queueLowestPriority = src.queueLowestPriority;
        dst.defaultKeyRemovalCharge = src.defaultKeyRemovalCharge;
        dst.defaultGeneralDelayedPenaltyAdditionalFine = src
            .defaultGeneralDelayedPenaltyAdditionalFine;
        dst.defaultKeysLimit = src.defaultKeysLimit;
        dst.defaultAvgPerfLeewayBP = src.defaultAvgPerfLeewayBP;
        dst.defaultRewardShareBP = src.defaultRewardShareBP;
        dst.defaultStrikesLifetimeFrames = src.defaultStrikesLifetimeFrames;
        dst.defaultStrikesThreshold = src.defaultStrikesThreshold;
        dst.defaultQueuePriority = src.defaultQueuePriority;
        dst.defaultQueueMaxDeposits = src.defaultQueueMaxDeposits;
        dst.defaultBadPerformancePenalty = src.defaultBadPerformancePenalty;
        dst.defaultAttestationsWeight = src.defaultAttestationsWeight;
        dst.defaultBlocksWeight = src.defaultBlocksWeight;
        dst.defaultSyncWeight = src.defaultSyncWeight;
        dst.defaultAllowedExitDelay = src.defaultAllowedExitDelay;
        dst.defaultExitDelayFee = src.defaultExitDelayFee;
        dst.defaultMaxWithdrawalRequestFee = src.defaultMaxWithdrawalRequestFee;

        // Curated gates
        for (uint256 i; i < src.curatedGates.length; ++i) {
            dst.curatedGates.push(src.curatedGates[i]);
        }

        // GateSeal
        dst.gateSealFactory = src.gateSealFactory;
        dst.sealingCommittee = src.sealingCommittee;
        dst.sealDuration = src.sealDuration;
        dst.sealExpiryTimestamp = src.sealExpiryTimestamp;

        // DG
        dst.resealManager = src.resealManager;

        // Testnet stuff
        dst.secondAdminAddress = src.secondAdminAddress;
    }

    function parseCommonDeployParams(
        string memory config
    ) internal view returns (CommonDeployParams memory params) {
        if (bytes(config).length == 0) {
            return params;
        }

        if (vm.keyExistsJson(config, ".CuratedModule")) {
            CuratedDeployParams memory decoded = abi.decode(
                vm.parseJsonBytes(config, ".CuratedDeployParams"),
                (CuratedDeployParams)
            );
            params.lidoLocatorAddress = decoded.lidoLocatorAddress;
            params.aragonAgent = decoded.aragonAgent;
            params.proxyAdmin = decoded.proxyAdmin;
            params.easyTrackEVMScriptExecutor = decoded
                .easyTrackEVMScriptExecutor;
            params.generalDelayedPenaltyReporter = decoded
                .generalDelayedPenaltyReporter;
            params.resealManager = decoded.resealManager;
            params.secondAdminAddress = decoded.secondAdminAddress;
            params.chargePenaltyRecipient = decoded.chargePenaltyRecipient;
            params.setResetBondCurveAddress = decoded.setResetBondCurveAddress;
            params.stakingModuleId = decoded.stakingModuleId;
            params.moduleType = decoded.moduleType;
            params.queueLowestPriority = decoded.queueLowestPriority;
            params.bondLockPeriod = decoded.bondLockPeriod;
            params.minBondLockPeriod = decoded.minBondLockPeriod;
            params.maxBondLockPeriod = decoded.maxBondLockPeriod;
            params.secondsPerSlot = decoded.secondsPerSlot;
            params.slotsPerEpoch = decoded.slotsPerEpoch;
            params.clGenesisTime = decoded.clGenesisTime;
            params.oracleReportEpochsPerFrame = decoded
                .oracleReportEpochsPerFrame;
            params.fastLaneLengthSlots = decoded.fastLaneLengthSlots;
            params.consensusVersion = decoded.consensusVersion;
            params.oracleMembers = decoded.oracleMembers;
            params.hashConsensusQuorum = decoded.hashConsensusQuorum;
            params.gIFirstWithdrawal = decoded.gIFirstWithdrawal;
            params.gIFirstValidator = decoded.gIFirstValidator;
            params.gIFirstHistoricalSummary = decoded.gIFirstHistoricalSummary;
            params.gIFirstBlockRootInSummary = decoded
                .gIFirstBlockRootInSummary;
            params.gIFirstBalanceNode = decoded.gIFirstBalanceNode;
            params.gIFirstPendingConsolidation = decoded
                .gIFirstPendingConsolidation;
            params.verifierFirstSupportedSlot = decoded
                .verifierFirstSupportedSlot;
            params.capellaSlot = decoded.capellaSlot;
            params.defaultBondCurve = decoded.defaultBondCurve;
        } else {
            DeployParams memory decoded = abi.decode(
                vm.parseJsonBytes(config, ".DeployParams"),
                (DeployParams)
            );
            params.lidoLocatorAddress = decoded.lidoLocatorAddress;
            params.aragonAgent = decoded.aragonAgent;
            params.proxyAdmin = decoded.proxyAdmin;
            params.easyTrackEVMScriptExecutor = decoded
                .easyTrackEVMScriptExecutor;
            params.generalDelayedPenaltyReporter = decoded
                .generalDelayedPenaltyReporter;
            params.resealManager = decoded.resealManager;
            params.secondAdminAddress = decoded.secondAdminAddress;
            params.chargePenaltyRecipient = decoded.chargePenaltyRecipient;
            params.setResetBondCurveAddress = decoded.setResetBondCurveAddress;
            params.stakingModuleId = decoded.stakingModuleId;
            params.moduleType = decoded.moduleType;
            params.queueLowestPriority = decoded.queueLowestPriority;
            params.bondLockPeriod = decoded.bondLockPeriod;
            params.minBondLockPeriod = decoded.minBondLockPeriod;
            params.maxBondLockPeriod = decoded.maxBondLockPeriod;
            params.secondsPerSlot = decoded.secondsPerSlot;
            params.slotsPerEpoch = decoded.slotsPerEpoch;
            params.clGenesisTime = decoded.clGenesisTime;
            params.oracleReportEpochsPerFrame = decoded
                .oracleReportEpochsPerFrame;
            params.fastLaneLengthSlots = decoded.fastLaneLengthSlots;
            params.consensusVersion = decoded.consensusVersion;
            params.oracleMembers = decoded.oracleMembers;
            params.hashConsensusQuorum = decoded.hashConsensusQuorum;
            params.gIFirstWithdrawal = decoded.gIFirstWithdrawal;
            params.gIFirstValidator = decoded.gIFirstValidator;
            params.gIFirstHistoricalSummary = decoded.gIFirstHistoricalSummary;
            params.gIFirstBlockRootInSummary = decoded
                .gIFirstBlockRootInSummary;
            params.gIFirstBalanceNode = decoded.gIFirstBalanceNode;
            params.gIFirstPendingConsolidation = decoded
                .gIFirstPendingConsolidation;
            params.verifierFirstSupportedSlot = decoded
                .verifierFirstSupportedSlot;
            params.capellaSlot = decoded.capellaSlot;
            params.defaultBondCurve = decoded.defaultBondCurve;
        }
    }

    function _isEmpty(string memory s) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(s)) == keccak256(abi.encodePacked(""));
    }
}

contract DeploymentFixtures is StdCheats, DeploymentHelpers {
    enum ModuleType {
        Unknown,
        Community,
        Curated
    }

    ModuleType public moduleType;
    CSModule public module;
    CSModule public moduleImpl;
    ParametersRegistry public parametersRegistry;
    ParametersRegistry public parametersRegistryImpl;
    PermissionlessGate public permissionlessGate;
    VettedGateFactory public vettedGateFactory;
    VettedGate public vettedGate;
    VettedGate public vettedGateImpl;
    address public earlyAdoption;
    Accounting public accounting;
    Accounting public accountingImpl;
    FeeOracle public oracle;
    FeeOracle public oracleImpl;
    FeeDistributor public feeDistributor;
    FeeDistributor public feeDistributorImpl;
    ExitPenalties public exitPenalties;
    ExitPenalties public exitPenaltiesImpl;
    ValidatorStrikes public strikes;
    ValidatorStrikes public strikesImpl;
    Ejector public ejector;
    Verifier public verifier;
    HashConsensus public hashConsensus;
    ILidoLocator public locator;
    IWstETH public wstETH;
    IStakingRouter public stakingRouter;
    ILido public lido;
    IGateSeal public gateSeal;
    IBurner public burner;
    CuratedModule public curatedModule;
    CuratedModule public curatedModuleImpl;
    OperatorsData public operatorsData;
    CuratedGateFactory public curatedGateFactory;
    address[] public curatedGates;

    error ModuleNotFound();

    function initializeFromDeployment() public {
        Env memory env = envVars();
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        delete curatedGates;

        if (vm.keyExistsJson(config, ".CuratedModule")) {
            _initializeCurated(config);
        } else {
            _initializeCommunity(config);
        }
    }

    function _initializeCommunity(string memory config) internal {
        DeploymentConfig memory deploymentConfig = parseDeploymentConfig(
            config
        );
        assertEq(deploymentConfig.chainId, block.chainid, "ChainId mismatch");

        moduleType = ModuleType.Community;

        module = CSModule(deploymentConfig.csm);
        moduleImpl = CSModule(deploymentConfig.csmImpl);
        parametersRegistry = ParametersRegistry(
            deploymentConfig.parametersRegistry
        );
        parametersRegistryImpl = ParametersRegistry(
            deploymentConfig.parametersRegistryImpl
        );
        permissionlessGate = PermissionlessGate(
            deploymentConfig.permissionlessGate
        );
        vettedGateFactory = VettedGateFactory(
            deploymentConfig.vettedGateFactory
        );
        vettedGate = VettedGate(deploymentConfig.vettedGate);
        vettedGateImpl = VettedGate(deploymentConfig.vettedGateImpl);
        earlyAdoption = deploymentConfig.earlyAdoption;
        accounting = Accounting(deploymentConfig.accounting);
        accountingImpl = Accounting(deploymentConfig.accountingImpl);
        oracle = FeeOracle(deploymentConfig.oracle);
        oracleImpl = FeeOracle(deploymentConfig.oracleImpl);
        feeDistributor = FeeDistributor(deploymentConfig.feeDistributor);
        feeDistributorImpl = FeeDistributor(
            deploymentConfig.feeDistributorImpl
        );
        exitPenalties = ExitPenalties(deploymentConfig.exitPenalties);
        exitPenaltiesImpl = ExitPenalties(deploymentConfig.exitPenaltiesImpl);
        ejector = Ejector(payable(deploymentConfig.ejector));
        strikes = ValidatorStrikes(deploymentConfig.strikes);
        strikesImpl = ValidatorStrikes(deploymentConfig.strikesImpl);
        verifier = Verifier(
            deploymentConfig.verifierV2 == address(0)
                ? deploymentConfig.verifier
                : deploymentConfig.verifierV2
        );
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        locator = ILidoLocator(deploymentConfig.lidoLocator);
        lido = ILido(locator.lido());
        stakingRouter = IStakingRouter(locator.stakingRouter());
        wstETH = IWstETH(IWithdrawalQueue(locator.withdrawalQueue()).WSTETH());
        gateSeal = IGateSeal(
            deploymentConfig.gateSealV2 == address(0)
                ? deploymentConfig.gateSeal
                : deploymentConfig.gateSealV2
        );
        burner = IBurner(locator.burner());
    }

    function _initializeCurated(string memory config) internal {
        CuratedDeploymentConfig
            memory deploymentConfig = parseCuratedDeploymentConfig(config);
        assertEq(deploymentConfig.chainId, block.chainid, "ChainId mismatch");

        moduleType = ModuleType.Curated;
        curatedModule = CuratedModule(deploymentConfig.curatedModule);
        curatedModuleImpl = CuratedModule(deploymentConfig.curatedModuleImpl);
        module = CSModule(deploymentConfig.curatedModule);
        moduleImpl = CSModule(deploymentConfig.curatedModuleImpl);
        parametersRegistry = ParametersRegistry(
            deploymentConfig.parametersRegistry
        );
        parametersRegistryImpl = ParametersRegistry(
            deploymentConfig.parametersRegistryImpl
        );
        permissionlessGate = PermissionlessGate(address(0));
        vettedGateFactory = VettedGateFactory(address(0));
        vettedGate = VettedGate(address(0));
        vettedGateImpl = VettedGate(address(0));
        earlyAdoption = address(0);
        accounting = Accounting(deploymentConfig.accounting);
        accountingImpl = Accounting(deploymentConfig.accountingImpl);
        oracle = FeeOracle(deploymentConfig.oracle);
        oracleImpl = FeeOracle(deploymentConfig.oracleImpl);
        feeDistributor = FeeDistributor(deploymentConfig.feeDistributor);
        feeDistributorImpl = FeeDistributor(
            deploymentConfig.feeDistributorImpl
        );
        exitPenalties = ExitPenalties(deploymentConfig.exitPenalties);
        exitPenaltiesImpl = ExitPenalties(deploymentConfig.exitPenaltiesImpl);
        ejector = Ejector(payable(deploymentConfig.ejector));
        strikes = ValidatorStrikes(deploymentConfig.strikes);
        strikesImpl = ValidatorStrikes(deploymentConfig.strikesImpl);
        verifier = Verifier(deploymentConfig.verifier);
        hashConsensus = HashConsensus(deploymentConfig.hashConsensus);
        locator = ILidoLocator(deploymentConfig.lidoLocator);
        lido = ILido(locator.lido());
        stakingRouter = IStakingRouter(locator.stakingRouter());
        wstETH = IWstETH(IWithdrawalQueue(locator.withdrawalQueue()).WSTETH());
        gateSeal = IGateSeal(deploymentConfig.gateSeal);
        burner = IBurner(locator.burner());

        operatorsData = OperatorsData(deploymentConfig.operatorsData);
        curatedGateFactory = CuratedGateFactory(
            deploymentConfig.curatedGateFactory
        );
        curatedGates = deploymentConfig.curatedGates;
    }

    function handleStakingLimit() public {
        address agent = stakingRouter.getRoleMember(
            stakingRouter.DEFAULT_ADMIN_ROLE(),
            0
        );
        IACL acl = IACL(IKernel(lido.kernel()).acl());
        bytes32 role = lido.STAKING_CONTROL_ROLE();
        vm.prank(acl.getPermissionManager(address(lido), role));
        acl.grantPermission(agent, address(lido), role);

        vm.prank(agent);
        lido.removeStakingLimit();
    }

    function handleBunkerMode() public {
        IWithdrawalQueue wq = IWithdrawalQueue(locator.withdrawalQueue());
        if (wq.isBunkerModeActive()) {
            vm.prank(wq.getRoleMember(wq.ORACLE_ROLE(), 0));
            wq.onOracleReport(false, 0, 0);
        }
    }

    function hugeDeposit() internal {
        // It's impossible to process deposits if withdrawal requests amount is more than the buffered ether,
        // so we need to make sure that the buffered ether is enough by submitting this tremendous amount.
        handleStakingLimit();
        handleBunkerMode();

        address whale = address(100499);
        vm.prank(whale);
        vm.deal(whale, 1e7 ether);
        lido.submit{ value: 1e7 ether }(address(0));
    }

    function findModule() internal view returns (uint256) {
        uint256[] memory ids = stakingRouter.getStakingModuleIds();
        for (uint256 i = ids.length - 1; i > 0; i--) {
            IStakingRouter.StakingModule memory moduleInfo = stakingRouter
                .getStakingModule(ids[i]);
            if (moduleInfo.stakingModuleAddress == address(module)) {
                return ids[i];
            }
        }
        revert ModuleNotFound();
    }

    function addNodeOperator(
        address from,
        uint256 keysCount
    ) internal returns (uint256 nodeOperatorId) {
        (bytes memory keys, bytes memory signatures) = new Utilities()
            .keysSignatures(keysCount);
        uint256 amount = accounting.getBondAmountByKeysCount(keysCount, 0);
        vm.deal(from, amount);

        vm.prank(from);
        nodeOperatorId = permissionlessGate.addNodeOperatorETH{
            value: amount
        }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
    }

    function getDepositableNodeOperator(
        address nodeOperatorAddress
    ) internal returns (uint256 noId, uint256 keysCount) {
        module.cleanDepositQueue({ maxItems: 2 * module.getNonce() });
        for (uint256 i = 0; i <= module.QUEUE_LOWEST_PRIORITY(); ++i) {
            (uint128 head, ) = module.depositQueuePointers(i);
            Batch batch = module.depositQueueItem(i, head);
            if (!batch.isNil()) {
                return (batch.noId(), batch.keys());
            }
        }
        keysCount = 5;
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
    }

    function getDepositedNodeOperator(
        address nodeOperatorAddress,
        uint256 keysCount
    ) internal returns (uint256 noId) {
        uint256 nosCount = module.getNodeOperatorsCount();
        for (; noId < nosCount; ++noId) {
            NodeOperator memory no = module.getNodeOperator(noId);
            if (no.totalDepositedKeys - no.totalWithdrawnKeys >= keysCount) {
                return noId;
            }
        }
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
        (, , uint256 depositableValidatorsCount) = module
            .getStakingModuleSummary();
        vm.startPrank(address(stakingRouter));
        // potentially time-consuming or reverting due to block/tx gas limit
        module.obtainDepositData(depositableValidatorsCount, "");
        vm.stopPrank();
    }

    function getDepositedNodeOperatorWithSequentialActiveKeys(
        address nodeOperatorAddress,
        uint256 keysCount
    ) internal returns (uint256 noId, uint256 startIndex) {
        uint256 nosCount = module.getNodeOperatorsCount();
        for (; noId < nosCount; ++noId) {
            NodeOperator memory no = module.getNodeOperator(noId);
            uint256 activeKeys = no.totalDepositedKeys - no.totalWithdrawnKeys;
            if (activeKeys >= keysCount) {
                uint256 sequentialKeys = 0;
                for (uint256 i = 0; i < no.totalDepositedKeys; ++i) {
                    if (!module.isValidatorWithdrawn(noId, i)) {
                        sequentialKeys++;
                    } else {
                        sequentialKeys = 0;
                    }
                    if (sequentialKeys == keysCount) {
                        return (noId, i - (keysCount - 1));
                    }
                }
            }
        }
        noId = addNodeOperator(nodeOperatorAddress, keysCount);
        (, , uint256 depositableValidatorsCount) = module
            .getStakingModuleSummary();
        vm.startPrank(address(stakingRouter));
        // potentially time-consuming or reverting due to block/tx gas limit
        module.obtainDepositData(depositableValidatorsCount, "");
        vm.stopPrank();
        return (noId, 0);
    }
}
