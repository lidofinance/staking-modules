// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase, CuratedGateConfig, CurveFeeModifierConfig } from "./DeployBase.s.sol";
import { Step } from "../../src/interfaces/IStepwiseWeightBoost.sol";
import { GIndices } from "../constants/GIndices.sol";
import { BaseOracle } from "../../src/lib/base-oracle/BaseOracle.sol";
import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";

contract DeployLocalDevNet is DeployBase {
    constructor() DeployBase("local-devnet", vm.envUint("DEVNET_CHAIN_ID")) {
        // Lido addresses
        config.lidoLocatorAddress = vm.envAddress("CSM_LOCATOR_ADDRESS");
        config.aragonAgent = vm.envAddress("CSM_ARAGON_AGENT_ADDRESS");
        config.easyTrackEVMScriptExecutor = vm.envAddress("EVM_SCRIPT_EXECUTOR_ADDRESS");
        config.proxyAdmin = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // Oracle
        config.secondsPerSlot = 12;
        config.slotsPerEpoch = vm.envUint("DEVNET_SLOTS_PER_EPOCH");
        config.clGenesisTime = vm.envUint("DEVNET_GENESIS_TIME");
        config.oracleReportEpochsPerFrame = vm.envUint("CSM_EPOCHS_PER_FRAME");
        config.fastLaneLengthSlots = 0;
        config.consensusVersion = 4;
        (config.oracleMembers, config.hashConsensusQuorum) = _readAccountingHashConsensus();

        // Verifier
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.verifierFirstSupportedSlot = vm.envUint("DEVNET_ELECTRA_EPOCH") * config.slotsPerEpoch;
        config.capellaSlot = vm.envUint("DEVNET_CAPELLA_EPOCH") * config.slotsPerEpoch;
        config.minWithdrawalRatio = 9950;

        // Accounting
        // 11 -> 1
        config.defaultBondCurve.push([1, 11 ether]);
        config.defaultBondCurve.push([2, 1 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 7 days;
        config.bondLockPeriod = 1 days;
        config.chargePenaltyRecipient = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // Module
        config.moduleType = "curated-onchain-v2"; // Just a unique type name to be used by the off-chain tooling
        config.generalDelayedPenaltyReporter = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = 100;
        config.defaultAvgPerfLeewayBP = 10000;
        // Legacy ParametersRegistry compatibility value; Curated fees come from CustomFeeRegistry.
        config.defaultRewardShareBP = 6250; // 62.5% of 4% = 2.5% of the total
        config.defaultStrikesLifetimeFrames = 6;
        config.defaultStrikesThreshold = 3;
        config.queueLowestPriority = 0;
        config.defaultQueuePriority = 0;
        config.defaultQueueMaxDeposits = type(uint32).max;
        config.defaultBadPerformancePenalty = 0 ether;
        config.defaultAttestationsWeight = 54; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultBlocksWeight = 8; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultSyncWeight = 2; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultAllowedExitDelay = 4 days;
        config.defaultExitDelayFee = 0.01 ether;
        config.defaultMaxElWithdrawalRequestFee = 0.1 ether;
        config.penaltiesManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // Curated gates
        // Professional Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Professional Operator Gate";
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a";
            gate.params.metaRegistryBondCurveWeight = _m(50000);
            gate.params.keysLimit = _m(80);
        }

        // Professional Trusted Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Professional Trusted Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Public Good Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Public Good Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Decentralization Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Decentralization Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Extra Effort Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Extra Effort Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Intra-Operator DVT Cluster Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Intra-Operator DVT Cluster Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Intra-Operator DVT Cluster Plus Gate (identical to the one above but with 4% fee)
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Intra-Operator DVT Cluster Plus Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        config.curatedGatePauseManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // MetaRegistry
        config.setOperatorInfoManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // CircuitBreaker
        config.circuitBreaker = vm.envAddress("CSM_CIRCUIT_BREAKER_ADDRESS");
        config.circuitBreakerPauser = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        config.secondAdminAddress = vm.envOr("CSM_SECOND_ADMIN_ADDRESS", address(0));

        // CurveMultiplier
        config.additionalBondRegistryConfig.curveMultiplierReductionCooldown = 1 days;
        // TODO: reconsider — placeholder initial boost steps.
        config.additionalBondRegistryConfig.boostSteps.push(Step({ threshold: 5_000, value: 2_000 }));
        config.additionalBondRegistryConfig.boostSteps.push(Step({ threshold: 10_000, value: 8_000 }));

        // NodeOperatorStrikes
        config.nodeOperatorStrikesConfig.committee = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        config.nodeOperatorStrikesConfig.thresholds.push(Step({ threshold: 2, value: 2_500 }));
        config.nodeOperatorStrikesConfig.thresholds.push(Step({ threshold: 3, value: 5_000 }));
        config.nodeOperatorStrikesConfig.thresholds.push(Step({ threshold: 4, value: 7_500 }));
        config.nodeOperatorStrikesConfig.thresholds.push(Step({ threshold: 5, value: 10_000 }));

        // LDO lock boost provider
        config.ldoLockBoostProviderConfig.token = vm.envAddress("CSM_LDO_TOKEN_ADDRESS");
        config.ldoLockBoostProviderConfig.votingContract = vm.envAddress("CSM_LDO_VOTING_ADDRESS");
        config.ldoLockBoostProviderConfig.snapshotDelegation = vm.envAddress("CSM_SNAPSHOT_DELEGATION_ADDRESS");
        config.ldoLockBoostProviderConfig.minLockPeriod = 1 days;
        config.ldoLockBoostProviderConfig.lockPeriod = 1 days;
        config.ldoLockBoostProviderConfig.lockBoostSteps.push(Step({ threshold: 100_000 ether, value: 1_000 }));
        config.ldoLockBoostProviderConfig.lockBoostSteps.push(Step({ threshold: 200_000 ether, value: 1_500 }));

        // CustomFeeRegistry
        config.customFeeRegistryConfig.defaultMaxFeeDiscount = 6_250;
        config.customFeeRegistryConfig.feeDiscountCutCooldown = 15 days;
        for (uint128 i = 1; i < 35; ++i) {
            config.customFeeRegistryConfig.feeDiscountWeightSteps.push(Step({ threshold: i * 250, value: i * 400 }));
        }
        // Professional Operator uses the default bond curve (curve 0): 8_750 - 2_500 = 6_250.
        config.customFeeRegistryConfig.feeModifiers.push(
            CurveFeeModifierConfig({ curveId: 0, value: 2_500, negative: true })
        );

        _setUp();
    }

    function _readAccountingHashConsensus() private view returns (address[] memory members, uint256 quorum) {
        HashConsensus accountingConsensus = HashConsensus(
            BaseOracle(ILidoLocator(config.lidoLocatorAddress).accountingOracle()).getConsensusContract()
        );
        (members, ) = accountingConsensus.getMembers();
        quorum = accountingConsensus.getQuorum();
    }
}
