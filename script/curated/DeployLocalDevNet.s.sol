// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { DeployBase, CuratedGateConfig } from "./DeployBase.s.sol";
import { GIndices } from "../constants/GIndices.sol";

contract DeployLocalDevNet is DeployBase {
    constructor() DeployBase("local-devnet", vm.envUint("DEVNET_CHAIN_ID")) {
        // Lido addresses
        config.lidoLocatorAddress = vm.envAddress("CSM_LOCATOR_ADDRESS");
        config.aragonAgent = vm.envAddress("CSM_ARAGON_AGENT_ADDRESS");
        config.easyTrackEVMScriptExecutor = vm.envAddress(
            "EVM_SCRIPT_EXECUTOR_ADDRESS"
        );
        config.proxyAdmin = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // Oracle
        config.secondsPerSlot = 12;
        config.slotsPerEpoch = vm.envUint("DEVNET_SLOTS_PER_EPOCH");
        config.clGenesisTime = vm.envUint("DEVNET_GENESIS_TIME");
        config.oracleReportEpochsPerFrame = vm.envUint("CSM_EPOCHS_PER_FRAME");
        config.fastLaneLengthSlots = 0;
        config.consensusVersion = 3;
        config.oracleMembers = new address[](3);
        config.oracleMembers[0] = vm.envAddress("CSM_ORACLE_1_ADDRESS");
        config.oracleMembers[1] = vm.envAddress("CSM_ORACLE_2_ADDRESS");
        config.oracleMembers[2] = vm.envAddress("CSM_ORACLE_3_ADDRESS");
        config.hashConsensusQuorum = 2;
        // Verifier
        config.slotsPerHistoricalRoot = vm.envOr(
            "DEVNET_SLOTS_PER_HISTORICAL_ROOT",
            uint256(8192)
        );
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBlockRootInSummary = GIndices.FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA; // prettier-ignore
        config.verifierFirstSupportedSlot =
            vm.envUint("DEVNET_ELECTRA_EPOCH") *
            config.slotsPerEpoch;
        config.capellaSlot =
            vm.envUint("DEVNET_CAPELLA_EPOCH") *
            config.slotsPerEpoch;

        // Accounting
        // 2.4 -> 1.3
        config.defaultBondCurve.push([1, 2.4 ether]);
        config.defaultBondCurve.push([2, 1.3 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 7 days;
        config.bondLockPeriod = 1 days;
        config.setResetBondCurveAddress = vm.envAddress(
            "CSM_FIRST_ADMIN_ADDRESS"
        ); // Dev team EOA
        config.chargePenaltyRecipient = vm.envAddress(
            "CSM_FIRST_ADMIN_ADDRESS"
        ); // Dev team EOA
        // Module
        config.stakingModuleId = vm.envUint("CSM_STAKING_MODULE_ID");
        config.moduleType = "curated-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config.generalDelayedPenaltyReporter = vm.envAddress(
            "CSM_FIRST_ADMIN_ADDRESS"
        ); // Dev team EOA

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = type(uint256).max;
        config.defaultAvgPerfLeewayBP = 450;
        config.defaultRewardShareBP = 10000;
        config.defaultStrikesLifetimeFrames = 6;
        config.defaultStrikesThreshold = 3;
        config.queueLowestPriority = 5;
        config.defaultQueuePriority = 5;
        config.defaultQueueMaxDeposits = type(uint32).max;
        config.defaultBadPerformancePenalty = 0.1 ether; // TODO: to be reviewed
        config.defaultAttestationsWeight = 54; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultBlocksWeight = 8; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultSyncWeight = 2; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultAllowedExitDelay = 4 days;
        config.defaultExitDelayFee = 0.1 ether;
        config.defaultMaxWithdrawalRequestFee = 0.1 ether;

        // Curated gates
        config.curatedGates.push();

        {
            CuratedGateConfig storage primaryGate = config.curatedGates[0];
            primaryGate.bondCurve.push([1, 1 ether]); // TODO: adjust curve
            primaryGate.bondCurve.push([2, 1 ether]); // TODO: adjust curve
            primaryGate.treeRoot = vm.envOr(
                "CURATED_GATE_TREE_ROOT",
                bytes32(uint256(0xdeadbeef))
            ); // TODO: replace with generated root
            primaryGate.treeCid = vm.envOr(
                "CURATED_GATE_TREE_CID",
                string("TODO: dev-tree-cid")
            );

            primaryGate.params.keyRemovalCharge = vm.envOr(
                "CURATED_GATE_KEY_REMOVAL_CHARGE",
                uint256(0.01 ether)
            );
            primaryGate.params.generalDelayedPenaltyAdditionalFine = vm.envOr(
                "CURATED_GATE_GENERAL_DELAYED_PENALTY_FINE",
                uint256(0.05 ether)
            );
            primaryGate.params.keysLimit = vm.envOr(
                "CURATED_GATE_KEYS_LIMIT",
                uint256(type(uint248).max)
            );
            primaryGate.params.avgPerfLeewayData.push([1, 500]); // TODO
            primaryGate.params.rewardShareData.push([1, 10000]); // TODO
            primaryGate.params.rewardShareData.push([17, 5834]); // TODO
            primaryGate.params.strikesLifetimeFrames = 6; // TODO
            primaryGate.params.strikesThreshold = 3; // TODO
            primaryGate.params.queuePriority = 1; // TODO
            primaryGate.params.queueMaxDeposits = 12; // TODO
            primaryGate.params.badPerformancePenalty = 0.05 ether; // TODO
            primaryGate.params.attestationsWeight = 60; // TODO
            primaryGate.params.blocksWeight = 4; // TODO
            primaryGate.params.syncWeight = 0; // TODO
            primaryGate.params.allowedExitDelay = 8 days; // TODO
            primaryGate.params.exitDelayFee = 0.05 ether; // TODO
            primaryGate.params.maxWithdrawalRequestFee = 0.05 ether; // TODO
        }

        // GateSeal
        config.gateSealFactory = address(0);
        config.sealingCommittee = address(0);
        config.sealDuration = 0;
        config.sealExpiryTimestamp = 0;

        config.secondAdminAddress = vm.envOr(
            "CSM_SECOND_ADMIN_ADDRESS",
            address(0)
        );

        _setUp();
    }
}
