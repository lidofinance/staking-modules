// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase } from "./DeployBase.s.sol";
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
        config.identifiedCommunityStakersGateName = "Identified Community Stakers Gate";
        config.identifiedCommunityStakersGateTreeRoot = vm.envOr(
            "CSM_VETTED_GATE_TREE_ROOT",
            bytes32(uint256(0xdeadbeef))
        );
        config.identifiedCommunityStakersGateTreeCid = vm.envOr("CSM_VETTED_GATE_TREE_CID", string("someCid"));
        config.identifiedDVTClusterGateName = "Identified DVT Clusters Gate";
        config.identifiedDVTClusterGateTreeRoot = bytes32(uint256(0xdeadbeef)); // TODO: Set real IDVTC tree root
        config.identifiedDVTClusterGateTreeCid = "someCid"; // TODO: Set real IDVTC tree CID
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

        // Parameters for Identified DVT Cluster type
        config.identifiedDVTClusterBondCurve.push([1, 1.5 ether]);
        config.identifiedDVTClusterBondCurve.push([2, 0.5 ether]);
        config.identifiedDVTClusterRewardShareData.push([1, 5834]); // 58.34% of 6% = 3.5% of the total
        config.identifiedDVTClusterRewardShareData.push([65, 3334]); // 33.34% of 6% = 2% of the total
        config.identifiedDVTClusterQueuePriority = 1;
        config.identifiedDVTClusterQueueMaxDeposits = 40;
        config.identifiedDVTClusterKeyRemovalCharge = 0.01 ether;
        config.identifiedDVTClusterGeneralDelayedPenaltyAdditionalFine = 0.05 ether;
        config.identifiedDVTClusterAllowedExitDelay = 5 days;
        config.identifiedDVTClusterExitDelayFee = 0.05 ether;

        // CircuitBreaker
        config.circuitBreaker = address(0);
        config.circuitBreakerPauser = address(0);

        // DG
        config.resealManager = vm.envAddress("CSM_RESEAL_MANAGER_ADDRESS");

        config.secondAdminAddress = vm.envOr("CSM_SECOND_ADMIN_ADDRESS", address(0));

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
