// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { DeployBase } from "./DeployBase.s.sol";
import { GIndices } from "./constants/GIndices.sol";

contract DeployMainnet is DeployBase {
    constructor() DeployBase("mainnet", 1) {
        // Lido addresses
        config.lidoLocatorAddress = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
        config.aragonAgent = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
        config
            .easyTrackEVMScriptExecutor = 0xFE5986E06210aC1eCC1aDCafc0cc7f8D63B3F977;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/metadata/config.yaml#L58
        config.slotsPerEpoch = 32; // https://github.com/ethereum/consensus-specs/blob/7df1ce30384b13d01617f8ddf930f4035da0f689/specs/phase0/beacon-chain.md?plain=1#L246
        config.clGenesisTime = 1606824023; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/README.md?plain=1#L10
        config.oracleReportEpochsPerFrame = 225 * 28; // 28 days
        config.fastLaneLengthSlots = 1800;
        config.consensusVersion = 3;
        config.oracleMembers = new address[](9);
        config.oracleMembers[0] = 0x73181107c8D9ED4ce0bbeF7A0b4ccf3320C41d12; // Instadapp
        config.oracleMembers[1] = 0x285f8537e1dAeEdaf617e96C742F2Cf36d63CcfB; // Chorus One
        config.oracleMembers[2] = 0x404335BcE530400a5814375E7Ec1FB55fAff3eA2; // Staking Facilities
        config.oracleMembers[3] = 0x946D3b081ed19173dC83Cd974fC69e1e760B7d78; // Stakefish
        config.oracleMembers[4] = 0x007DE4a5F7bc37E2F26c0cb2E8A95006EE9B89b5; // P2P
        config.oracleMembers[5] = 0xc79F702202E3A6B0B6310B537E786B9ACAA19BAf; // Chainlayer
        config.oracleMembers[6] = 0x61c91ECd902EB56e314bB2D5c5C07785444Ea1c8; // bloXroute
        config.oracleMembers[7] = 0xe57B3792aDCc5da47EF4fF588883F0ee0c9835C9; // MatrixedLink
        config.oracleMembers[8] = 0x4118DAD7f348A4063bD15786c299De2f3B1333F3; // Caliber
        config.hashConsensusQuorum = 5;

        // Verifier
        config.slotsPerHistoricalRoot = 8192; // @see https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBlockRootInSummary = GIndices.FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.gIFirstPendingConsolidation = GIndices.FIRST_PENDING_CONSOLIDATION_ELECTRA; // prettier-ignore
        config.verifierFirstSupportedSlot = 364032 * config.slotsPerEpoch; // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7600.md#activation
        config.capellaSlot = 194048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L50

        // Accounting
        // 2.4 -> 1.3
        config.defaultBondCurve.push([1, 2.4 ether]);
        config.defaultBondCurve.push([2, 1.3 ether]);
        // 1.5 -> 1.3
        config.legacyEaBondCurve.push([1, 1.5 ether]);
        config.legacyEaBondCurve.push([2, 1.3 ether]);

        config.minBondLockPeriod = 4 weeks;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 8 weeks;
        config
            .setResetBondCurveAddress = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config
            .chargePenaltyRecipient = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c; // locator.treasury()

        // Module
        config.stakingModuleId = _nextStakingModuleId(
            config.lidoLocatorAddress
        );
        config.moduleType = "community-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config
            .generalDelayedPenaltyReporter = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS

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
            .identifiedCommunityStakersGateManager = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config.identifiedCommunityStakersGateCurveId = 2;
        config
            .identifiedCommunityStakersGateTreeRoot = 0x91545c42adde0f5d82e4c228f81449eab20349c1d31a8538e0468466f93495c5;
        config
            .identifiedCommunityStakersGateTreeCid = "bafkreido7ieacbe6nlhdivxfp2gd5kxovofngf6qdmahih4laihm675e2a";
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
        config.gateSealFactory = 0x6C82877cAC5a7A739f16Ca0A89c0A328B8764A24;
        config.sealingCommittee = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config.sealDuration = 11 days;
        config.sealExpiryTimestamp = block.timestamp + 365 days;

        // DG
        config.resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;
        _setUp();
    }
}
