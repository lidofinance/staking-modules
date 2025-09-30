// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { DeployBase } from "./DeployBase.s.sol";
import { GIndices } from "./constants/GIndices.sol";
import { ICSBondCurve } from "../src/interfaces/ICSBondCurve.sol";

contract DeployHolesky is DeployBase {
    constructor() DeployBase("holesky", 17000) {
        // Lido addresses
        config.lidoLocatorAddress = 0x28FAB2059C713A7F9D8c86Db49f9bb0e96Af1ef8;
        config.aragonAgent = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d;
        config
            .easyTrackEVMScriptExecutor = 0x2819B65021E13CEEB9AC33E77DB32c7e64e7520D;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12;
        config.slotsPerEpoch = 32;
        config.clGenesisTime = 1695902400;
        config.oracleReportEpochsPerFrame = 225 * 7; // 7 days
        config.fastLaneLengthSlots = 600;
        config.consensusVersion = 3;
        config.oracleMembers = new address[](2);
        config.oracleMembers[0] = 0x12A1D74F8697b9f4F1eEBb0a9d0FB6a751366399;
        config.oracleMembers[1] = 0xD892c09b556b547c80B7d8c8cB8d75bf541B2284;
        config.hashConsensusQuorum = 2;

        // Verifier
        // current deployment is on Capella
        config.slotsPerHistoricalRoot = 8192; // @see https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBlockRootInSummary = GIndices.FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.gIFirstPendingConsolidation = GIndices.FIRST_PENDING_CONSOLIDATION_ELECTRA; // prettier-ignore
        config.verifierFirstSupportedSlot = 115968 * config.slotsPerEpoch; // @see https://github.com/eth-clients/holesky/blob/main/metadata/config.yaml#L42
        config.capellaSlot = 256 * config.slotsPerEpoch; // @see https://github.com/eth-clients/holesky/blob/main/metadata/config.yaml#L34

        // Accounting
        // 2 -> 1.9 -> 1.8 -> 1.7 -> 1.6 -> 1.5
        config.defaultBondCurve.push([1, 2 ether]);
        config.defaultBondCurve.push([2, 1.9 ether]);
        config.defaultBondCurve.push([3, 1.8 ether]);
        config.defaultBondCurve.push([4, 1.7 ether]);
        config.defaultBondCurve.push([5, 1.6 ether]);
        config.defaultBondCurve.push([6, 1.5 ether]);
        // 1.5 -> 1.9 -> 1.8 -> 1.7 -> 1.6 -> 1.5
        config.legacyEaBondCurve.push([1, 1.5 ether]);
        config.legacyEaBondCurve.push([2, 1.9 ether]);
        config.legacyEaBondCurve.push([3, 1.8 ether]);
        config.legacyEaBondCurve.push([4, 1.7 ether]);
        config.legacyEaBondCurve.push([5, 1.6 ether]);
        config.legacyEaBondCurve.push([6, 1.5 ether]);

        uint256[2][] memory bondCurve2 = new uint256[2][](6);
        // Prev:
        // 3000000000000000000,4900000000000000000,6700000000000000000,8400000000000000000,10000000000000000000,11500000000000000000
        bondCurve2[0] = uintArr(1, 3 ether);
        bondCurve2[1] = uintArr(2, 1.9 ether);
        bondCurve2[2] = uintArr(3, 1.8 ether);
        bondCurve2[3] = uintArr(4, 1.7 ether);
        bondCurve2[4] = uintArr(5, 1.6 ether);
        bondCurve2[5] = uintArr(6, 1.5 ether);

        uint256[2][] memory bondCurve3 = new uint256[2][](2);
        // Prev:
        // 4000000000000000000,5000000000000000000,6000000000000000000,7000000000000000000
        bondCurve3[0] = uintArr(1, 4 ether);
        bondCurve3[1] = uintArr(2, 1 ether);

        config.extraBondCurves.push(bondCurve2);
        config.extraBondCurves.push(bondCurve3);

        config.minBondLockPeriod = 0;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 8 weeks;
        config.bondReserveMinPeriod = 4 weeks;
        config.enableBondReserve = false;
        config
            .setResetBondCurveAddress = 0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164; // Dev team EOA
        config
            .chargePenaltyRecipient = 0xE92329EC7ddB11D25e25b3c21eeBf11f15eB325d; // locator.treasury()
        // Module
        config.stakingModuleId = 4;
        config.moduleType = "community-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config
            .elRewardsStealingReporter = 0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164; // Dev team EOA

        // CSParameters
        config.defaultKeyRemovalCharge = 0.02 ether;
        config.defaultElRewardsStealingAdditionalFine = 0.1 ether;
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
        config.defaultExitDelayPenalty = 0.1 ether;
        config.defaultMaxWithdrawalRequestFee = 0.1 ether;

        // VettedGate
        config
            .identifiedCommunityStakersGateManager = 0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164; // Dev team EOA
        config.identifiedCommunityStakersGateCurveId = 4;
        config
            .identifiedCommunityStakersGateTreeRoot = 0x359e02c5c065c682839661c9bdfaf38db472629bf5f7a7e8f0261b31dc9332c2; // TODO: update before deployment
        config.identifiedCommunityStakersGateTreeCid = "someCid"; // TODO: update with a real CID before deployment
        // 1.5 -> 1.3
        config.identifiedCommunityStakersGateBondCurve.push([1, 1.5 ether]);
        config.identifiedCommunityStakersGateBondCurve.push([2, 1.3 ether]);

        // Parameters for Identified Community Staker type
        config.identifiedCommunityStakersGateKeyRemovalCharge = 0.01 ether;
        config
            .identifiedCommunityStakersGateELRewardsStealingAdditionalFine = 0.05 ether;
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
        config.identifiedCommunityStakersGateExitDelayPenalty = 0.05 ether;
        config
            .identifiedCommunityStakersGateMaxWithdrawalRequestFee = 0.1 ether;

        // GateSeal
        config.gateSealFactory = 0x1134F7077055b0B3559BE52AfeF9aA22A0E1eEC2;
        config.sealingCommittee = 0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164; // Dev team EOA
        config.sealDuration = 6 days;
        config.sealExpiryTimestamp = block.timestamp + 365 days;

        // DG
        config.resealManager = 0x9dE2273f9f1e81145171CcA927EFeE7aCC64c9fb;

        config.secondAdminAddress = 0xc4DAB3a3ef68C6DFd8614a870D64D475bA44F164; // Dev team EOA
        _setUp();
    }

    function uintArr(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256[2] memory arr) {
        arr[0] = a;
        arr[1] = b;
    }
}
