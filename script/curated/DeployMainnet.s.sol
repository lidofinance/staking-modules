// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase, CuratedGateConfig, AdditionalBondRegistryConfig } from "./DeployBase.s.sol";
import { StrikeThreshold } from "../../src/interfaces/INodeOperatorStrikes.sol";
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
        config.oracleMembers[1] = 0x4118DAD7f348A4063bD15786c299De2f3B1333F3; // Caliber
        config.oracleMembers[2] = 0x404335BcE530400a5814375E7Ec1FB55fAff3eA2; // Staking Facilities
        config.oracleMembers[3] = 0x8dB977C13CAA938BC58464bFD622DF0570564b78; // Chorus One
        config.oracleMembers[4] = 0x007DE4a5F7bc37E2F26c0cb2E8A95006EE9B89b5; // P2P
        config.oracleMembers[5] = 0xc79F702202E3A6B0B6310B537E786B9ACAA19BAf; // Chainlayer
        config.oracleMembers[6] = 0x61c91ECd902EB56e314bB2D5c5C07785444Ea1c8; // bloXroute
        config.oracleMembers[7] = 0xe57B3792aDCc5da47EF4fF588883F0ee0c9835C9; // MatrixedLink
        config.oracleMembers[8] = 0x042a9e5acCfa17e28300F1b5967f20891E973922; // Stakefish
        config.hashConsensusQuorum = 5;

        // Verifier
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
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
        config.moduleType = "curated-onchain-v2";
        config.generalDelayedPenaltyReporter = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc

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
        config.penaltiesManager = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc

        // Curated gates
        // Professional Operator Gate
        // This gate is deployed "empty" since there are no plans to onboard new operators to CMv2 in the nearest future. The gate will be populated later by the CMC if needed.
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Professional Operator Gate";
            gate.treeRoot = 0x1111111111111111111111111111111111111111111111111111111111111111; // Unusable root. Effectively means that the gate is disabled until the real root is set.
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT"; // Points to the "null" json file
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
            gate.treeRoot = 0x2be2e6ef3183615954ff2eef0a1425133132db440efa6c2b6162906d92057a97; // /artifacts/mainnet/curated/gates/pto/merkle-tree.json
            gate.treeCid = "bafkreidgr4wofdx5x2efyianenyi3ldq5hxareq6ydj6pjoolpu3izqq2u";
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
            gate.treeRoot = 0x57db3289376dfbe035e073d81d5b297b8f5269fbdfee12643ded0180aac80839; // /artifacts/mainnet/curated/gates/pgo/merkle-tree.json
            gate.treeCid = "bafkreihicf5dj4rfa42j4prxegrzxfcdkhwzgvgqjhuntgytdvffxkhjim";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Decentralization Operator Gate
        // This gate is deployed "empty" since the participants list will not be available at the time of deployment. The gate will be populated later by the CMC.
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Decentralization Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = 0x1111111111111111111111111111111111111111111111111111111111111111; // Unusable root. Effectively means that the gate is disabled until the real root is set.
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT"; // Points to the "null" json file
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Extra Effort Operator Gate
        // This gate is deployed "empty" since the participants list will not be available at the time of deployment. The gate will be populated later by the CMC.
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.name = "Extra Effort Operator Gate";
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = 0x1111111111111111111111111111111111111111111111111111111111111111; // Unusable root. Effectively means that the gate is disabled until the real root is set.
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT"; // Points to the "null" json file
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
            gate.treeRoot = 0xfda6c221ae0f44dfa57c64324ebbd0c468bb402cbcc20326ad65a18e96a3df0c; // /artifacts/mainnet/curated/gates/iodvtc/merkle-tree.json
            gate.treeCid = "bafkreigm3mqlqdto2ggxpq22w7tblfbx4p4o4a3gudf2lkfduwxeh2m62e";
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
            gate.treeRoot = 0x1111111111111111111111111111111111111111111111111111111111111111; // Unusable root. Effectively means that the gate is disabled until the real root is set.
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT"; // Points to the "null" json file
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        config.curatedGatePauseManager = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc

        // MetaRegistry
        config.setOperatorInfoManager = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc

        // CircuitBreaker
        config.circuitBreaker = 0x6019CB557978296BA3C08a7B73225C0975DFB2F7; // Proposed by LIP-34
        config.circuitBreakerPauser = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc

        // DG
        config.resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;

        // CurveMultiplier
        config.additionalBondRegistryConfig.curveMultiplierCooldown = 7 days;
        // TODO: reconsider — placeholder initial boost steps.
        config.additionalBondRegistryConfig.boostSteps.push([uint256(5_000), 2_000]);
        config.additionalBondRegistryConfig.boostSteps.push([uint256(10_000), 8_000]);

        // NodeOperatorStrikes
        config.strikesCommittee = 0x2570e0b22AD904501dfB0d49575991ACB801dD91; // CMC https://docs.lido.fi/multisigs/committees#220-curated-module-committee-cmc
        // TODO: finalize strike weight-reduction thresholds
        config.strikesThresholds.push(StrikeThreshold({ minCount: 2, reductionBP: 2_500 }));
        config.strikesThresholds.push(StrikeThreshold({ minCount: 3, reductionBP: 5_000 }));
        config.strikesThresholds.push(StrikeThreshold({ minCount: 4, reductionBP: 7_500 }));
        config.strikesThresholds.push(StrikeThreshold({ minCount: 5, reductionBP: 10_000 }));

        _setUp();
    }
}
