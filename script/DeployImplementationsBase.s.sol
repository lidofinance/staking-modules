// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { DeployBase } from "./DeployBase.s.sol";
import { GIndex } from "../src/lib/GIndex.sol";

import { HashConsensus } from "../src/lib/base-oracle/HashConsensus.sol";
import { CSModule } from "../src/CSModule.sol";
import { CSAccounting } from "../src/CSAccounting.sol";
import { CSFeeDistributor } from "../src/CSFeeDistributor.sol";
import { CSExitPenalties } from "../src/CSExitPenalties.sol";
import { CSEjector } from "../src/CSEjector.sol";
import { CSStrikes } from "../src/CSStrikes.sol";
import { CSFeeOracle } from "../src/CSFeeOracle.sol";
import { CSVerifier } from "../src/CSVerifier.sol";
import { PermissionlessGate } from "../src/PermissionlessGate.sol";
import { VettedGateFactory } from "../src/VettedGateFactory.sol";
import { VettedGate } from "../src/VettedGate.sol";
import { CSParametersRegistry } from "../src/CSParametersRegistry.sol";
import { ICSParametersRegistry } from "../src/interfaces/ICSParametersRegistry.sol";
import { ICSVerifier } from "../src/interfaces/ICSVerifier.sol";
import { OssifiableProxy } from "../src/lib/proxy/OssifiableProxy.sol";

import { JsonObj, Json } from "./utils/Json.sol";
import { Dummy } from "./utils/Dummy.sol";
import { CommonScriptUtils } from "./utils/Common.sol";
import { GIndex } from "../src/lib/GIndex.sol";
import { Slot } from "../src/lib/Types.sol";
import { DeployBase } from "./DeployBase.s.sol";

abstract contract DeployImplementationsBase is DeployBase {
    address public gateSealV2;
    CSVerifier public verifierV2;
    address public earlyAdoption;

    function _deploy() internal {
        if (chainId != block.chainid) {
            revert ChainIdMismatch({
                actual: block.chainid,
                expected: chainId
            });
        }
        artifactDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/local/"));

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");

        {
            CSParametersRegistry parametersRegistryImpl = new CSParametersRegistry(
                    config.queueLowestPriority
                );
            parametersRegistry = CSParametersRegistry(
                _deployProxy(config.proxyAdmin, address(parametersRegistryImpl))
            );
            parametersRegistry.initialize({
                admin: deployer,
                data: ICSParametersRegistry.InitializationData({
                    keyRemovalCharge: config.defaultKeyRemovalCharge,
                    elRewardsStealingAdditionalFine: config
                        .defaultElRewardsStealingAdditionalFine,
                    keysLimit: config.defaultKeysLimit,
                    rewardShare: config.defaultRewardShareBP,
                    performanceLeeway: config.defaultAvgPerfLeewayBP,
                    strikesLifetime: config.defaultStrikesLifetimeFrames,
                    strikesThreshold: config.defaultStrikesThreshold,
                    defaultQueuePriority: config.defaultQueuePriority,
                    defaultQueueMaxDeposits: config.defaultQueueMaxDeposits,
                    badPerformancePenalty: config.defaultBadPerformancePenalty,
                    attestationsWeight: config.defaultAttestationsWeight,
                    blocksWeight: config.defaultBlocksWeight,
                    syncWeight: config.defaultSyncWeight,
                    defaultAllowedExitDelay: config.defaultAllowedExitDelay,
                    defaultExitDelayPenalty: config.defaultExitDelayPenalty,
                    defaultMaxWithdrawalRequestFee: config
                        .defaultMaxWithdrawalRequestFee
                })
            });

            CSAccounting accountingImpl = new CSAccounting({
                lidoLocator: config.lidoLocatorAddress,
                module: address(csm),
                _feeDistributor: address(feeDistributor),
                minBondLockPeriod: config.minBondLockPeriod,
                maxBondLockPeriod: config.maxBondLockPeriod,
                enableBondReserve: config.enableBondReserve
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
            parametersRegistry.setElRewardsStealingAdditionalFine(
                identifiedCommunityStakersGateBondCurveId,
                config
                    .identifiedCommunityStakersGateELRewardsStealingAdditionalFine
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
            parametersRegistry.setExitDelayPenalty(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateExitDelayPenalty
            );
            parametersRegistry.setMaxWithdrawalRequestFee(
                identifiedCommunityStakersGateBondCurveId,
                config.identifiedCommunityStakersGateMaxWithdrawalRequestFee
            );

            OssifiableProxy vettedGateProxy = OssifiableProxy(
                payable(address(vettedGate))
            );
            vettedGateProxy.proxy__changeAdmin(config.proxyAdmin);

            CSFeeDistributor feeDistributorImpl = new CSFeeDistributor({
                stETH: locator.lido(),
                accounting: address(accounting),
                oracle: address(oracle)
            });

            Dummy dummyImpl = new Dummy();

            exitPenalties = CSExitPenalties(
                _deployProxy(deployer, address(dummyImpl))
            );

            CSModule csmImpl = new CSModule({
                moduleType: config.moduleType,
                lidoLocator: config.lidoLocatorAddress,
                parametersRegistry: address(parametersRegistry),
                _accounting: address(accounting),
                exitPenalties: address(exitPenalties)
            });

            CSStrikes strikesImpl = new CSStrikes({
                module: address(csm),
                oracle: address(oracle),
                exitPenalties: address(exitPenalties),
                parametersRegistry: address(parametersRegistry)
            });

            strikes = CSStrikes(
                _deployProxy(config.proxyAdmin, address(strikesImpl))
            );

            CSFeeOracle oracleImpl = new CSFeeOracle({
                feeDistributor: address(feeDistributor),
                strikes: address(strikes),
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime
            });

            CSExitPenalties exitPenaltiesImpl = new CSExitPenalties(
                address(csm),
                address(parametersRegistry),
                address(strikes)
            );

            OssifiableProxy exitPenaltiesProxy = OssifiableProxy(
                payable(address(exitPenalties))
            );
            exitPenaltiesProxy.proxy__upgradeTo(address(exitPenaltiesImpl));
            exitPenaltiesProxy.proxy__changeAdmin(config.proxyAdmin);

            ejector = new CSEjector(
                address(csm),
                address(strikes),
                config.stakingModuleId,
                deployer
            );

            strikes.initialize(deployer, address(ejector));

            // prettier-ignore
            verifierV2 = new CSVerifier({
                withdrawalAddress: locator.withdrawalVault(),
                module: address(csm),
                slotsPerEpoch: uint64(config.slotsPerEpoch),
                slotsPerHistoricalRoot: uint64(config.slotsPerHistoricalRoot),
                gindices: ICSVerifier.GIndices({
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
            deployJson.set("CSParametersRegistry", address(parametersRegistry));
            deployJson.set(
                "CSParametersRegistryImpl",
                address(parametersRegistryImpl)
            );
            deployJson.set("CSAccounting", address(accounting));
            deployJson.set("CSAccountingImpl", address(accountingImpl));
            deployJson.set("CSFeeOracle", address(oracle));
            deployJson.set("CSFeeOracleImpl", address(oracleImpl));
            deployJson.set("CSFeeDistributor", address(feeDistributor));
            deployJson.set("CSFeeDistributorImpl", address(feeDistributorImpl));
            deployJson.set("CSExitPenalties", address(exitPenalties));
            deployJson.set("CSExitPenaltiesImpl", address(exitPenaltiesImpl));
            deployJson.set("CSEjector", address(ejector));
            deployJson.set("CSStrikes", address(strikes));
            deployJson.set("CSStrikesImpl", address(strikesImpl));
            deployJson.set("HashConsensus", address(hashConsensus));
            deployJson.set("CSVerifier", address(verifier));
            deployJson.set("CSVerifierV2", address(verifierV2));
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
}

interface ICSEarlyAdoption {
    function CURVE_ID() external view returns (uint256);
}
