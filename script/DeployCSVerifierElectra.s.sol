// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

// Usage: forge script --private-key=$PRIVATE_KEY ./script/DeployCSVerifierElectra.s.sol:DeployCSVerifier[Mainnet|Hoodi|DevNet]

pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { CSVerifier } from "../src/CSVerifier.sol";
import { ICSVerifier } from "../src/interfaces/ICSVerifier.sol";
import { GIndex } from "../src/lib/GIndex.sol";
import { Slot } from "../src/lib/Types.sol";
import { JsonObj, Json } from "./utils/Json.sol";
import { GIndices } from "./constants/GIndices.sol";

struct Config {
    address withdrawalVault;
    address module;
    GIndex gIFirstWithdrawalPrev;
    GIndex gIFirstWithdrawalCurr;
    GIndex gIFirstValidatorPrev;
    GIndex gIFirstValidatorCurr;
    GIndex gIFirstHistoricalSummaryPrev;
    GIndex gIFirstHistoricalSummaryCurr;
    GIndex gIFirstBlockRootInSummaryPrev;
    GIndex gIFirstBlockRootInSummaryCurr;
    Slot firstSupportedSlot;
    Slot pivotSlot;
    Slot capellaSlot;
    uint64 slotsPerEpoch;
    uint64 slotsPerHistoricalRoot;
    address admin;
    string chainName;
}

abstract contract DeployCSVerifier is Script {
    CSVerifier internal verifier;
    Config internal config;
    string internal artifactDir;

    function run() public {
        artifactDir = vm.envOr("ARTIFACTS_DIR", string("./artifacts/latest/"));

        vm.startBroadcast();
        {
            // prettier-ignore
            verifier = new CSVerifier({
                withdrawalAddress: config.withdrawalVault,
                module: config.module,
                slotsPerEpoch: config.slotsPerEpoch,
                slotsPerHistoricalRoot: config.slotsPerHistoricalRoot,
                gindices: ICSVerifier.GIndices({
                    gIFirstWithdrawalPrev: config.gIFirstWithdrawalPrev,
                    gIFirstWithdrawalCurr: config.gIFirstWithdrawalCurr,
                    gIFirstValidatorPrev: config.gIFirstValidatorPrev,
                    gIFirstValidatorCurr: config.gIFirstValidatorCurr,
                    gIFirstHistoricalSummaryPrev: config.gIFirstHistoricalSummaryPrev,
                    gIFirstHistoricalSummaryCurr: config.gIFirstHistoricalSummaryCurr,
                    gIFirstBlockRootInSummaryPrev: config.gIFirstBlockRootInSummaryPrev,
                    gIFirstBlockRootInSummaryCurr: config.gIFirstBlockRootInSummaryCurr
                }),
                firstSupportedSlot: config.firstSupportedSlot,
                pivotSlot: config.pivotSlot,
                capellaSlot: config.capellaSlot,
                admin: config.admin
            });
        }
        vm.stopBroadcast();

        JsonObj memory deployJson = Json.newObj("artifact");
        deployJson.set("CSVerifier", address(verifier));
        vm.writeJson(deployJson.str, _deployJsonFilename());
        console.log("CSVerifier deployed at:", address(verifier));
    }

    function _deployJsonFilename() internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    artifactDir,
                    "deploy-verifier-",
                    config.chainName,
                    ".json"
                )
            );
    }
}

contract DeployCSVerifierHoodi is DeployCSVerifier {
    constructor() {
        config = Config({
            withdrawalVault: 0x4473dCDDbf77679A643BdB654dbd86D67F8d32f2,
            module: 0x79CEf36D84743222f37765204Bec41E92a93E59d,
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192, // @see https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
            gIFirstWithdrawalPrev: GIndices.FIRST_WITHDRAWAL_DENEB,
            gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
            gIFirstValidatorPrev: GIndices.FIRST_VALIDATOR_DENEB,
            gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
            gIFirstHistoricalSummaryPrev: GIndices
                .FIRST_HISTORICAL_SUMMARY_DENEB,
            gIFirstHistoricalSummaryCurr: GIndices
                .FIRST_HISTORICAL_SUMMARY_ELECTRA,
            gIFirstBlockRootInSummaryPrev: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB,
            gIFirstBlockRootInSummaryCurr: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
            firstSupportedSlot: Slot.wrap(0), // @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L37
            pivotSlot: Slot.wrap(65536), // 2048 * 32, @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L41
            capellaSlot: Slot.wrap(0), // 0 * 32, @see https://github.com/eth-clients/hoodi/blob/main/metadata/config.yaml#L33
            admin: 0x0534aA41907c9631fae990960bCC72d75fA7cfeD,
            chainName: "hoodi"
        });
    }
}

contract DeployCSVerifierMainnet is DeployCSVerifier {
    constructor() {
        config = Config({
            withdrawalVault: 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f,
            module: 0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F,
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192, // @see https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters
            gIFirstWithdrawalPrev: GIndices.FIRST_WITHDRAWAL_DENEB,
            gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
            gIFirstValidatorPrev: GIndices.FIRST_VALIDATOR_DENEB,
            gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
            gIFirstHistoricalSummaryPrev: GIndices
                .FIRST_HISTORICAL_SUMMARY_DENEB,
            gIFirstHistoricalSummaryCurr: GIndices
                .FIRST_HISTORICAL_SUMMARY_ELECTRA,
            gIFirstBlockRootInSummaryPrev: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB,
            gIFirstBlockRootInSummaryCurr: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
            firstSupportedSlot: Slot.wrap(8626176), // 269_568 * 32, @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L53
            pivotSlot: Slot.wrap(11649024), // 364_032 * 32 https://github.com/ethereum/EIPs/blob/master/EIPS/eip-7600.md#activation
            capellaSlot: Slot.wrap(6209536), // 194_048 * 32, @see https://github.com/eth-clients/mainnet/blob/main/metadata/config.yaml#L50
            admin: 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c, // Aragon Agent
            chainName: "mainnet"
        });
    }
}

contract DeployCSVerifierDevNet is DeployCSVerifier {
    constructor() {
        config = Config({
            withdrawalVault: vm.envAddress("CSM_WITHDRAWAL_VAULT"),
            module: vm.envAddress("CSM_MODULE"),
            slotsPerEpoch: uint64(vm.envUint("DEVNET_SLOTS_PER_EPOCH")),
            slotsPerHistoricalRoot: uint64(
                vm.envUint("DEVNET_SLOTS_PER_HISTORICAL_ROOT")
            ),
            gIFirstWithdrawalPrev: GIndices.FIRST_WITHDRAWAL_DENEB,
            gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
            gIFirstValidatorPrev: GIndices.FIRST_VALIDATOR_DENEB,
            gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
            gIFirstHistoricalSummaryPrev: GIndices
                .FIRST_HISTORICAL_SUMMARY_DENEB,
            gIFirstHistoricalSummaryCurr: GIndices
                .FIRST_HISTORICAL_SUMMARY_ELECTRA,
            gIFirstBlockRootInSummaryPrev: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB,
            gIFirstBlockRootInSummaryCurr: GIndices
                .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
            firstSupportedSlot: Slot.wrap(0),
            pivotSlot: Slot.wrap(
                uint64(vm.envUint("DEVNET_ELECTRA_EPOCH")) * 32
            ),
            capellaSlot: Slot.wrap(
                uint64(vm.envUint("DEVNET_CAPELLA_EPOCH")) * 32
            ),
            admin: 0x0534aA41907c9631fae990960bCC72d75fA7cfeD,
            chainName: "devnet"
        });
    }
}
