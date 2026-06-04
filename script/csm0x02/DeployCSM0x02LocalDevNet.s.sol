// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCSM0x02Base } from "./DeployCSM0x02Base.s.sol";
import { GIndices } from "../constants/GIndices.sol";
import { BaseOracle } from "../../src/lib/base-oracle/BaseOracle.sol";
import { HashConsensus } from "../../src/lib/base-oracle/HashConsensus.sol";
import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";

contract DeployCSM0x02LocalDevNet is DeployCSM0x02Base {
    constructor() DeployCSM0x02Base("local-devnet", vm.envUint("DEVNET_CHAIN_ID")) {
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
        config.defaultBondCurve.push([1, 32 ether]);
        config.defaultBondCurve.push([2, 24 ether]);

        config.minBondLockPeriod = 1 days;
        config.maxBondLockPeriod = 7 days;
        config.bondLockPeriod = 1 days;
        config.setResetBondCurveAddress = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        config.chargePenaltyRecipient = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        // Module
        config.moduleType = "community-onchain-v1"; // Just a unique type name to be used by the off-chain tooling
        config.generalDelayedPenaltyReporter = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA
        // TODO: Reconsider the top-up queue limit value for CSM0x02.
        config.topUpQueueLimit = 32;

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
        config.defaultBadPerformancePenalty = 0.1 ether; // TODO: to be reviewed
        config.defaultAttestationsWeight = 54; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultBlocksWeight = 8; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultSyncWeight = 2; // https://eth2book.info/capella/part2/incentives/rewards/
        config.defaultAllowedExitDelay = 4 days;
        config.defaultExitDelayFee = 0.1 ether;
        config.defaultMaxElWithdrawalRequestFee = 0.1 ether;
        config.penaltiesManager = vm.envAddress("CSM_FIRST_ADMIN_ADDRESS"); // Dev team EOA

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
