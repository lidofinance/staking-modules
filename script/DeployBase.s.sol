// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script, VmSafe } from "forge-std/Script.sol";

import { HashConsensus } from "../src/lib/base-oracle/HashConsensus.sol";
import { OssifiableProxy } from "../src/lib/proxy/OssifiableProxy.sol";
import { CSModule } from "../src/CSModule.sol";
import { Accounting } from "../src/Accounting.sol";
import { FeeDistributor } from "../src/FeeDistributor.sol";
import { Ejector } from "../src/Ejector.sol";
import { ValidatorStrikes } from "../src/ValidatorStrikes.sol";
import { FeeOracle } from "../src/FeeOracle.sol";
import { Verifier } from "../src/Verifier.sol";
import { IVerifier } from "../src/interfaces/IVerifier.sol";
import { PermissionlessGate } from "../src/PermissionlessGate.sol";
import { VettedGate } from "../src/VettedGate.sol";
import { ParametersRegistry } from "../src/ParametersRegistry.sol";

import { ILidoLocator } from "../src/interfaces/ILidoLocator.sol";
import { IGateSealFactory } from "../src/interfaces/IGateSealFactory.sol";
import { BaseOracle } from "../src/lib/base-oracle/BaseOracle.sol";
import { IParametersRegistry } from "../src/interfaces/IParametersRegistry.sol";
import { IBondCurve } from "../src/interfaces/IBondCurve.sol";

import { JsonObj, Json } from "./utils/Json.sol";
import { Dummy } from "./utils/Dummy.sol";
import { CommonScriptUtils } from "./utils/Common.sol";
import { GIndex } from "../src/lib/GIndex.sol";
import { Slot } from "../src/lib/Types.sol";
import { VettedGateFactory } from "../src/VettedGateFactory.sol";
import { ExitPenalties } from "../src/ExitPenalties.sol";
import { IStakingRouter } from "../src/interfaces/IStakingRouter.sol";

struct DeployParams {
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
    uint256[2][] legacyEaBondCurve;
    uint256[2][][] extraBondCurves;
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
    // VettedGate
    address identifiedCommunityStakersGateManager;
    uint256 identifiedCommunityStakersGateCurveId;
    bytes32 identifiedCommunityStakersGateTreeRoot;
    string identifiedCommunityStakersGateTreeCid;
    uint256[2][] identifiedCommunityStakersGateBondCurve;
    // Parameters for Identified Community Staker type
    uint256 identifiedCommunityStakersGateKeyRemovalCharge;
    uint256 identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine;
    uint256 identifiedCommunityStakersGateKeysLimit;
    uint256[2][] identifiedCommunityStakersGateAvgPerfLeewayData;
    uint256[2][] identifiedCommunityStakersGateRewardShareData;
    uint256 identifiedCommunityStakersGateStrikesLifetimeFrames;
    uint256 identifiedCommunityStakersGateStrikesThreshold;
    uint256 identifiedCommunityStakersGateQueuePriority;
    uint256 identifiedCommunityStakersGateQueueMaxDeposits;
    uint256 identifiedCommunityStakersGateBadPerformancePenalty;
    uint256 identifiedCommunityStakersGateAttestationsWeight;
    uint256 identifiedCommunityStakersGateBlocksWeight;
    uint256 identifiedCommunityStakersGateSyncWeight;
    uint256 identifiedCommunityStakersGateAllowedExitDelay;
    uint256 identifiedCommunityStakersGateExitDelayFee;
    uint256 identifiedCommunityStakersGateMaxWithdrawalRequestFee;
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
    DeployParams internal config;
    string internal artifactDir;
    string internal chainName;
    uint256 internal chainId;
    ILidoLocator internal locator;

    address internal deployer;
    CSModule public csm;
    Accounting public accounting;
    FeeOracle public oracle;
    FeeDistributor public feeDistributor;
    ExitPenalties public exitPenalties;
    Ejector public ejector;
    ValidatorStrikes public strikes;
    Verifier public verifier;
    address public gateSeal;
    PermissionlessGate public permissionlessGate;
    VettedGateFactory public vettedGateFactory;
    VettedGate public vettedGate;
    HashConsensus public hashConsensus;
    ParametersRegistry public parametersRegistry;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error HashConsensusMismatch();
    error CannotBeUsedInMainnet();
    error InvalidSecondAdmin();

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

        {
            ParametersRegistry parametersRegistryImpl = new ParametersRegistry(
                config.queueLowestPriority
            );
            parametersRegistry = ParametersRegistry(
                _deployProxy(config.proxyAdmin, address(parametersRegistryImpl))
            );

            Dummy dummyImpl = new Dummy();

            csm = CSModule(_deployProxy(deployer, address(dummyImpl)));

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
                module: address(csm),
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
                module: address(csm),
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

            IBondCurve.BondCurveIntervalInput[]
                memory legacyEaBondCurve = CommonScriptUtils
                    .arraysToBondCurveIntervalsInputs(config.legacyEaBondCurve);
            accounting.addBondCurve(legacyEaBondCurve);

            if (config.extraBondCurves.length > 0) {
                for (uint256 i = 0; i < config.extraBondCurves.length; i++) {
                    IBondCurve.BondCurveIntervalInput[]
                        memory extraBondCurve = CommonScriptUtils
                            .arraysToBondCurveIntervalsInputs(
                                config.extraBondCurves[i]
                            );
                    accounting.addBondCurve(extraBondCurve);
                }
            }

            IBondCurve.BondCurveIntervalInput[]
                memory identifiedCommunityStakersGateBondCurve = CommonScriptUtils
                    .arraysToBondCurveIntervalsInputs(
                        config.identifiedCommunityStakersGateBondCurve
                    );
            uint256 identifiedCommunityStakersGateBondCurveId = accounting
                .addBondCurve(identifiedCommunityStakersGateBondCurve);
            accounting.revokeRole(
                accounting.MANAGE_BOND_CURVES_ROLE(),
                address(deployer)
            );

            exitPenalties = ExitPenalties(
                _deployProxy(deployer, address(dummyImpl))
            );

            CSModule csmImpl = new CSModule({
                moduleType: config.moduleType,
                lidoLocator: config.lidoLocatorAddress,
                parametersRegistry: address(parametersRegistry),
                accounting: address(accounting),
                exitPenalties: address(exitPenalties)
            });

            {
                OssifiableProxy csmProxy = OssifiableProxy(
                    payable(address(csm))
                );
                csmProxy.proxy__upgradeTo(address(csmImpl));
                csmProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            csm.initialize({ admin: deployer });

            ValidatorStrikes strikesImpl = new ValidatorStrikes({
                module: address(csm),
                oracle: address(oracle),
                exitPenalties: address(exitPenalties),
                parametersRegistry: address(parametersRegistry)
            });

            strikes = ValidatorStrikes(
                _deployProxy(config.proxyAdmin, address(strikesImpl))
            );

            ExitPenalties exitPenaltiesImpl = new ExitPenalties(
                address(csm),
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
                address(csm),
                address(strikes),
                config.stakingModuleId,
                deployer
            );

            strikes.initialize(deployer, address(ejector));

            permissionlessGate = new PermissionlessGate(address(csm), deployer);

            address vettedGateImpl = address(new VettedGate(address(csm)));
            vettedGateFactory = new VettedGateFactory(vettedGateImpl);
            vettedGate = VettedGate(
                vettedGateFactory.create({
                    curveId: identifiedCommunityStakersGateBondCurveId,
                    treeRoot: config.identifiedCommunityStakersGateTreeRoot,
                    treeCid: config.identifiedCommunityStakersGateTreeCid,
                    admin: deployer
                })
            );

            {
                OssifiableProxy vettedGateProxy = OssifiableProxy(
                    payable(address(vettedGate))
                );
                vettedGateProxy.proxy__changeAdmin(config.proxyAdmin);
            }

            parametersRegistry.setKeyRemovalCharge(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateKeyRemovalCharge
            );
            parametersRegistry.setGeneralDelayedPenaltyAdditionalFine(
                identifiedCommunityStakersGateBondCurveId,
                config
                    .identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine
            );
            parametersRegistry.setKeysLimit(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateKeysLimit
            );
            parametersRegistry.setPerformanceLeewayData(
                identifiedCommunityStakersGateBondCurveId,
                CommonScriptUtils.arraysToKeyIndexValueIntervals(
                    config.identifiedCommunityStakersGateAvgPerfLeewayData
                )
            );
            parametersRegistry.setRewardShareData(
                identifiedCommunityStakersGateBondCurveId,
                CommonScriptUtils.arraysToKeyIndexValueIntervals(
                    config.identifiedCommunityStakersGateRewardShareData
                )
            );
            parametersRegistry.setStrikesParams(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateStrikesLifetimeFrames,
                config.identifiedCommunityStakersGateStrikesThreshold
            );
            parametersRegistry.setQueueConfig(
                identifiedCommunityStakersGateBondCurveId,
                uint32(config.identifiedCommunityStakersGateQueuePriority),
                uint32(config.identifiedCommunityStakersGateQueueMaxDeposits)
            );
            parametersRegistry.setBadPerformancePenalty(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateBadPerformancePenalty
            );
            parametersRegistry.setPerformanceCoefficients(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateAttestationsWeight,
                config.identifiedCommunityStakersGateBlocksWeight,
                config.identifiedCommunityStakersGateSyncWeight
            );
            parametersRegistry.setAllowedExitDelay(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateAllowedExitDelay
            );
            parametersRegistry.setExitDelayFee(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateExitDelayFee
            );
            parametersRegistry.setMaxWithdrawalRequestFee(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateMaxWithdrawalRequestFee
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
                address[] memory sealables = new address[](6);
                sealables[0] = address(csm);
                sealables[1] = address(accounting);
                sealables[2] = address(oracle);
                sealables[3] = address(verifier);
                sealables[4] = address(vettedGate);
                sealables[5] = address(ejector);
                gateSeal = _deployGateSeal(sealables);

                csm.grantRole(csm.PAUSE_ROLE(), gateSeal);
                oracle.grantRole(oracle.PAUSE_ROLE(), gateSeal);
                accounting.grantRole(accounting.PAUSE_ROLE(), gateSeal);
                verifier.grantRole(verifier.PAUSE_ROLE(), gateSeal);
                vettedGate.grantRole(vettedGate.PAUSE_ROLE(), gateSeal);
                ejector.grantRole(ejector.PAUSE_ROLE(), gateSeal);
            }

            csm.grantRole(csm.PAUSE_ROLE(), config.resealManager);
            csm.grantRole(csm.RESUME_ROLE(), config.resealManager);
            accounting.grantRole(accounting.PAUSE_ROLE(), config.resealManager);
            accounting.grantRole(
                accounting.RESUME_ROLE(),
                config.resealManager
            );
            oracle.grantRole(oracle.PAUSE_ROLE(), config.resealManager);
            oracle.grantRole(oracle.RESUME_ROLE(), config.resealManager);
            verifier.grantRole(verifier.PAUSE_ROLE(), config.resealManager);
            verifier.grantRole(verifier.RESUME_ROLE(), config.resealManager);
            vettedGate.grantRole(vettedGate.PAUSE_ROLE(), config.resealManager);
            vettedGate.grantRole(
                vettedGate.RESUME_ROLE(),
                config.resealManager
            );
            ejector.grantRole(ejector.PAUSE_ROLE(), config.resealManager);
            ejector.grantRole(ejector.RESUME_ROLE(), config.resealManager);

            accounting.grantRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(config.setResetBondCurveAddress)
            );
            accounting.grantRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(vettedGate)
            );

            csm.grantRole(
                csm.CREATE_NODE_OPERATOR_ROLE(),
                address(permissionlessGate)
            );
            csm.grantRole(csm.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate));
            csm.grantRole(
                csm.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
                config.generalDelayedPenaltyReporter
            );
            csm.grantRole(
                csm.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            csm.grantRole(csm.VERIFIER_ROLE(), address(verifier));
            csm.grantRole(csm.SUBMIT_WITHDRAWALS_ROLE(), address(verifier));
            csm.grantRole(
                csm.SUBMIT_WITHDRAWALS_ROLE(),
                config.easyTrackEVMScriptExecutor
            );

            if (config.secondAdminAddress != address(0)) {
                if (config.secondAdminAddress == deployer) {
                    revert InvalidSecondAdmin();
                }
                _grantSecondAdmins();
            }

            csm.grantRole(csm.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            csm.revokeRole(csm.DEFAULT_ADMIN_ROLE(), deployer);

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

            vettedGate.grantRole(
                vettedGate.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            vettedGate.grantRole(
                vettedGate.SET_TREE_ROLE(),
                config.easyTrackEVMScriptExecutor
            );
            vettedGate.grantRole(
                vettedGate.START_REFERRAL_SEASON_ROLE(),
                config.aragonAgent
            );
            vettedGate.grantRole(
                vettedGate.END_REFERRAL_SEASON_ROLE(),
                config.identifiedCommunityStakersGateManager
            );
            vettedGate.revokeRole(vettedGate.DEFAULT_ADMIN_ROLE(), deployer);

            permissionlessGate.grantRole(
                permissionlessGate.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            permissionlessGate.revokeRole(
                permissionlessGate.DEFAULT_ADMIN_ROLE(),
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
            deployJson.set("CSModule", address(csm));
            deployJson.set("CSModuleImpl", address(csmImpl));
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
            deployJson.set("PermissionlessGate", address(permissionlessGate));
            deployJson.set("VettedGateFactory", address(vettedGateFactory));
            deployJson.set("VettedGate", address(vettedGate));
            deployJson.set("VettedGateImpl", address(vettedGateImpl));
            deployJson.set("LidoLocator", config.lidoLocatorAddress);
            deployJson.set("GateSeal", gateSeal);
            deployJson.set("DeployParams", abi.encode(config));
            deployJson.set("git-ref", gitRef);
            vm.writeJson(deployJson.str, _deployJsonFilename());
        }

        vm.stopBroadcast();
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
        csm.grantRole(csm.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
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
        vettedGate.grantRole(
            vettedGate.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        permissionlessGate.grantRole(
            permissionlessGate.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
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
