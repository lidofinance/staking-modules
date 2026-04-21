// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployBase, CuratedGateConfig } from "./DeployBase.s.sol";
import { GIndices } from "../constants/GIndices.sol";

contract DeployHoodi is DeployBase {
    constructor() DeployBase("hoodi", 560048) {
        // Lido addresses
        config.lidoLocatorAddress = 0xe2EF9536DAAAEBFf5b1c130957AB3E80056b06D8;
        config.aragonAgent = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
        config.easyTrackEVMScriptExecutor = 0x79a20FD0FA36453B2F45eAbab19bfef43575Ba9E;
        config.proxyAdmin = config.aragonAgent;

        // Oracle
        config.secondsPerSlot = 12;
        config.slotsPerEpoch = 32;
        config.clGenesisTime = 1742213400;
        config.oracleReportEpochsPerFrame = 225 * 7; // 7 days
        config.fastLaneLengthSlots = 128;
        config.consensusVersion = 4;
        config.oracleMembers = new address[](12);
        config.oracleMembers[0] = 0xf7aE520e99ed3C41180B5E12681d31Aa7302E4e5;
        config.oracleMembers[1] = 0x948A62cc0414979dc7aa9364BA5b96ECb29f8736;
        config.oracleMembers[2] = 0x1932f53B1457a5987791a40Ba91f71c5Efd5788F;
        config.oracleMembers[3] = 0x219743f1911d84B32599BdC2Df21fC8Dba6F81a2;
        config.oracleMembers[4] = 0xfe43A8B0b481Ae9fB1862d31826532047d2d538c;
        config.oracleMembers[5] = 0x4c75FA734a39f3a21C57e583c1c29942F021C6B7;
        config.oracleMembers[6] = 0xD3b1e36A372Ca250eefF61f90E833Ca070559970;
        config.oracleMembers[7] = 0xcA80ee7313A315879f326105134F938676Cfd7a9;
        config.oracleMembers[8] = 0x99B2B75F490fFC9A29E4E1f5987BE8e30E690aDF;
        config.oracleMembers[9] = 0x43C45C2455C49eed320F463fF4f1Ece3D2BF5aE2;
        config.oracleMembers[10] = 0x44e3996629a9026BF95C4Be3c1a38242D1E64a01;
        config.oracleMembers[11] = 0x0f30c4ceBE7F3057e81949B0Ab1591FC256226b5;
        config.hashConsensusQuorum = 7;

        // Verifier
        config.gIFirstWithdrawal = GIndices.FIRST_WITHDRAWAL_ELECTRA;
        config.gIFirstValidator = GIndices.FIRST_VALIDATOR_ELECTRA;
        config.gIFirstHistoricalSummary = GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA; // prettier-ignore
        config.gIFirstBalanceNode = GIndices.FIRST_BALANCE_NODE_ELECTRA;
        config.verifierFirstSupportedSlot = 2048 * config.slotsPerEpoch; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L41
        config.capellaSlot = 0; // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L33
        config.minWithdrawalRatio = 9950;

        // Accounting
        // 11 -> 1
        config.defaultBondCurve.push([1, 11 ether]);
        config.defaultBondCurve.push([2, 1 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 365 days;
        config.bondLockPeriod = 60 days;
        config.chargePenaltyRecipient = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD; // locator.treasury()

        // Module
        config.moduleType = "curated-onchain-v2"; // Just a unique type name to be used by the off-chain tooling
        config.generalDelayedPenaltyReporter = 0x84DffcfB232594975C608DE92544Ff239a24c9E9; // CMC on Hoodi

        // ParametersRegistry
        config.defaultKeyRemovalCharge = 0;
        config.defaultGeneralDelayedPenaltyAdditionalFine = 0.1 ether;
        config.defaultKeysLimit = 80;
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
        config.penaltiesManager = 0x84DffcfB232594975C608DE92544Ff239a24c9E9; // CMC on Hoodi

        // Curated gates
        // Professional Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.treeRoot = bytes32(type(uint256).max);
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT";
            gate.params.metaRegistryBondCurveWeight = _m(50000);
        }

        // Professional Trusted Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = 0x2135d436079a77c58134f53d371e9292070a173bbc87d9c7d23bad2d8da35e33;
            gate.treeCid = "QmSZWfHiM896LNoVmHkkQ13XJDCiQbDzMWa8V43pKYrWa7";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Public Good Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(type(uint256).max);
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Decentralization Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(type(uint256).max);
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Extra Effort Operator Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(type(uint256).max);
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Intra-Operator DVT Cluster Gate
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = 0xe0250b81599ea522c64802477d407fd87b1ae17f5426317d355689d86a781088;
            gate.treeCid = "QmZUZYHTLhBKybzF9szFf7tgxegqR4C1mZs6K5H92o2H2f";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 8750]); // 87.5% of 4% = 3.5% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        // Intra-Operator DVT Cluster Plus Gate (identical to the one above but with 4% fee)
        {
            CuratedGateConfig storage gate = config.curatedGates.push();
            gate.bondCurve.push([1, 11 ether]);
            gate.bondCurve.push([2, 0.1 ether]);
            gate.bondCurve.push([19, 0.7 ether]);
            gate.treeRoot = bytes32(type(uint256).max);
            gate.treeCid = "QmU4cnyaKWgMVCZVLiuQaqu6yGXahjzi4F1Vcnq2SXBBmT";
            gate.params.generalDelayedPenaltyAdditionalFine = _m(0.05 ether);
            gate.params.keysLimit = _m(500);
            gate.params.rewardShareData.push([1, 10000]); // 100% of 4% = 4% of the total
            gate.params.metaRegistryBondCurveWeight = _m(100000);
            gate.params.exitDelayFee = _m(0.005 ether);
        }

        config.curatedGatePauseManager = 0x84DffcfB232594975C608DE92544Ff239a24c9E9; // CMC on Hoodi

        // MetaRegistry
        config.setOperatorInfoManager = 0x84DffcfB232594975C608DE92544Ff239a24c9E9; // CMC on Hoodi

        // CircuitBreaker
        config.circuitBreaker = 0x44a5789dFeDa59cD176Ab5709ec2F4829dE4d555;
        config.circuitBreakerPauser = 0x84DffcfB232594975C608DE92544Ff239a24c9E9; // CMC on Hoodi

        // DG
        config.resealManager = 0x05172CbCDb7307228F781436b327679e4DAE166B;

        config.secondAdminAddress = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53; // Dev team EOA
        _setUp();
    }
}
