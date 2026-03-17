// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase } from "./DeployBase.s.sol";
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
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.verifierFirstSupportedSlot = vm.envUint("DEVNET_ELECTRA_EPOCH") * config.slotsPerEpoch;
        config.capellaSlot = vm.envUint("DEVNET_CAPELLA_EPOCH") * config.slotsPerEpoch;
        config.minWithdrawalRatio = 9900;

        // Accounting
        // 2.4 -> 1.3
        config.defaultBondCurve.push([1, 2.4 ether]);
        config.defaultBondCurve.push([2, 1.3 ether]);
        // 1.5 -> 1.3
        config.legacyEaBondCurve.push([1, 1.5 ether]);
        config.legacyEaBondCurve.push([2, 1.3 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 7 days;
        config.bondLockPeriod = 1 days;
        config.setResetBondCurveAddress = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        config.chargePenaltyRecipient = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        // Module
        config.moduleType = "community-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config.generalDelayedPenaltyReporter = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0.05 ether;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = type(uint256).max;
        config.defaultAvgPerfLeewayBP = 450;
        config.defaultRewardShareBP = 10000;
        config.defaultStrikesLifetimeFrames = 6;
        config.defaultStrikesThreshold = 3;
        config.queueLowestPriority = 5;
        config.defaultQueuePriority = 5;
        config.defaultQueueMaxDeposits = type(uint32).max;
        config.defaultBadPerformancePenalty = 0.1 ether;
        config.defaultAttestationsWeight = 54; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultBlocksWeight = 8; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultSyncWeight = 2; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultAllowedExitDelay = 4 days;
        config.defaultExitDelayFee = 0.1 ether;
        config.defaultMaxElWithdrawalRequestFee = 0.1 ether;
        config.penaltiesManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

        // VettedGate
        config.identifiedCommunityStakersGateManager = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        config.identifiedCommunityStakersGateCurveId = 2;
        config.identifiedCommunityStakersGateTreeRoot = vm.envOr(
            "CSM_VETTED_GATE_TREE_ROOT",
            bytes32(uint256(0xdeadbeef))
        );
        config.identifiedCommunityStakersGateTreeCid = vm.envOr("CSM_VETTED_GATE_TREE_CID", string("someCid"));
        // 1.5 -> 1.3
        config.identifiedCommunityStakersGateBondCurve.push([1, 1.5 ether]);
        config.identifiedCommunityStakersGateBondCurve.push([2, 1.3 ether]);

        // Parameters for Identified Community Staker type
        config.identifiedCommunityStakersGateKeyRemovalCharge = 0.01 ether;
        config.identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine = 0.05 ether;
        config.identifiedCommunityStakersGateKeysLimit = type(uint248).max;
        config.identifiedCommunityStakersGateAvgPerfLeewayData.push([1, 500]);
        config.identifiedCommunityStakersGateAvgPerfLeewayData.push([151, 300]);
        config.identifiedCommunityStakersGateRewardShareData.push([1, 10000]);
        config.identifiedCommunityStakersGateRewardShareData.push([17, 5834]);
        config.identifiedCommunityStakersGateStrikesLifetimeFrames = 6;
        config.identifiedCommunityStakersGateStrikesThreshold = 4;
        config.identifiedCommunityStakersGateQueuePriority = 0;
        config.identifiedCommunityStakersGateQueueMaxDeposits = 10;
        config.identifiedCommunityStakersGateBadPerformancePenalty = 0.172 ether;
        config.identifiedCommunityStakersGateAttestationsWeight = 54;
        config.identifiedCommunityStakersGateBlocksWeight = 4;
        config.identifiedCommunityStakersGateSyncWeight = 2;
        config.identifiedCommunityStakersGateAllowedExitDelay = 5 days;
        config.identifiedCommunityStakersGateExitDelayFee = 0.05 ether;
        config.identifiedCommunityStakersGateMaxElWithdrawalRequestFee = 0.1 ether;

        // GateSeal
        config.gateSealFactory = 0x0000000000000000000000000000000000000000;
        config.sealingCommittee = 0x0000000000000000000000000000000000000000;
        config.sealDuration = 0;
        config.sealExpiryTimestamp = 0;

        // DG
        config.resealManager = vm.envAddress("CSM_RESEAL_MANAGER_ADDRESS");

        config.secondAdminAddress = vm.envOr("CSM_SECOND_ADMIN_ADDRESS", address(0));

        _setUp();
    }
}
