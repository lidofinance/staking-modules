// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase, CuratedGateConfig } from "./DeployBase.s.sol";
import { GIndices } from "../constants/GIndices.sol";

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
        config.oracleMembers = new address[](3);
        config.oracleMembers[0] = vm.envAddress("CSM_ORACLE_1_ADDRESS");
        config.oracleMembers[1] = vm.envAddress("CSM_ORACLE_2_ADDRESS");
        config.oracleMembers[2] = vm.envAddress("CSM_ORACLE_3_ADDRESS");
        config.hashConsensusQuorum = 2;

        // Verifier
        config.slotsPerHistoricalRoot = vm.envOr("DEVNET_SLOTS_PER_HISTORICAL_ROOT", uint256(8192));
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBlockRootInSummary = GIndices.FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA; // prettier-ignore
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
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a";
            gate.params.metaRegistryBondCurveWeight = _m(7000);
        }

        // Professional Trusted Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([18, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(10000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Public Good Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([18, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(10000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Decentralization Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([18, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(10000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Extra Effort Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([18, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(10000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Intra-Operator DVT Cluster Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([18, 0.7 ether]);
            gate.treeRoot = bytes32(uint256(0xaaaabbbb)); // TODO: derive from final tree
            gate.treeCid = "TODO: ipfs-cid-cohort-a"; // TODO: derive from final tree
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(10000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        config.curatedGatePauseManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // MetaRegistry
        config.setOperatorInfoManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // GateSeal
        config.gateSealFactory = address(0);
        config.sealingCommittee = address(0);
        config.sealDuration = 0;
        config.sealExpiryTimestamp = 0;

        config.secondAdminAddress = vm.envOr("CSM_SECOND_ADMIN_ADDRESS", address(0));

        _setUp();
    }
}
