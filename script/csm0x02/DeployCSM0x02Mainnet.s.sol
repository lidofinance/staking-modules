// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCSM0x02Base } from "./DeployCSM0x02Base.s.sol";
import { GIndices } from "../constants/GIndices.sol";

contract DeployCSM0x02Mainnet is DeployCSM0x02Base {
    constructor() DeployCSM0x02Base("mainnet", 1) {
        // Lido addresses
        config.lidoLocatorAddress = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
        config.aragonAgent = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
        config.easyTrackEVMScriptExecutor = 0xFE5986E06210aC1eCC1aDCafc0cc7f8D63B3F977;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/metadata/config.yaml#L58
        config.slotsPerEpoch = 32; // https://github.com/ethereum/consensus-specs/blob/7df1ce30384b13d01617f8ddf930f4035da0f689/specs/phase0/beacon-chain.md?plain=1#L246
        config.clGenesisTime = 1606824023; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/README.md?plain=1#L10
        config.oracleReportEpochsPerFrame = 225 * 28; // 28 days
        config.fastLaneLengthSlots = 300;
        config.consensusVersion = 4;
        config.oracleMembers = new address[](9);
        config.oracleMembers[0] = 0xC4f2704273598d51A0ec76A31C12553ec8f5A891; // MatrixedLink
        config.oracleMembers[1] = 0xE75A431A98487DC69A14Bdd13d858E3238e9C1b3; // Instadapp
        config.oracleMembers[2] = 0xc77d0Bf3AA4778E36a89CDC8bbc9c34d8060637d; // Caliber
        config.oracleMembers[3] = 0xc7442d4d8F3FfEa0fA4a18Ad3062c8137cE21749; // Staking Facilities
        config.oracleMembers[4] = 0x56B3eA8016Da18C6E8CD8135492d242F0dE0DBBC; // Chorus One (Bitwise)
        config.oracleMembers[5] = 0x4E3F2DEeb59eB9a205D82D17647b3e56422e0FEe; // P2P
        config.oracleMembers[6] = 0xd524101C3c40f71Fce7B9312D299603880a06Bdb; // Chainlayer
        config.oracleMembers[7] = 0x99Cd2EF33040879D40BBC77Df81863D97f13C64d; // bloXroute
        config.oracleMembers[8] = 0x5e8Ed9f10307eD6FA793A347e4D0f407D00B9C6f; // Stakefish
        config.hashConsensusQuorum = 5;

        // Verifier
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.verifierFirstSupportedSlot = 364032 * config.slotsPerEpoch; // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7600.md#activation
        config.capellaSlot = 194048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L50
        config.minWithdrawalRatio = 9900;

        // Accounting
        config.defaultBondCurve.push([1, 32 ether]);
        config.defaultBondCurve.push([2, 30 ether]);

        config.minBondLockPeriod = 4 weeks;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 8 weeks;
        config.setResetBondCurveAddress = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config.chargePenaltyRecipient = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c; // locator.treasury()

        // Module
        config.moduleType = "community-onchain-v1"; // Type identifier used by the off-chain tooling
        config.generalDelayedPenaltyReporter = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config.rewindTopUpQueueRoleHolder = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS
        config.topUpQueueLimit = 16;

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0.02 ether;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = type(uint256).max;
        config.defaultAvgPerfLeewayBP = 300;
        config.defaultRewardShareBP = 10000; // 100% of 2% = 2% of the total
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
        config.defaultMaxElWithdrawalRequestFee = 0.1 ether;
        config.penaltiesManager = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS

        // CircuitBreaker
        config.circuitBreaker = 0x6019CB557978296BA3C08a7B73225C0975DFB2F7; // Proposed by LIP-34
        config.circuitBreakerPauser = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // CSM Committee MS

        // DG
        config.resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;
        _setUp();
    }
}
