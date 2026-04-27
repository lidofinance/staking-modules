// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase } from "./DeployBase.s.sol";
import { CSModule } from "../../src/CSModule.sol";
import { Accounting } from "../../src/Accounting.sol";
import { FeeOracle } from "../../src/FeeOracle.sol";
import { FeeDistributor } from "../../src/FeeDistributor.sol";
import { ExitPenalties } from "../../src/ExitPenalties.sol";
import { Ejector } from "../../src/Ejector.sol";
import { PermissionlessGate } from "../../src/PermissionlessGate.sol";
import { ValidatorStrikes } from "../../src/ValidatorStrikes.sol";
import { Verifier } from "../../src/Verifier.sol";
import { VettedGate } from "../../src/VettedGate.sol";
import { MerkleGateFactory } from "../../src/MerkleGateFactory.sol";
import { ParametersRegistry } from "../../src/ParametersRegistry.sol";
import { OneShotCurveSetup } from "../../src/utils/OneShotCurveSetup.sol";
import { IOneShotCurveSetup } from "../../src/interfaces/IOneShotCurveSetup.sol";
import { IVerifier } from "../../src/interfaces/IVerifier.sol";
import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";

import { JsonObj, Json } from "../utils/Json.sol";
import { CommonScriptUtils } from "../utils/Common.sol";
import { Slot } from "../../src/lib/Types.sol";

abstract contract DeployCSMImplementationsBase is DeployBase {
    Verifier public verifierV3;
    OneShotCurveSetup public identifiedDVTClusterCurveSetup;
    address public earlyAdoption;
    address public legacyGateSeal; // TODO: remove after the CB mainnet deployment.

    bytes32 internal constant LEGACY_QUEUE_SLOT = bytes32(uint256(1));

    error LegacyQueueNotEmpty(uint128 head, uint128 tail);
    error MissingCSModuleAddress();

    function _deploy() internal {
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });

        _ensureLegacyQueueDrained();
        artifactDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/local/"));

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");

        {
            ParametersRegistry parametersRegistryImpl = new ParametersRegistry(config.queueLowestPriority);

            Accounting accountingImpl = new Accounting({
                lidoLocator: config.lidoLocatorAddress,
                module: address(csm),
                feeDistributor: address(feeDistributor),
                minBondLockPeriod: config.minBondLockPeriod,
                maxBondLockPeriod: config.maxBondLockPeriod
            });

            VettedGate vettedGateImpl = new VettedGate(address(csm));
            vettedGateFactory = new MerkleGateFactory(address(vettedGateImpl));
            uint256 expectedIdentifiedDVTClusterCurveId = accounting.getCurvesCount();
            config.identifiedDVTClusterBondCurveId = expectedIdentifiedDVTClusterCurveId;
            identifiedDVTClusterGate = VettedGate(
                vettedGateFactory.create(
                    expectedIdentifiedDVTClusterCurveId,
                    config.identifiedDVTClusterGateTreeRoot,
                    config.identifiedDVTClusterGateTreeCid,
                    deployer
                )
            );
            OssifiableProxy(payable(address(identifiedDVTClusterGate))).proxy__changeAdmin(config.proxyAdmin);

            FeeOracle oracleImpl = new FeeOracle({
                feeDistributor: address(feeDistributor),
                strikes: address(strikes),
                secondsPerSlot: config.secondsPerSlot,
                genesisTime: config.clGenesisTime
            });

            FeeDistributor feeDistributorImpl = new FeeDistributor({
                stETH: locator.lido(),
                accounting: address(accounting),
                oracle: address(oracle)
            });

            CSModule csmImpl = new CSModule({
                moduleType: config.moduleType,
                lidoLocator: config.lidoLocatorAddress,
                parametersRegistry: address(parametersRegistry),
                accounting: address(accounting),
                exitPenalties: address(exitPenalties)
            });

            ValidatorStrikes strikesImpl = new ValidatorStrikes({ module: address(csm), oracle: address(oracle) });

            ExitPenalties exitPenaltiesImpl = new ExitPenalties(address(csm), address(strikes));

            ejector = new Ejector(address(csm), address(strikes), deployer);

            permissionlessGate = new PermissionlessGate(address(csm), deployer);

            identifiedDVTClusterCurveSetup = new OneShotCurveSetup(
                address(accounting),
                address(parametersRegistry),
                _identifiedDVTClusterCurveSetupParams()
            );

            // prettier-ignore
            verifierV3 = new Verifier({
                withdrawalAddress: locator.withdrawalVault(),
                module: address(csm),
                slotsPerEpoch: uint64(config.slotsPerEpoch),
                gindices: IVerifier.GIndices({
                    gIFirstWithdrawalPrev: config.gIFirstWithdrawal,
                    gIFirstWithdrawalCurr: config.gIFirstWithdrawal,
                    gIFirstValidatorPrev: config.gIFirstValidator,
                    gIFirstValidatorCurr: config.gIFirstValidator,
                    gIFirstHistoricalSummaryPrev: config.gIFirstHistoricalSummary,
                    gIFirstHistoricalSummaryCurr: config.gIFirstHistoricalSummary,
                    gIFirstBalanceNodePrev: config.gIFirstBalanceNode,
                    gIFirstBalanceNodeCurr: config.gIFirstBalanceNode
                }),
                firstSupportedSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                pivotSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
                capellaSlot: Slot.wrap(uint64(config.capellaSlot)),
                minWithdrawalRatio: config.minWithdrawalRatio,
                admin: deployer
            });

            if (config.secondAdminAddress != address(0)) {
                if (config.secondAdminAddress == deployer) revert InvalidSecondAdmin();
                _grantSecondAdminsForNewContracts();
            }

            verifierV3.grantRole(verifierV3.PAUSE_ROLE(), config.resealManager);
            verifierV3.grantRole(verifierV3.RESUME_ROLE(), config.resealManager);
            ejector.grantRole(ejector.PAUSE_ROLE(), config.resealManager);
            ejector.grantRole(ejector.RESUME_ROLE(), config.resealManager);
            identifiedDVTClusterGate.grantRole(identifiedDVTClusterGate.PAUSE_ROLE(), config.resealManager);
            identifiedDVTClusterGate.grantRole(identifiedDVTClusterGate.RESUME_ROLE(), config.resealManager);

            if (config.circuitBreaker != address(0)) {
                ejector.grantRole(ejector.PAUSE_ROLE(), config.circuitBreaker);
                identifiedDVTClusterGate.grantRole(identifiedDVTClusterGate.PAUSE_ROLE(), circuitBreaker);
            }
            ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            ejector.revokeRole(ejector.DEFAULT_ADMIN_ROLE(), deployer);

            permissionlessGate.grantRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            permissionlessGate.revokeRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), deployer);

            identifiedDVTClusterGate.grantRole(identifiedDVTClusterGate.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            identifiedDVTClusterGate.grantRole(
                identifiedDVTClusterGate.SET_TREE_ROLE(),
                config.easyTrackEVMScriptExecutor
            );
            identifiedDVTClusterGate.revokeRole(identifiedDVTClusterGate.DEFAULT_ADMIN_ROLE(), deployer);

            if (config.circuitBreaker != address(0)) {
                verifierV3.grantRole(verifierV3.PAUSE_ROLE(), config.circuitBreaker);
            }
            verifierV3.grantRole(verifierV3.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
            verifierV3.revokeRole(verifierV3.DEFAULT_ADMIN_ROLE(), deployer);

            config.identifiedCommunityStakersGateCurveId = vettedGate.curveId();
            config.identifiedCommunityStakersGateTreeRoot = vettedGate.treeRoot();
            config.identifiedCommunityStakersGateTreeCid = vettedGate.treeCid();

            JsonObj memory deployJson = Json.newObj("artifact");
            deployJson.set("ChainId", chainId);
            deployJson.set("CSModule", address(csm));
            deployJson.set("CSModuleImpl", address(csmImpl));
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
            deployJson.set("VerifierV3", address(verifierV3));
            deployJson.set("PermissionlessGate", address(permissionlessGate));
            deployJson.set("IdentifiedDVTClusterCurveSetup", address(identifiedDVTClusterCurveSetup));
            deployJson.set("IdentifiedDVTClusterGate", address(identifiedDVTClusterGate));
            deployJson.set("VettedGateFactory", address(vettedGateFactory));
            deployJson.set("VettedGate", address(vettedGate));
            deployJson.set("VettedGateImpl", address(vettedGateImpl));
            deployJson.set("LidoLocator", config.lidoLocatorAddress);
            deployJson.set("GateSeal", legacyGateSeal);
            deployJson.set("CircuitBreaker", config.circuitBreaker);
            deployJson.set("DeployParams", abi.encode(config));
            deployJson.set("git-ref", gitRef);
            if (!vm.exists(artifactDir)) {
                vm.createDir(artifactDir, true);
            }
            vm.writeJson(deployJson.str, string(abi.encodePacked(artifactDir, "upgrade-", chainName, ".json")));
        }

        vm.stopBroadcast();
    }

    function _grantSecondAdminsForNewContracts() internal {
        if (keccak256(abi.encodePacked(chainName)) == keccak256("mainnet")) revert CannotBeUsedInMainnet();
        ejector.grantRole(ejector.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        verifierV3.grantRole(verifierV3.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        permissionlessGate.grantRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        identifiedDVTClusterGate.grantRole(identifiedDVTClusterGate.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
    }

    function _ensureLegacyQueueDrained() internal {
        if (address(csm) == address(0)) revert MissingCSModuleAddress();

        // QueueLib.Queue packs head/tail into a single slot. See forge inspect output for slot indexes.
        bytes32 queuePointers = vm.load(address(csm), LEGACY_QUEUE_SLOT);
        uint128 head = uint128(uint256(queuePointers));
        uint128 tail = uint128(uint256(queuePointers) >> 128);

        if (head != tail) revert LegacyQueueNotEmpty(head, tail);
    }

    function _identifiedDVTClusterCurveSetupParams()
        internal
        view
        returns (IOneShotCurveSetup.ConstructorParams memory params)
    {
        params.bondCurve = CommonScriptUtils.arraysToBondCurveIntervalsInputs(config.identifiedDVTClusterBondCurve);

        params.queueConfig = IOneShotCurveSetup.QueueConfigOverride({
            isSet: true,
            priority: config.identifiedDVTClusterQueuePriority,
            maxDeposits: config.identifiedDVTClusterQueueMaxDeposits
        });

        params.rewardShareData.isSet = true;
        params.rewardShareData.data = CommonScriptUtils.arraysToKeyIndexValueIntervals(
            config.identifiedDVTClusterRewardShareData
        );

        params.keyRemovalCharge = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: config.identifiedDVTClusterKeyRemovalCharge
        });
        params.generalDelayedPenaltyFine = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: config.identifiedDVTClusterGeneralDelayedPenaltyAdditionalFine
        });
        params.allowedExitDelay = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: config.identifiedDVTClusterAllowedExitDelay
        });
        params.exitDelayFee = IOneShotCurveSetup.ScalarOverride({
            isSet: true,
            value: config.identifiedDVTClusterExitDelayFee
        });
    }
}
