// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase, CuratedGateConfig } from "./DeployBase.s.sol";
import { GIndices } from "../constants/GIndices.sol";

contract DeployMainnet is DeployBase {
    constructor() DeployBase("mainnet", 1) {
        // Lido addresses
        config.lidoLocatorAddress = 0xC1d0b3DE6792Bf6b4b37EccdcC24e45978Cfd2Eb;
        config.aragonAgent = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
        config.easyTrackEVMScriptExecutor = 0xFE5986E06210aC1eCC1aDCafc0cc7f8D63B3F977;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/metadata/config.yaml#L58
        config.slotsPerEpoch = 32; // https://github.com/ethereum/consensus-specs/blob/7df1ce30384b13d01617f8ddf930f4035da0f689/specs/phase0/beacon-chain.md?plain=1#L246
        config.clGenesisTime = 1606824023; // https://github.com/eth-clients/mainnet/blob/f6b7882618a5ad2c1d2731ae35e5d16a660d5bb7/README.md?plain=1#L10
        config.oracleReportEpochsPerFrame = 225 * 14;
        config.fastLaneLengthSlots = 300;
        config.consensusVersion = 4;
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
        config.verifierFirstSupportedSlot = 364032 * config.slotsPerEpoch; // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7600.md#activation
        config.capellaSlot = 194048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L50
        config.minWithdrawalRatio = 9950;

        // Accounting
        // 11 -> 1
        config.defaultBondCurve.push([1, 11 ether]);
        config.defaultBondCurve.push([2, 1 ether]);

        config.minBondLockPeriod = 4 weeks;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 60 days;
        config.chargePenaltyRecipient = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c; // locator.treasury()

        // Module
        config.moduleType = "curated-onchain-v2"; // TODO reconsider
        config.generalDelayedPenaltyReporter = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // TODO reconsider once we have CMC address

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
        config.penaltiesManager = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // TODO reconsider once we have CMC address

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

        config.curatedGatePauseManager = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // TODO reconsider once we have CMC address

        // MetaRegistry
        config.setOperatorInfoManager = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // TODO reconsider once we have CMC address

        // GateSeal
        config.gateSealFactory = 0x6C82877cAC5a7A739f16Ca0A89c0A328B8764A24;
        config.sealingCommittee = 0xC52fC3081123073078698F1EAc2f1Dc7Bd71880f; // TODO reconsider once we have CMC address
        config.sealDuration = 14 days;
        config.sealExpiryTimestamp = block.timestamp + 365 days;

        // DG
        config.resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;
        _setUp();
    }
}
