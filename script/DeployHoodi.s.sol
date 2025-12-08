// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { DeployBase } from "./DeployBase.s.sol";
import { GIndices } from "./constants/GIndices.sol";

contract DeployHoodi is DeployBase {
    constructor() DeployBase("hoodi", 560048) {
        // Lido addresses
        config.lidoLocatorAddress = 0xe2EF9536DAAAEBFf5b1c130957AB3E80056b06D8;
        config.aragonAgent = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
        config
            .easyTrackEVMScriptExecutor = 0x79a20FD0FA36453B2F45eAbab19bfef43575Ba9E;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12;
        config.slotsPerEpoch = 32;
        config.clGenesisTime = 1742213400;
        config.oracleReportEpochsPerFrame = 1575; // 7 days
        config.fastLaneLengthSlots = 32;
        config.consensusVersion = 3;
        config.oracleMembers = new address[](12);
        config.oracleMembers[0] = 0xcA80ee7313A315879f326105134F938676Cfd7a9;
        config.oracleMembers[1] = 0xf03B8DC8762B97F13Ac82e6F94bE3Ed002FF7459;
        config.oracleMembers[2] = 0x1932f53B1457a5987791a40Ba91f71c5Efd5788F;
        config.oracleMembers[3] = 0x4c75FA734a39f3a21C57e583c1c29942F021C6B7;
        config.oracleMembers[4] = 0x99B2B75F490fFC9A29E4E1f5987BE8e30E690aDF;
        config.oracleMembers[5] = 0x219743f1911d84B32599BdC2Df21fC8Dba6F81a2;
        config.oracleMembers[6] = 0xD3b1e36A372Ca250eefF61f90E833Ca070559970;
        config.oracleMembers[7] = 0xf7aE520e99ed3C41180B5E12681d31Aa7302E4e5;
        config.oracleMembers[8] = 0xB1cC91878c1831893D39C2Bb0988404ca5Fa7918;
        config.oracleMembers[9] = 0xfe43A8B0b481Ae9fB1862d31826532047d2d538c;
        config.oracleMembers[10] = 0x43C45C2455C49eed320F463fF4f1Ece3D2BF5aE2;
        config.oracleMembers[11] = 0x948A62cc0414979dc7aa9364BA5b96ECb29f8736;
        config.hashConsensusQuorum = 7;

        // Verifier
        config.slotsPerHistoricalRoot = 8192; // @see https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBlockRootInSummary = GIndices.FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.gIFirstPendingConsolidation = GIndices.FIRST_PENDING_CONSOLIDATION_ELECTRA; // prettier-ignore
        config.verifierFirstSupportedSlot = 2048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L41
        config.capellaSlot = 0; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L33

        // Accounting
        // 2.4 -> 1.3
        config.defaultBondCurve.push([1, 2.4 ether]);
        config.defaultBondCurve.push([2, 1.3 ether]);
        // 1.5 -> 1.3
        config.legacyEaBondCurve.push([1, 1.5 ether]);
        config.legacyEaBondCurve.push([2, 1.3 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 8 weeks;
        config
            .setResetBondCurveAddress = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        config
            .chargePenaltyRecipient = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD; // locator.treasury()
        // Module
        config.stakingModuleId = _nextStakingModuleId(
            config.lidoLocatorAddress
        );
        config.moduleType = "community-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config
            .generalDelayedPenaltyReporter = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0.02 ether;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = type(uint256).max;
        config.defaultAvgPerfLeewayBP = 300;
        config.defaultRewardShareBP = 5834; // 58.34% of 6% = 3.5% of the total
        config.defaultStrikesLifetimeFrames = 6;
        config.defaultStrikesThreshold = 3;
        config.queueLowestPriority = 5;
        config.defaultQueuePriority = 5;
        config.defaultQueueMaxDeposits = type(uint32).max;
        config.defaultBadPerformancePenalty = 0.258 ether;
        config.defaultAttestationsWeight = 54; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultBlocksWeight = 8; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultSyncWeight = 2; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultAllowedExitDelay = 4 days;
        config.defaultExitDelayFee = 0.1 ether;
        config.defaultMaxWithdrawalRequestFee = 0.1 ether;

        // VettedGate
        config
            .identifiedCommunityStakersGateManager = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        config.identifiedCommunityStakersGateCurveId = 2;
        config
            .identifiedCommunityStakersGateTreeRoot = 0x6ddbc639b18ef7eee4e4262baf6e2bec58724b40b9e557df4bc78a0d9c2e0607; // See the first value in artifacts/hoodi/ics/merkle-tree.json
        config
            .identifiedCommunityStakersGateTreeCid = "bafkreicr363zly5gj3gkpmamu2qzcpevw6tylwc767fxi3vfc2skcxanfi";
        // 1.5 -> 1.3
        config.identifiedCommunityStakersGateBondCurve.push([1, 1.5 ether]);
        config.identifiedCommunityStakersGateBondCurve.push([2, 1.3 ether]);

        // Parameters for Identified Community Staker type
        config.identifiedCommunityStakersGateKeyRemovalCharge = 0.01 ether;
        config
            .identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine = 0.05 ether;
        config.identifiedCommunityStakersGateKeysLimit = type(uint248).max;
        config.identifiedCommunityStakersGateAvgPerfLeewayData.push([1, 500]);
        config.identifiedCommunityStakersGateAvgPerfLeewayData.push([151, 300]);
        config.identifiedCommunityStakersGateRewardShareData.push([1, 10000]);
        config.identifiedCommunityStakersGateRewardShareData.push([17, 5834]);
        config.identifiedCommunityStakersGateStrikesLifetimeFrames = 6;
        config.identifiedCommunityStakersGateStrikesThreshold = 4;
        config.identifiedCommunityStakersGateQueuePriority = 0;
        config.identifiedCommunityStakersGateQueueMaxDeposits = 10;
        config
            .identifiedCommunityStakersGateBadPerformancePenalty = 0.172 ether;
        config.identifiedCommunityStakersGateAttestationsWeight = 54;
        config.identifiedCommunityStakersGateBlocksWeight = 4;
        config.identifiedCommunityStakersGateSyncWeight = 2;
        config.identifiedCommunityStakersGateAllowedExitDelay = 5 days;
        config.identifiedCommunityStakersGateExitDelayFee = 0.05 ether;
        config
            .identifiedCommunityStakersGateMaxWithdrawalRequestFee = 0.1 ether;

        // GateSeal
        config.gateSealFactory = 0xA402349F560D45310D301E92B1AA4DeCABe147B3;
        config.sealingCommittee = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        config.sealDuration = 11 days;
        config.sealExpiryTimestamp = block.timestamp + 365 days;

        // DG
        config.resealManager = 0x05172CbCDb7307228F781436b327679e4DAE166B;

        config.secondAdminAddress = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        _setUp();
    }
}
