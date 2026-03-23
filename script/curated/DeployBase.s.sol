// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

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
import { MetaRegistry } from "../../src/MetaRegistry.sol";
import { CuratedGate } from "../../src/CuratedGate.sol";
import { MerkleGateFactory } from "../../src/MerkleGateFactory.sol";

import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";
import { IGateSealFactory } from "../../src/interfaces/IGateSealFactory.sol";
import { BaseOracle } from "../../src/lib/base-oracle/BaseOracle.sol";
import { IVerifier } from "../../src/interfaces/IVerifier.sol";
import { IParametersRegistry } from "../../src/interfaces/IParametersRegistry.sol";
import { IBondCurve } from "../../src/interfaces/IBondCurve.sol";

import { JsonObj, Json } from "../utils/Json.sol";
import { Dummy } from "../utils/Dummy.sol";
import { CommonScriptUtils } from "../utils/Common.sol";
import { GIndex } from "../../src/lib/GIndex.sol";
import { Slot } from "../../src/lib/Types.sol";

struct GateCurveParams {
    IParametersRegistry.MarkedUint248 generalDelayedPenaltyAdditionalFine;
    IParametersRegistry.MarkedUint248 keysLimit;
    uint256[2][] avgPerfLeewayData;
    uint256[2][] rewardShareData;
    IParametersRegistry.MarkedUint248 strikesLifetimeFrames;
    IParametersRegistry.MarkedUint248 strikesThreshold;
    IParametersRegistry.MarkedUint248 badPerformancePenalty;
    IParametersRegistry.MarkedUint248 attestationsWeight;
    IParametersRegistry.MarkedUint248 blocksWeight;
    IParametersRegistry.MarkedUint248 syncWeight;
    IParametersRegistry.MarkedUint248 metaRegistryBondCurveWeight;
    IParametersRegistry.MarkedUint248 allowedExitDelay;
    IParametersRegistry.MarkedUint248 exitDelayFee;
    IParametersRegistry.MarkedUint248 maxElWithdrawalRequestFee;
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
    uint256 verifierFirstSupportedSlot;
    uint256 capellaSlot;
    uint256 minWithdrawalRatio;
    // Accounting
    uint256[2][] defaultBondCurve;
    uint256 minBondLockPeriod;
    uint256 maxBondLockPeriod;
    uint256 bondLockPeriod;
    address chargePenaltyRecipient;
    // Module
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
    uint256 defaultMaxElWithdrawalRequestFee;
    address penaltiesManager;
    // Curated gates
    CuratedGateConfig[] curatedGates;
    address curatedGatePauseManager;
    // MetaRegistry
    address setOperatorInfoManager;
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
    MetaRegistry public metaRegistry;
    MerkleGateFactory public curatedGateFactory;
    address[] public curatedGateInstances;
    address internal curatedGateImpl;
    address public gateSeal;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error HashConsensusMismatch();
    error CannotBeUsedInMainnet();
    error InvalidSecondAdmin();
    error InvalidInput(string reason);

    function _m(uint256 v) internal pure returns (IParametersRegistry.MarkedUint248 memory) {
        return IParametersRegistry.MarkedUint248({ value: uint248(v), isValue: true });
    }

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
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });
        HashConsensus accountingConsensus = HashConsensus(
            BaseOracle(locator.accountingOracle()).getConsensusContract()
        );
        (address[] memory members, ) = accountingConsensus.getMembers();
        uint256 quorum = accountingConsensus.getQuorum();
        if (block.chainid == 1) {
            if (
                keccak256(abi.encode(config.oracleMembers)) != keccak256(abi.encode(members)) ||
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
            ParametersRegistry parametersRegistryImpl = new ParametersRegistry(config.queueLowestPriority);
            IParametersRegistry.InitializationData memory parametersRegistryData = IParametersRegistry
                .InitializationData({
                    defaultKeyRemovalCharge: config.defaultKeyRemovalCharge,
                    defaultGeneralDelayedPenaltyAdditionalFine: config.defaultGeneralDelayedPenaltyAdditionalFine,
                    defaultKeysLimit: config.defaultKeysLimit,
                    defaultRewardShare: config.defaultRewardShareBP,
                    defaultPerformanceLeeway: config.defaultAvgPerfLeewayBP,
                    defaultStrikesLifetime: config.defaultStrikesLifetimeFrames,
                    defaultStrikesThreshold: config.defaultStrikesThreshold,
                    defaultQueuePriority: config.defaultQueuePriority,
                    defaultQueueMaxDeposits: config.defaultQueueMaxDeposits,
                    defaultBadPerformancePenalty: config.defaultBadPerformancePenalty,
                    defaultAttestationsWeight: config.defaultAttestationsWeight,
                    defaultBlocksWeight: config.defaultBlocksWeight,
                    defaultSyncWeight: config.defaultSyncWeight,
                    defaultAllowedExitDelay: config.defaultAllowedExitDelay,
                    defaultExitDelayFee: config.defaultExitDelayFee,
                    defaultMaxElWithdrawalRequestFee: config.defaultMaxElWithdrawalRequestFee
                });
            parametersRegistry = ParametersRegistry(
                _deployProxy(
                    config.proxyAdmin,
                    address(parametersRegistryImpl),
                    abi.encodeCall(ParametersRegistry.initialize, (deployer, parametersRegistryData))
                )
            );

            Dummy dummyImpl = new Dummy();

            curatedModule = CuratedModule(_deployProxy(deployer, address(dummyImpl)));

            accounting = Accounting(_deployProxy(deployer, address(dummyImpl)));
            oracle = FeeOracle(_deployProxy(deployer, address(dummyImpl)));
            metaRegistry = MetaRegistry(_deployProxy(deployer, address(dummyImpl)));

            FeeDistributor feeDistributorImpl = new FeeDistributor({
                stETH: locator.lido(),
                accounting: address(accounting),
                oracle: address(oracle)
            });
            feeDistributor = FeeDistributor(
                _deployProxy(
                    config.proxyAdmin,
                    address(feeDistributorImpl),
                    abi.encodeCall(FeeDistributor.initialize, (deployer, config.aragonAgent))
                )
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
                    gIFirstBalanceNodeCurr: config.gIFirstBalanceNode
                }),
                firstSupportedSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                pivotSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                capellaSlot: Slot.wrap(uint64(config.capellaSlot)),
                minWithdrawalRatio: config.minWithdrawalRatio,
                admin: deployer
            });

            Accounting accountingImpl = new Accounting({
                lidoLocator: config.lidoLocatorAddress,
                module: address(curatedModule),
                feeDistributor: address(feeDistributor),
                minBondLockPeriod: config.minBondLockPeriod,
                maxBondLockPeriod: config.maxBondLockPeriod
            });

            IBondCurve.BondCurveIntervalInput[] memory defaultBondCurve = CommonScriptUtils
                .arraysToBondCurveIntervalsInputs(config.defaultBondCurve);
            {
                OssifiableProxy accountingProxy = OssifiableProxy(payable(address(accounting)));
                accountingProxy.proxy__upgradeToAndCall(
                    address(accountingImpl),
                    abi.encodeCall(
                        Accounting.initialize,
                        (defaultBondCurve, deployer, config.bondLockPeriod, config.chargePenaltyRecipient)
                    )
                );
                accountingProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            exitPenalties = ExitPenalties(_deployProxy(deployer, address(dummyImpl)));

            CuratedModule curatedModuleImpl = new CuratedModule({
                moduleType: config.moduleType,
                lidoLocator: config.lidoLocatorAddress,
                parametersRegistry: address(parametersRegistry),
                accounting: address(accounting),
                exitPenalties: address(exitPenalties),
                metaRegistry: address(metaRegistry)
            });

            {
                OssifiableProxy moduleProxy = OssifiableProxy(payable(address(curatedModule)));
                moduleProxy.proxy__upgradeToAndCall(
                    address(curatedModuleImpl),
                    abi.encodeCall(CuratedModule.initialize, (deployer))
                );
                moduleProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            MetaRegistry metaRegistryImpl = new MetaRegistry(address(curatedModule));

            {
                OssifiableProxy metaRegistryProxy = OssifiableProxy(payable(address(metaRegistry)));
                metaRegistryProxy.proxy__upgradeToAndCall(
                    address(metaRegistryImpl),
                    abi.encodeCall(MetaRegistry.initialize, (deployer))
                );
                metaRegistryProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            accounting.grantRole(accounting.MANAGE_BOND_CURVES_ROLE(), address(deployer));
            metaRegistry.grantRole(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE(), deployer);

            for (uint256 i = 0; i < gatesCount; i++) {
                CuratedGateConfig storage gateConfig = config.curatedGates[i];
                // default curve if no values
                uint256 curveId = 0;
                if (gateConfig.bondCurve.length != 0) {
                    IBondCurve.BondCurveIntervalInput[] memory curatedGateBondCurve = CommonScriptUtils
                        .arraysToBondCurveIntervalsInputs(gateConfig.bondCurve);
                    curveId = accounting.addBondCurve(curatedGateBondCurve);
                }
                curatedCurveIds[i] = curveId;

                GateCurveParams storage params = gateConfig.params;
                if (params.generalDelayedPenaltyAdditionalFine.isValue) {
                    parametersRegistry.setGeneralDelayedPenaltyAdditionalFine(
                        curveId,
                        params.generalDelayedPenaltyAdditionalFine.value
                    );
                }
                if (params.keysLimit.isValue) {
                    parametersRegistry.setKeysLimit(curveId, params.keysLimit.value);
                }
                if (params.avgPerfLeewayData.length > 0) {
                    parametersRegistry.setPerformanceLeewayData(
                        curveId,
                        CommonScriptUtils.arraysToKeyIndexValueIntervals(params.avgPerfLeewayData)
                    );
                }
                if (params.rewardShareData.length > 0) {
                    parametersRegistry.setRewardShareData(
                        curveId,
                        CommonScriptUtils.arraysToKeyIndexValueIntervals(params.rewardShareData)
                    );
                }
                if (params.strikesLifetimeFrames.isValue || params.strikesThreshold.isValue) {
                    parametersRegistry.setStrikesParams(
                        curveId,
                        params.strikesLifetimeFrames.value,
                        params.strikesThreshold.value
                    );
                }
                if (params.badPerformancePenalty.isValue) {
                    parametersRegistry.setBadPerformancePenalty(curveId, params.badPerformancePenalty.value);
                }
                if (params.attestationsWeight.isValue || params.blocksWeight.isValue || params.syncWeight.isValue) {
                    parametersRegistry.setPerformanceCoefficients(
                        curveId,
                        params.attestationsWeight.value,
                        params.blocksWeight.value,
                        params.syncWeight.value
                    );
                }
                if (params.metaRegistryBondCurveWeight.isValue) {
                    metaRegistry.setBondCurveWeight(curveId, params.metaRegistryBondCurveWeight.value);
                }
                if (params.allowedExitDelay.isValue) {
                    parametersRegistry.setAllowedExitDelay(curveId, params.allowedExitDelay.value);
                }
                if (params.exitDelayFee.isValue) {
                    parametersRegistry.setExitDelayFee(curveId, params.exitDelayFee.value);
                }
                if (params.maxElWithdrawalRequestFee.isValue) {
                    parametersRegistry.setMaxElWithdrawalRequestFee(curveId, params.maxElWithdrawalRequestFee.value);
                }
            }
            accounting.revokeRole(accounting.MANAGE_BOND_CURVES_ROLE(), address(deployer));
            metaRegistry.revokeRole(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE(), deployer);

            ValidatorStrikes strikesImpl = new ValidatorStrikes({
                module: address(curatedModule),
                oracle: address(oracle)
            });

            strikes = ValidatorStrikes(_deployProxy(deployer, address(new Dummy())));

            ExitPenalties exitPenaltiesImpl = new ExitPenalties(address(curatedModule), address(strikes));

            {
                OssifiableProxy exitPenaltiesProxy = OssifiableProxy(payable(address(exitPenalties)));
                exitPenaltiesProxy.proxy__upgradeTo(address(exitPenaltiesImpl));
                exitPenaltiesProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            ejector = new Ejector(address(curatedModule), address(strikes), deployer);

            {
                OssifiableProxy strikesProxy = OssifiableProxy(payable(address(strikes)));
                strikesProxy.proxy__upgradeToAndCall(
                    address(strikesImpl),
                    abi.encodeCall(ValidatorStrikes.initialize, (deployer, address(ejector)))
                );
                strikesProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            curatedGateImpl = address(new CuratedGate(address(curatedModule)));

            curatedGateFactory = new MerkleGateFactory(curatedGateImpl);

            curatedGateInstances = _deployCuratedGates(curatedCurveIds, address(curatedGateFactory));

            hashConsensus = new HashConsensus({
                slotsPerEpoch: config.slotsPerEpoch,
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime,
                epochsPerFrame: config.oracleReportEpochsPerFrame,
                fastLaneLengthSlots: config.fastLaneLengthSlots,
                admin: address(deployer),
                reportProcessor: address(oracle)
            });
            hashConsensus.grantRole(hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(), config.aragonAgent);
            hashConsensus.grantRole(hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(), address(deployer));
            for (uint256 i = 0; i < config.oracleMembers.length; i++) {
                hashConsensus.addMember(config.oracleMembers[i], config.hashConsensusQuorum);
            }
            hashConsensus.revokeRole(hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(), address(deployer));

            FeeOracle oracleImpl = new FeeOracle({
                feeDistributor: address(feeDistributor),
                strikes: address(strikes),
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime
            });

            {
                OssifiableProxy oracleProxy = OssifiableProxy(payable(address(oracle)));
                oracleProxy.proxy__upgradeToAndCall(
                    address(oracleImpl),
                    abi.encodeCall(FeeOracle.initialize, (deployer, address(hashConsensus), config.consensusVersion))
                );
                oracleProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            if (config.gateSealFactory != address(0)) {
                uint256 sealablesCount = 5;
                address[] memory sealables = new address[](sealablesCount);
                sealables[0] = address(curatedModule);
                sealables[1] = address(accounting);
                sealables[2] = address(oracle);
                sealables[3] = address(verifier);
                sealables[4] = address(ejector);
                gateSeal = _deployGateSeal(sealables);

                curatedModule.grantRole(curatedModule.PAUSE_ROLE(), gateSeal);
                accounting.grantRole(accounting.PAUSE_ROLE(), gateSeal);
                oracle.grantRole(oracle.PAUSE_ROLE(), gateSeal);
                verifier.grantRole(verifier.PAUSE_ROLE(), gateSeal);
                ejector.grantRole(ejector.PAUSE_ROLE(), gateSeal);
            }

            curatedModule.grantRole(curatedModule.PAUSE_ROLE(), config.resealManager);
            curatedModule.grantRole(curatedModule.RESUME_ROLE(), config.resealManager);
            accounting.grantRole(accounting.PAUSE_ROLE(), config.resealManager);
            accounting.grantRole(accounting.RESUME_ROLE(), config.resealManager);
            oracle.grantRole(oracle.PAUSE_ROLE(), config.resealManager);
            oracle.grantRole(oracle.RESUME_ROLE(), config.resealManager);
            verifier.grantRole(verifier.PAUSE_ROLE(), config.resealManager);
            verifier.grantRole(verifier.RESUME_ROLE(), config.resealManager);
            ejector.grantRole(ejector.PAUSE_ROLE(), config.resealManager);
            ejector.grantRole(ejector.RESUME_ROLE(), config.resealManager);

            metaRegistry.grantRole(metaRegistry.SET_OPERATOR_INFO_ROLE(), config.setOperatorInfoManager);
            metaRegistry.grantRole(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE(), config.easyTrackEVMScriptExecutor);

            parametersRegistry.grantRole(
                parametersRegistry.MANAGE_GENERAL_PENALTIES_AND_CHARGES_ROLE(),
                config.penaltiesManager
            );

            curatedModule.grantRole(
                curatedModule.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
                config.generalDelayedPenaltyReporter
            );
            curatedModule.grantRole(
                curatedModule.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            curatedModule.grantRole(curatedModule.VERIFIER_ROLE(), address(verifier));
            curatedModule.grantRole(curatedModule.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), address(verifier));
            curatedModule.grantRole(
                curatedModule.REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            if (config.secondAdminAddress != address(0)) {
                if (config.secondAdminAddress == deployer) revert InvalidSecondAdmin();
                _grantSecondAdmins();
            }

            curatedModule.grantRole(curatedModule.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            curatedModule.revokeRole(curatedModule.DEFAULT_ADMIN_ROLE(), deployer);

            ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            ejector.revokeRole(ejector.DEFAULT_ADMIN_ROLE(), deployer);

            parametersRegistry.grantRole(parametersRegistry.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            parametersRegistry.revokeRole(parametersRegistry.DEFAULT_ADMIN_ROLE(), deployer);

            for (uint256 i = 0; i < curatedGateInstances.length; i++) {
                CuratedGate gate = CuratedGate(curatedGateInstances[i]);
                gate.grantRole(gate.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
                gate.revokeRole(gate.DEFAULT_ADMIN_ROLE(), deployer);
            }

            metaRegistry.grantRole(metaRegistry.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            metaRegistry.revokeRole(metaRegistry.DEFAULT_ADMIN_ROLE(), deployer);

            verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            verifier.revokeRole(verifier.DEFAULT_ADMIN_ROLE(), deployer);

            accounting.grantRole(accounting.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            accounting.revokeRole(accounting.DEFAULT_ADMIN_ROLE(), deployer);

            hashConsensus.grantRole(hashConsensus.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            hashConsensus.revokeRole(hashConsensus.DEFAULT_ADMIN_ROLE(), deployer);

            oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            oracle.revokeRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);

            feeDistributor.grantRole(feeDistributor.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            feeDistributor.revokeRole(feeDistributor.DEFAULT_ADMIN_ROLE(), deployer);

            strikes.grantRole(strikes.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            strikes.revokeRole(strikes.DEFAULT_ADMIN_ROLE(), deployer);

            JsonObj memory deployJson = Json.newObj("artifact");
            deployJson.set("ChainId", chainId);
            deployJson.set("CuratedModule", address(curatedModule));
            deployJson.set("CuratedModuleImpl", address(curatedModuleImpl));
            deployJson.set("MetaRegistry", address(metaRegistry));
            deployJson.set("MetaRegistryImpl", address(metaRegistryImpl));
            deployJson.set("ParametersRegistry", address(parametersRegistry));
            deployJson.set("ParametersRegistryImpl", address(parametersRegistryImpl));
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
            deployJson.set("CuratedGateFactory", address(curatedGateFactory));
            deployJson.set("CuratedGateImpl", curatedGateImpl);
            deployJson.set("CuratedGates", curatedGateInstances);
            deployJson.set("LidoLocator", config.lidoLocatorAddress);
            deployJson.set("GateSeal", address(gateSeal));
            deployJson.set("DeployParams", abi.encode(config));
            deployJson.set("CuratedDeployParams", abi.encode(config));
            deployJson.set("git-ref", gitRef);
            if (!vm.exists(artifactDir)) {
                vm.createDir(artifactDir, true);
            }
            vm.writeJson(deployJson.str, _deployJsonFilename());
        }

        vm.stopBroadcast();
    }

    function _deployCuratedGates(
        uint256[] memory curveIds,
        address gateFactoryAddress
    ) internal returns (address[] memory gates) {
        uint256 gateCount = curveIds.length;
        if (gateCount == 0) return gates;
        gates = new address[](gateCount);

        if (gateFactoryAddress == address(0)) revert InvalidInput("curated gate factory address is zero");
        MerkleGateFactory gateFactory = MerkleGateFactory(gateFactoryAddress);

        for (uint256 i = 0; i < gateCount; i++) {
            uint256 gateCurveId = curveIds[i];
            CuratedGateConfig storage gateConfig = config.curatedGates[i];
            CuratedGate gate = CuratedGate(
                gateFactory.create(gateCurveId, gateConfig.treeRoot, gateConfig.treeCid, deployer)
            );

            {
                OssifiableProxy gateProxy = OssifiableProxy(payable(address(gate)));
                gateProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            gates[i] = address(gate);

            curatedModule.grantRole(curatedModule.CREATE_NODE_OPERATOR_ROLE(), address(gate));
            if (gateCurveId != accounting.DEFAULT_BOND_CURVE_ID()) {
                accounting.grantRole(accounting.SET_BOND_CURVE_ROLE(), address(gate));
            }
            metaRegistry.grantRole(metaRegistry.SET_OPERATOR_INFO_ROLE(), address(gate));
            gate.grantRole(gate.PAUSE_ROLE(), config.curatedGatePauseManager);
            gate.grantRole(gate.SET_TREE_ROLE(), config.easyTrackEVMScriptExecutor);
        }
        return gates;
    }

    function _deployProxy(address admin, address implementation) internal returns (address) {
        return _deployProxy(admin, implementation, new bytes(0));
    }

    function _deployProxy(address admin, address implementation, bytes memory initCalldata) internal returns (address) {
        OssifiableProxy proxy = new OssifiableProxy({
            implementation_: implementation,
            data_: initCalldata,
            admin_: admin
        });

        return address(proxy);
    }

    function _deployGateSeal(address[] memory sealables) internal returns (address) {
        IGateSealFactory gateSealFactory = IGateSealFactory(config.gateSealFactory);

        address committee = config.sealingCommittee == address(0) ? deployer : config.sealingCommittee;

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
        return string(abi.encodePacked(artifactDir, "deploy-", chainName, ".json"));
    }

    function _grantSecondAdmins() internal {
        if (keccak256(abi.encodePacked(chainName)) == keccak256("mainnet")) revert CannotBeUsedInMainnet();
        curatedModule.grantRole(curatedModule.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        accounting.grantRole(accounting.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        feeDistributor.grantRole(feeDistributor.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        hashConsensus.grantRole(hashConsensus.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        parametersRegistry.grantRole(parametersRegistry.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        metaRegistry.grantRole(metaRegistry.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        for (uint256 i = 0; i < curatedGateInstances.length; i++) {
            CuratedGate gate = CuratedGate(curatedGateInstances[i]);
            gate.grantRole(gate.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        }
        ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        strikes.grantRole(strikes.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
    }
}
