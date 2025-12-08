// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script, VmSafe } from "forge-std/Script.sol";

import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";
import { CuratedModule } from "../../src/CuratedModule.sol";
import { Accounting } from "../../src/Accounting.sol";
import { FeeDistributor } from "../../src/FeeDistributor.sol";
import { Ejector } from "../../src/Ejector.sol";
import { ValidatorStrikes } from "../../src/ValidatorStrikes.sol";
import { FeeOracle } from "../../src/FeeOracle.sol";
import { Verifier } from "../../src/Verifier.sol";
import { ParametersRegistry } from "../../src/ParametersRegistry.sol";
import { ExitPenalties } from "../../src/ExitPenalties.sol";
import { OperatorsData } from "../../src/OperatorsData.sol";
import { CuratedGate } from "../../src/CuratedGate.sol";
import { CuratedGateFactory } from "../../src/CuratedGateFactory.sol";

import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";
import { IGateSealFactory } from "../../src/interfaces/IGateSealFactory.sol";
import { BaseOracle } from "../../src/lib/base-oracle/BaseOracle.sol";
import { IVerifier } from "../../src/interfaces/IVerifier.sol";
import { IParametersRegistry } from "../../src/interfaces/IParametersRegistry.sol";
import { IBondCurve } from "../../src/interfaces/IBondCurve.sol";
import { IStakingRouter } from "../../src/interfaces/IStakingRouter.sol";

import { JsonObj, Json } from "../utils/Json.sol";
import { Dummy } from "../utils/Dummy.sol";
import { CommonScriptUtils } from "../utils/Common.sol";
import { GIndex } from "../../src/lib/GIndex.sol";
import { Slot } from "../../src/lib/Types.sol";

struct GateCurveParams {
    uint256 keyRemovalCharge;
    uint256 generalDelayedPenaltyAdditionalFine;
    uint256 keysLimit;
    uint256[2][] avgPerfLeewayData;
    uint256[2][] rewardShareData;
    uint256 strikesLifetimeFrames;
    uint256 strikesThreshold;
    uint256 queuePriority;
    uint256 queueMaxDeposits;
    uint256 badPerformancePenalty;
    uint256 attestationsWeight;
    uint256 blocksWeight;
    uint256 syncWeight;
    uint256 allowedExitDelay;
    uint256 exitDelayFee;
    uint256 maxWithdrawalRequestFee;
}

struct CuratedGateConfig {
    uint256[2][] bondCurve;
    bytes32 treeRoot;
    string treeCid;
    GateCurveParams params;
}

struct CuratedDeployParams {
    // Lido addresses
    address lidoLocatorAddress;
    address aragonAgent;
    address easyTrackEVMScriptExecutor;
    address proxyAdmin;
    // Oracle
    uint256 secondsPerSlot;
    uint256 slotsPerEpoch;
    uint256 clGenesisTime;
    uint256 oracleReportEpochsPerFrame;
    uint256 fastLaneLengthSlots;
    uint256 consensusVersion;
    address[] oracleMembers;
    uint256 hashConsensusQuorum;
    // Verifier
    uint256 slotsPerHistoricalRoot;
    GIndex gIFirstWithdrawal;
    GIndex gIFirstValidator;
    GIndex gIFirstHistoricalSummary;
    GIndex gIFirstBlockRootInSummary;
    GIndex gIFirstBalanceNode;
    GIndex gIFirstPendingConsolidation;
    uint256 verifierFirstSupportedSlot;
    uint256 capellaSlot;
    // Accounting
    uint256[2][] defaultBondCurve;
    uint256 minBondLockPeriod;
    uint256 maxBondLockPeriod;
    uint256 bondLockPeriod;
    address setResetBondCurveAddress;
    address chargePenaltyRecipient;
    // Module
    uint256 stakingModuleId;
    bytes32 moduleType;
    address generalDelayedPenaltyReporter;
    // ParametersRegistry
    uint256 queueLowestPriority;
    uint256 defaultKeyRemovalCharge;
    uint256 defaultGeneralDelayedPenaltyAdditionalFine;
    uint256 defaultKeysLimit;
    uint256 defaultAvgPerfLeewayBP;
    uint256 defaultRewardShareBP;
    uint256 defaultStrikesLifetimeFrames;
    uint256 defaultStrikesThreshold;
    uint256 defaultQueuePriority;
    uint256 defaultQueueMaxDeposits;
    uint256 defaultBadPerformancePenalty;
    uint256 defaultAttestationsWeight;
    uint256 defaultBlocksWeight;
    uint256 defaultSyncWeight;
    uint256 defaultAllowedExitDelay;
    uint256 defaultExitDelayFee;
    uint256 defaultMaxWithdrawalRequestFee;
    // Curated gates
    CuratedGateConfig[] curatedGates;
    // GateSeal
    address gateSealFactory;
    address sealingCommittee;
    uint256 sealDuration;
    uint256 sealExpiryTimestamp;
    // DG
    address resealManager;
    // Testnet stuff
    address secondAdminAddress;
}

abstract contract DeployBase is Script {
    string internal gitRef;
    CuratedDeployParams internal config;
    string internal artifactDir;
    string internal chainName;
    uint256 internal chainId;
    ILidoLocator internal locator;

    address internal deployer;
    CuratedModule public curatedModule;
    Accounting public accounting;
    FeeOracle public oracle;
    FeeDistributor public feeDistributor;
    ExitPenalties public exitPenalties;
    Ejector public ejector;
    ValidatorStrikes public strikes;
    Verifier public verifier;
    HashConsensus public hashConsensus;
    ParametersRegistry public parametersRegistry;
    OperatorsData public operatorsData;
    CuratedGateFactory public curatedGateFactory;
    address[] public curatedGateInstances;
    address internal curatedGateImpl;
    address public gateSeal;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error HashConsensusMismatch();
    error CannotBeUsedInMainnet();
    error InvalidSecondAdmin();
    error InvalidInput(string reason);

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function _setUp() internal {
        vm.label(config.aragonAgent, "ARAGON_AGENT_ADDRESS");
        vm.label(config.lidoLocatorAddress, "LIDO_LOCATOR");
        vm.label(config.easyTrackEVMScriptExecutor, "EVM_SCRIPT_EXECUTOR");
        locator = ILidoLocator(config.lidoLocatorAddress);
    }

    function run(string memory _gitRef) external virtual {
        gitRef = _gitRef;
        if (chainId != block.chainid) {
            revert ChainIdMismatch({
                actual: block.chainid,
                expected: chainId
            });
        }
        HashConsensus accountingConsensus = HashConsensus(
            BaseOracle(locator.accountingOracle()).getConsensusContract()
        );
        (address[] memory members, ) = accountingConsensus.getMembers();
        uint256 quorum = accountingConsensus.getQuorum();
        if (block.chainid == 1) {
            if (
                keccak256(abi.encode(config.oracleMembers)) !=
                keccak256(abi.encode(members)) ||
                config.hashConsensusQuorum != quorum
            ) {
                revert HashConsensusMismatch();
            }
        }
        artifactDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/local/"));

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");
        uint256 gatesCount = config.curatedGates.length;
        uint256[] memory curatedCurveIds = new uint256[](gatesCount);

        {
            ParametersRegistry parametersRegistryImpl = new ParametersRegistry(
                config.queueLowestPriority
            );
            parametersRegistry = ParametersRegistry(
                _deployProxy(config.proxyAdmin, address(parametersRegistryImpl))
            );

            Dummy dummyImpl = new Dummy();

            curatedModule = CuratedModule(
                _deployProxy(deployer, address(dummyImpl))
            );

            accounting = Accounting(_deployProxy(deployer, address(dummyImpl)));

            oracle = FeeOracle(_deployProxy(deployer, address(dummyImpl)));

            FeeDistributor feeDistributorImpl = new FeeDistributor({
                stETH: locator.lido(),
                accounting: address(accounting),
                oracle: address(oracle)
            });
            feeDistributor = FeeDistributor(
                _deployProxy(config.proxyAdmin, address(feeDistributorImpl))
            );

            // prettier-ignore
            verifier = new Verifier({
                withdrawalAddress: locator.withdrawalVault(),
                module: address(curatedModule),
                slotsPerEpoch: uint64(config.slotsPerEpoch),
                slotsPerHistoricalRoot: uint64(config.slotsPerHistoricalRoot),
                gindices: IVerifier.GIndices({
                    gIFirstWithdrawalPrev: config.gIFirstWithdrawal,
                    gIFirstWithdrawalCurr: config.gIFirstWithdrawal,
                    gIFirstValidatorPrev: config.gIFirstValidator,
                    gIFirstValidatorCurr: config.gIFirstValidator,
                    gIFirstHistoricalSummaryPrev: config.gIFirstHistoricalSummary,
                    gIFirstHistoricalSummaryCurr: config.gIFirstHistoricalSummary,
                    gIFirstBlockRootInSummaryPrev: config.gIFirstBlockRootInSummary,
                    gIFirstBlockRootInSummaryCurr: config.gIFirstBlockRootInSummary,
                    gIFirstBalanceNodePrev: config.gIFirstBalanceNode,
                    gIFirstBalanceNodeCurr: config.gIFirstBalanceNode,
                    gIFirstPendingConsolidationPrev: config.gIFirstPendingConsolidation,
                    gIFirstPendingConsolidationCurr: config.gIFirstPendingConsolidation
                }),
                firstSupportedSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                pivotSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                capellaSlot: Slot.wrap(uint64(config.capellaSlot)),
                admin: deployer
            });

            parametersRegistry.initialize({
                admin: deployer,
                data: IParametersRegistry.InitializationData({
                    defaultKeyRemovalCharge: config.defaultKeyRemovalCharge,
                    defaultGeneralDelayedPenaltyAdditionalFine: config
                        .defaultGeneralDelayedPenaltyAdditionalFine,
                    defaultKeysLimit: config.defaultKeysLimit,
                    defaultRewardShare: config.defaultRewardShareBP,
                    defaultPerformanceLeeway: config.defaultAvgPerfLeewayBP,
                    defaultStrikesLifetime: config.defaultStrikesLifetimeFrames,
                    defaultStrikesThreshold: config.defaultStrikesThreshold,
                    defaultQueuePriority: config.defaultQueuePriority,
                    defaultQueueMaxDeposits: config.defaultQueueMaxDeposits,
                    defaultBadPerformancePenalty: config
                        .defaultBadPerformancePenalty,
                    defaultAttestationsWeight: config.defaultAttestationsWeight,
                    defaultBlocksWeight: config.defaultBlocksWeight,
                    defaultSyncWeight: config.defaultSyncWeight,
                    defaultAllowedExitDelay: config.defaultAllowedExitDelay,
                    defaultExitDelayFee: config.defaultExitDelayFee,
                    defaultMaxWithdrawalRequestFee: config
                        .defaultMaxWithdrawalRequestFee
                })
            });

            Accounting accountingImpl = new Accounting({
                lidoLocator: config.lidoLocatorAddress,
                module: address(curatedModule),
                feeDistributor: address(feeDistributor),
                minBondLockPeriod: config.minBondLockPeriod,
                maxBondLockPeriod: config.maxBondLockPeriod
            });

            {
                OssifiableProxy accountingProxy = OssifiableProxy(
                    payable(address(accounting))
                );
                accountingProxy.proxy__upgradeTo(address(accountingImpl));
                accountingProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            IBondCurve.BondCurveIntervalInput[]
                memory defaultBondCurve = CommonScriptUtils
                    .arraysToBondCurveIntervalsInputs(config.defaultBondCurve);
            accounting.initialize({
                bondCurve: defaultBondCurve,
                admin: deployer,
                bondLockPeriod: config.bondLockPeriod,
                _chargePenaltyRecipient: config.chargePenaltyRecipient
            });

            accounting.grantRole(
                accounting.MANAGE_BOND_CURVES_ROLE(),
                address(deployer)
            );

            for (uint256 i = 0; i < gatesCount; i++) {
                CuratedGateConfig storage gateConfig = config.curatedGates[i];
                // default curve if no values
                uint256 curveId = 0;
                if (gateConfig.bondCurve.length != 0) {
                    IBondCurve.BondCurveIntervalInput[]
                        memory curatedGateBondCurve = CommonScriptUtils
                            .arraysToBondCurveIntervalsInputs(
                                gateConfig.bondCurve
                            );
                    curveId = accounting.addBondCurve(curatedGateBondCurve);
                }
                curatedCurveIds[i] = curveId;

                GateCurveParams storage params = gateConfig.params;
                parametersRegistry.setKeyRemovalCharge(
                    curveId,
                    params.keyRemovalCharge
                );
                parametersRegistry.setGeneralDelayedPenaltyAdditionalFine(
                    curveId,
                    params.generalDelayedPenaltyAdditionalFine
                );
                parametersRegistry.setKeysLimit(curveId, params.keysLimit);
                if (params.avgPerfLeewayData.length > 0) {
                    parametersRegistry.setPerformanceLeewayData(
                        curveId,
                        CommonScriptUtils.arraysToKeyIndexValueIntervals(
                            params.avgPerfLeewayData
                        )
                    );
                }
                if (params.rewardShareData.length > 0) {
                    parametersRegistry.setRewardShareData(
                        curveId,
                        CommonScriptUtils.arraysToKeyIndexValueIntervals(
                            params.rewardShareData
                        )
                    );
                }
                parametersRegistry.setStrikesParams(
                    curveId,
                    params.strikesLifetimeFrames,
                    params.strikesThreshold
                );
                parametersRegistry.setQueueConfig(
                    curveId,
                    uint32(params.queuePriority),
                    uint32(params.queueMaxDeposits)
                );
                parametersRegistry.setBadPerformancePenalty(
                    curveId,
                    params.badPerformancePenalty
                );
                parametersRegistry.setPerformanceCoefficients(
                    curveId,
                    params.attestationsWeight,
                    params.blocksWeight,
                    params.syncWeight
                );
                parametersRegistry.setAllowedExitDelay(
                    curveId,
                    params.allowedExitDelay
                );
                parametersRegistry.setExitDelayFee(
                    curveId,
                    params.exitDelayFee
                );
                parametersRegistry.setMaxWithdrawalRequestFee(
                    curveId,
                    params.maxWithdrawalRequestFee
                );
            }
            accounting.revokeRole(
                accounting.MANAGE_BOND_CURVES_ROLE(),
                address(deployer)
            );

            exitPenalties = ExitPenalties(
                _deployProxy(deployer, address(dummyImpl))
            );

            CuratedModule curatedModuleImpl = new CuratedModule({
                moduleType: config.moduleType,
                lidoLocator: config.lidoLocatorAddress,
                parametersRegistry: address(parametersRegistry),
                accounting: address(accounting),
                exitPenalties: address(exitPenalties)
            });

            {
                OssifiableProxy moduleProxy = OssifiableProxy(
                    payable(address(curatedModule))
                );
                moduleProxy.proxy__upgradeTo(address(curatedModuleImpl));
                moduleProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            curatedModule.initialize({ admin: deployer });

            ValidatorStrikes strikesImpl = new ValidatorStrikes({
                module: address(curatedModule),
                oracle: address(oracle),
                exitPenalties: address(exitPenalties),
                parametersRegistry: address(parametersRegistry)
            });

            strikes = ValidatorStrikes(
                _deployProxy(config.proxyAdmin, address(strikesImpl))
            );

            ExitPenalties exitPenaltiesImpl = new ExitPenalties(
                address(curatedModule),
                address(parametersRegistry),
                address(strikes)
            );

            {
                OssifiableProxy exitPenaltiesProxy = OssifiableProxy(
                    payable(address(exitPenalties))
                );
                exitPenaltiesProxy.proxy__upgradeTo(address(exitPenaltiesImpl));
                exitPenaltiesProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            ejector = new Ejector(
                address(curatedModule),
                address(strikes),
                config.stakingModuleId,
                deployer
            );

            strikes.initialize(deployer, address(ejector));

            address operatorsDataImpl = address(
                new OperatorsData(locator.stakingRouter())
            );
            operatorsData = OperatorsData(
                _deployProxy(config.proxyAdmin, operatorsDataImpl)
            );
            operatorsData.initialize(deployer);

            curatedGateImpl = address(
                new CuratedGate(
                    address(curatedModule),
                    config.stakingModuleId,
                    address(operatorsData)
                )
            );

            curatedGateFactory = new CuratedGateFactory(curatedGateImpl);

            curatedGateInstances = _deployCuratedGates(
                curatedCurveIds,
                address(curatedGateFactory)
            );

            feeDistributor.initialize({
                admin: address(deployer),
                _rebateRecipient: config.aragonAgent
            });

            hashConsensus = new HashConsensus({
                slotsPerEpoch: config.slotsPerEpoch,
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime,
                epochsPerFrame: config.oracleReportEpochsPerFrame,
                fastLaneLengthSlots: config.fastLaneLengthSlots,
                admin: address(deployer),
                reportProcessor: address(oracle)
            });
            hashConsensus.grantRole(
                hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(),
                config.aragonAgent
            );
            hashConsensus.grantRole(
                hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(),
                address(deployer)
            );
            for (uint256 i = 0; i < config.oracleMembers.length; i++) {
                hashConsensus.addMember(
                    config.oracleMembers[i],
                    config.hashConsensusQuorum
                );
            }
            hashConsensus.revokeRole(
                hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(),
                address(deployer)
            );

            FeeOracle oracleImpl = new FeeOracle({
                feeDistributor: address(feeDistributor),
                strikes: address(strikes),
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime
            });

            {
                OssifiableProxy oracleProxy = OssifiableProxy(
                    payable(address(oracle))
                );
                oracleProxy.proxy__upgradeTo(address(oracleImpl));
                oracleProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            oracle.initialize({
                admin: address(deployer),
                consensusContract: address(hashConsensus),
                consensusVersion: config.consensusVersion
            });

            if (config.gateSealFactory != address(0)) {
                uint256 baseSealables = 5;
                uint256 sealablesCount = baseSealables +
                    curatedGateInstances.length;
                address[] memory sealables = new address[](sealablesCount);
                sealables[0] = address(curatedModule);
                sealables[1] = address(accounting);
                sealables[2] = address(oracle);
                sealables[3] = address(verifier);
                sealables[4] = address(ejector);
                for (uint256 i = 0; i < curatedGateInstances.length; ++i) {
                    sealables[baseSealables + i] = curatedGateInstances[i];
                }
                gateSeal = _deployGateSeal(sealables);

                curatedModule.grantRole(curatedModule.PAUSE_ROLE(), gateSeal);
                accounting.grantRole(accounting.PAUSE_ROLE(), gateSeal);
                oracle.grantRole(oracle.PAUSE_ROLE(), gateSeal);
                verifier.grantRole(verifier.PAUSE_ROLE(), gateSeal);
                ejector.grantRole(ejector.PAUSE_ROLE(), gateSeal);
                for (uint256 i = 0; i < curatedGateInstances.length; ++i) {
                    CuratedGate gate = CuratedGate(curatedGateInstances[i]);
                    gate.grantRole(gate.PAUSE_ROLE(), gateSeal);
                }
            }

            curatedModule.grantRole(
                curatedModule.PAUSE_ROLE(),
                config.resealManager
            );
            curatedModule.grantRole(
                curatedModule.RESUME_ROLE(),
                config.resealManager
            );
            accounting.grantRole(accounting.PAUSE_ROLE(), config.resealManager);
            accounting.grantRole(
                accounting.RESUME_ROLE(),
                config.resealManager
            );
            oracle.grantRole(oracle.PAUSE_ROLE(), config.resealManager);
            oracle.grantRole(oracle.RESUME_ROLE(), config.resealManager);
            verifier.grantRole(verifier.PAUSE_ROLE(), config.resealManager);
            verifier.grantRole(verifier.RESUME_ROLE(), config.resealManager);
            ejector.grantRole(ejector.PAUSE_ROLE(), config.resealManager);
            ejector.grantRole(ejector.RESUME_ROLE(), config.resealManager);

            accounting.grantRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(config.setResetBondCurveAddress)
            );

            curatedModule.grantRole(
                curatedModule.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
                config.generalDelayedPenaltyReporter
            );
            curatedModule.grantRole(
                curatedModule.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            curatedModule.grantRole(
                curatedModule.VERIFIER_ROLE(),
                address(verifier)
            );
            curatedModule.grantRole(
                curatedModule.SUBMIT_WITHDRAWALS_ROLE(),
                address(verifier)
            );
            curatedModule.grantRole(
                curatedModule.SUBMIT_WITHDRAWALS_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            if (config.secondAdminAddress != address(0)) {
                if (config.secondAdminAddress == deployer) {
                    revert InvalidSecondAdmin();
                }
                _grantSecondAdmins();
            }

            curatedModule.grantRole(
                curatedModule.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            curatedModule.revokeRole(
                curatedModule.DEFAULT_ADMIN_ROLE(),
                deployer
            );

            ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            ejector.revokeRole(ejector.DEFAULT_ADMIN_ROLE(), deployer);

            parametersRegistry.grantRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            parametersRegistry.revokeRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
                deployer
            );

            for (uint256 i = 0; i < curatedGateInstances.length; i++) {
                CuratedGate gate = CuratedGate(curatedGateInstances[i]);
                gate.grantRole(gate.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
                gate.revokeRole(gate.DEFAULT_ADMIN_ROLE(), deployer);
            }

            operatorsData.grantRole(
                operatorsData.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            operatorsData.revokeRole(
                operatorsData.DEFAULT_ADMIN_ROLE(),
                deployer
            );

            verifier.grantRole(
                verifier.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            verifier.revokeRole(verifier.DEFAULT_ADMIN_ROLE(), deployer);

            accounting.grantRole(
                accounting.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            accounting.revokeRole(accounting.DEFAULT_ADMIN_ROLE(), deployer);

            hashConsensus.grantRole(
                hashConsensus.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            hashConsensus.revokeRole(
                hashConsensus.DEFAULT_ADMIN_ROLE(),
                deployer
            );

            oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);

            feeDistributor.grantRole(
                feeDistributor.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            feeDistributor.revokeRole(
                feeDistributor.DEFAULT_ADMIN_ROLE(),
                deployer
            );

            strikes.grantRole(strikes.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            strikes.revokeRole(strikes.DEFAULT_ADMIN_ROLE(), deployer);

            JsonObj memory deployJson = Json.newObj("artifact");
            deployJson.set("ChainId", chainId);
            deployJson.set("CuratedModule", address(curatedModule));
            deployJson.set("CuratedModuleImpl", address(curatedModuleImpl));
            deployJson.set("ParametersRegistry", address(parametersRegistry));
            deployJson.set(
                "ParametersRegistryImpl",
                address(parametersRegistryImpl)
            );
            deployJson.set("Accounting", address(accounting));
            deployJson.set("AccountingImpl", address(accountingImpl));
            deployJson.set("FeeOracle", address(oracle));
            deployJson.set("FeeOracleImpl", address(oracleImpl));
            deployJson.set("FeeDistributor", address(feeDistributor));
            deployJson.set("FeeDistributorImpl", address(feeDistributorImpl));
            deployJson.set("ExitPenalties", address(exitPenalties));
            deployJson.set("ExitPenaltiesImpl", address(exitPenaltiesImpl));
            deployJson.set("Ejector", address(ejector));
            deployJson.set("ValidatorStrikes", address(strikes));
            deployJson.set("ValidatorStrikesImpl", address(strikesImpl));
            deployJson.set("HashConsensus", address(hashConsensus));
            deployJson.set("Verifier", address(verifier));
            deployJson.set("OperatorsData", address(operatorsData));
            deployJson.set("OperatorsDataImpl", address(operatorsDataImpl));
            deployJson.set("CuratedGateFactory", address(curatedGateFactory));
            deployJson.set("CuratedGates", curatedGateInstances);
            deployJson.set("LidoLocator", config.lidoLocatorAddress);
            deployJson.set("GateSeal", address(gateSeal));
            deployJson.set("DeployParams", abi.encode(config));
            deployJson.set("CuratedDeployParams", abi.encode(config));
            deployJson.set("git-ref", gitRef);
            vm.writeJson(deployJson.str, _deployJsonFilename());
        }

        vm.stopBroadcast();
    }

    function _deployCuratedGates(
        uint256[] memory curveIds,
        address gateFactoryAddress
    ) internal returns (address[] memory gates) {
        uint256 gateCount = curveIds.length;
        if (gateCount == 0) {
            return gates;
        }
        gates = new address[](gateCount);

        if (gateFactoryAddress == address(0)) {
            revert InvalidInput("curated gate factory address is zero");
        }
        CuratedGateFactory gateFactory = CuratedGateFactory(gateFactoryAddress);

        for (uint256 i = 0; i < gateCount; i++) {
            uint256 gateCurveId = curveIds[i];
            CuratedGateConfig storage gateConfig = config.curatedGates[i];
            CuratedGate gate = CuratedGate(
                gateFactory.create({
                    curveId: gateCurveId,
                    treeRoot: gateConfig.treeRoot,
                    treeCid: gateConfig.treeCid,
                    admin: deployer
                })
            );

            {
                OssifiableProxy gateProxy = OssifiableProxy(
                    payable(address(gate))
                );
                gateProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            gates[i] = address(gate);

            curatedModule.grantRole(
                curatedModule.CREATE_NODE_OPERATOR_ROLE(),
                address(gate)
            );
            if (gateCurveId != accounting.DEFAULT_BOND_CURVE_ID()) {
                accounting.grantRole(
                    accounting.SET_BOND_CURVE_ROLE(),
                    address(gate)
                );
            }
            operatorsData.grantRole(operatorsData.SETTER_ROLE(), address(gate));
            gate.grantRole(gate.PAUSE_ROLE(), config.resealManager);
            gate.grantRole(gate.RESUME_ROLE(), config.resealManager);
            gate.grantRole(
                gate.SET_TREE_ROLE(),
                config.easyTrackEVMScriptExecutor
            );
        }
        return gates;
    }

    function _deployProxy(
        address admin,
        address implementation
    ) internal returns (address) {
        OssifiableProxy proxy = new OssifiableProxy({
            implementation_: implementation,
            data_: new bytes(0),
            admin_: admin
        });

        return address(proxy);
    }

    function _deployGateSeal(
        address[] memory sealables
    ) internal returns (address) {
        IGateSealFactory gateSealFactory = IGateSealFactory(
            config.gateSealFactory
        );

        address committee = config.sealingCommittee == address(0)
            ? deployer
            : config.sealingCommittee;

        vm.recordLogs();
        gateSealFactory.create_gate_seal({
            sealingCommittee: committee,
            sealDurationSeconds: config.sealDuration,
            sealables: sealables,
            expiryTimestamp: config.sealExpiryTimestamp
        });
        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        return abi.decode(entries[0].data, (address));
    }

    function _deployJsonFilename() internal view returns (string memory) {
        return
            string(
                abi.encodePacked(artifactDir, "deploy-", chainName, ".json")
            );
    }

    function _grantSecondAdmins() internal {
        if (keccak256(abi.encodePacked(chainName)) == keccak256("mainnet")) {
            revert CannotBeUsedInMainnet();
        }
        curatedModule.grantRole(
            curatedModule.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        accounting.grantRole(
            accounting.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        oracle.grantRole(
            oracle.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        feeDistributor.grantRole(
            feeDistributor.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        hashConsensus.grantRole(
            hashConsensus.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        parametersRegistry.grantRole(
            parametersRegistry.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        operatorsData.grantRole(
            operatorsData.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        for (uint256 i = 0; i < curatedGateInstances.length; i++) {
            CuratedGate gate = CuratedGate(curatedGateInstances[i]);
            gate.grantRole(
                gate.DEFAULT_ADMIN_ROLE(),
                config.secondAdminAddress
            );
        }
        ejector.grantRole(
            ejector.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        verifier.grantRole(
            verifier.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        strikes.grantRole(
            strikes.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
    }

    function _nextStakingModuleId(
        address locatorAddress
    ) internal view returns (uint256) {
        return
            IStakingRouter(ILidoLocator(locatorAddress).stakingRouter())
                .getStakingModulesCount() + 1;
    }
}
