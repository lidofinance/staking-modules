// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { DeployBase } from "./DeployBase.s.sol";
import { CSModule } from "../src/CSModule.sol";
import { Accounting } from "../src/Accounting.sol";
import { FeeDistributor } from "../src/FeeDistributor.sol";
import { ExitPenalties } from "../src/ExitPenalties.sol";
import { Ejector } from "../src/Ejector.sol";
import { ValidatorStrikes } from "../src/ValidatorStrikes.sol";
import { FeeOracle } from "../src/FeeOracle.sol";
import { Verifier } from "../src/Verifier.sol";
import { PermissionlessGate } from "../src/PermissionlessGate.sol";
import { VettedGateFactory } from "../src/VettedGateFactory.sol";
import { VettedGate } from "../src/VettedGate.sol";
import { ParametersRegistry } from "../src/ParametersRegistry.sol";
import { IParametersRegistry } from "../src/interfaces/IParametersRegistry.sol";
import { IVerifier } from "../src/interfaces/IVerifier.sol";
import { OssifiableProxy } from "../src/lib/proxy/OssifiableProxy.sol";

import { JsonObj, Json } from "./utils/Json.sol";
import { Dummy } from "./utils/Dummy.sol";
import { CommonScriptUtils } from "./utils/Common.sol";
import { Slot } from "../src/lib/Types.sol";

abstract contract DeployImplementationsBase is DeployBase {
    address public gateSealV2;
    Verifier public verifierV2;
    address public earlyAdoption;

    bytes32 internal constant LEGACY_QUEUE_SLOT = bytes32(uint256(1));

    error LegacyQueueNotEmpty(uint128 head, uint128 tail);
    error MissingCSModuleAddress();

    function _deploy() internal {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({
                actual: block.chainid,
                expected: chainId
            });
        }

        bool skipLegacyQueueCheck = vm.envOr("SKIP_LEGACY_QUEUE_CHECK", false);
        if (!skipLegacyQueueCheck) {
            _ensureLegacyQueueDrained();
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

            permissionlessGate = new PermissionlessGate(address(csm), deployer);

            address vettedGateImpl = address(new VettedGate(address(csm)));
            vettedGateFactory = new VettedGateFactory(vettedGateImpl);
            vettedGate = VettedGate(
                vettedGateFactory.create({
                    curveId: config.identifiedCommunityStakersGateCurveId,
                    treeRoot: config.identifiedCommunityStakersGateTreeRoot,
                    treeCid: config.identifiedCommunityStakersGateTreeCid,
                    admin: deployer
                })
            );

            uint256 identifiedCommunityStakersGateBondCurveId = vettedGate
                .curveId();
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

            OssifiableProxy vettedGateProxy = OssifiableProxy(
                payable(address(vettedGate))
            );
            vettedGateProxy.proxy__changeAdmin(config.proxyAdmin);

            FeeDistributor feeDistributorImpl = new FeeDistributor({
                stETH: locator.lido(),
                accounting: address(accounting),
                oracle: address(oracle)
            });

            Dummy dummyImpl = new Dummy();

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

            ValidatorStrikes strikesImpl = new ValidatorStrikes({
                module: address(csm),
                oracle: address(oracle),
                exitPenalties: address(exitPenalties),
                parametersRegistry: address(parametersRegistry)
            });

            strikes = ValidatorStrikes(
                _deployProxy(config.proxyAdmin, address(strikesImpl))
            );

            FeeOracle oracleImpl = new FeeOracle({
                feeDistributor: address(feeDistributor),
                strikes: address(strikes),
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime
            });

            ExitPenalties exitPenaltiesImpl = new ExitPenalties(
                address(csm),
                address(parametersRegistry),
                address(strikes)
            );

            OssifiableProxy exitPenaltiesProxy = OssifiableProxy(
                payable(address(exitPenalties))
            );
            exitPenaltiesProxy.proxy__upgradeTo(address(exitPenaltiesImpl));
            exitPenaltiesProxy.proxy__changeAdmin(config.proxyAdmin);

            ejector = new Ejector(
                address(csm),
                address(strikes),
                config.stakingModuleId,
                deployer
            );

            strikes.initialize(deployer, address(ejector));

            // prettier-ignore
            verifierV2 = new Verifier({
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

            address[] memory sealables = new address[](6);
            sealables[0] = address(csm);
            sealables[1] = address(accounting);
            sealables[2] = address(oracle);
            sealables[3] = address(verifierV2);
            sealables[4] = address(vettedGate);
            sealables[5] = address(ejector);
            gateSealV2 = _deployGateSeal(sealables);

            if (config.secondAdminAddress != address(0)) {
                if (config.secondAdminAddress == deployer) {
                    revert InvalidSecondAdmin();
                }
                _grantSecondAdminsForNewContracts();
            }

            verifierV2.grantRole(verifierV2.PAUSE_ROLE(), config.resealManager);
            verifierV2.grantRole(
                verifierV2.RESUME_ROLE(),
                config.resealManager
            );
            vettedGate.grantRole(vettedGate.PAUSE_ROLE(), config.resealManager);
            vettedGate.grantRole(
                vettedGate.RESUME_ROLE(),
                config.resealManager
            );
            ejector.grantRole(ejector.PAUSE_ROLE(), config.resealManager);
            ejector.grantRole(ejector.RESUME_ROLE(), config.resealManager);

            ejector.grantRole(ejector.PAUSE_ROLE(), gateSealV2);
            ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            ejector.revokeRole(ejector.DEFAULT_ADMIN_ROLE(), deployer);

            vettedGate.grantRole(vettedGate.PAUSE_ROLE(), gateSealV2);
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

            verifierV2.grantRole(verifierV2.PAUSE_ROLE(), gateSealV2);
            verifierV2.grantRole(
                verifierV2.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            verifierV2.revokeRole(verifierV2.DEFAULT_ADMIN_ROLE(), deployer);

            parametersRegistry.grantRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
                config.aragonAgent
            );
            parametersRegistry.revokeRole(
                parametersRegistry.DEFAULT_ADMIN_ROLE(),
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
            deployJson.set("VerifierV2", address(verifierV2));
            deployJson.set("PermissionlessGate", address(permissionlessGate));
            deployJson.set("VettedGateFactory", address(vettedGateFactory));
            deployJson.set("VettedGate", address(vettedGate));
            deployJson.set("VettedGateImpl", address(vettedGateImpl));
            deployJson.set("LidoLocator", config.lidoLocatorAddress);
            deployJson.set("GateSeal", gateSeal);
            deployJson.set("GateSealV2", gateSealV2);
            deployJson.set("DeployParams", abi.encode(config));
            deployJson.set("git-ref", gitRef);
            vm.writeJson(
                deployJson.str,
                string(
                    abi.encodePacked(
                        artifactDir,
                        "upgrade-",
                        chainName,
                        ".json"
                    )
                )
            );
        }

        vm.stopBroadcast();
    }

    function _grantSecondAdminsForNewContracts() internal {
        if (keccak256(abi.encodePacked(chainName)) == keccak256("mainnet")) {
            revert CannotBeUsedInMainnet();
        }
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
        verifierV2.grantRole(
            verifierV2.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
        strikes.grantRole(
            strikes.DEFAULT_ADMIN_ROLE(),
            config.secondAdminAddress
        );
    }

    function _ensureLegacyQueueDrained() internal {
        if (address(csm) == address(0)) {
            revert MissingCSModuleAddress();
        }

        // QueueLib.Queue packs head/tail into a single slot. See forge inspect output for slot indexes.
        bytes32 queuePointers = vm.load(address(csm), LEGACY_QUEUE_SLOT);
        uint128 head = uint128(uint256(queuePointers));
        uint128 tail = uint128(uint256(queuePointers) >> 128);

        if (head != tail) {
            revert LegacyQueueNotEmpty(head, tail);
        }
    }
}

interface ICSEarlyAdoption {
    function CURVE_ID() external view returns (uint256);
}
