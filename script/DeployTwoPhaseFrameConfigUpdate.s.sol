// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";
import { TwoPhaseFrameConfigUpdate } from "../src/utils/TwoPhaseFrameConfigUpdate.sol";
import { JsonObj, Json } from "./utils/Json.sol";

struct TwoPhaseFrameConfigUpdateParams {
    uint256 reportsToProcessBeforeOffsetPhase;
    uint256 reportsToProcessBeforeRestorePhase;
    uint256 offsetPhaseEpochsPerFrame;
    uint256 restorePhaseFastLaneLengthSlots;
}

abstract contract DeployTwoPhaseFrameConfigUpdateBase is Script {
    string internal chainName;
    string internal artifactDir;
    string internal gitRef;
    TwoPhaseFrameConfigUpdateParams internal config;
    uint256 internal expectedChainId;
    address internal deployer;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error MainDeploymentNotFound(string path);
    error InvalidOracleAddress();

    constructor(string memory _chainName, uint256 _expectedChainId) {
        chainName = _chainName;
        expectedChainId = _expectedChainId;
    }

    function run(string memory _gitRef) external returns (address deployed) {
        gitRef = _gitRef;

        if (expectedChainId != block.chainid) {
            revert ChainIdMismatch({ actual: block.chainid, expected: expectedChainId });
        }

        artifactDir = vm.envOr(
            "ARTIFACTS_DIR",
            string(abi.encodePacked("./artifacts/", chainName, "/utils/TwoPhaseFrameConfigUpdate/"))
        );

        string memory mainDeployPath = string(
            abi.encodePacked("./artifacts/", chainName, "/deploy-", chainName, ".json")
        );
        if (!vm.exists(mainDeployPath)) revert MainDeploymentNotFound(mainDeployPath);

        string memory mainDeployJson = vm.readFile(mainDeployPath);
        address oracle = vm.parseJsonAddress(mainDeployJson, ".FeeOracle");

        if (oracle == address(0)) revert InvalidOracleAddress();

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");

        TwoPhaseFrameConfigUpdate.PhasesConfig memory phasesConfig = TwoPhaseFrameConfigUpdate.PhasesConfig({
            reportsToProcessBeforeOffsetPhase: config.reportsToProcessBeforeOffsetPhase,
            reportsToProcessBeforeRestorePhase: config.reportsToProcessBeforeRestorePhase,
            offsetPhaseEpochsPerFrame: config.offsetPhaseEpochsPerFrame,
            restorePhaseFastLaneLengthSlots: config.restorePhaseFastLaneLengthSlots
        });

        TwoPhaseFrameConfigUpdate twoPhaseFrameUpdate = new TwoPhaseFrameConfigUpdate(oracle, phasesConfig);
        deployed = address(twoPhaseFrameUpdate);

        vm.label(deployed, "TwoPhaseFrameConfigUpdate");
        vm.label(oracle, "FeeOracle");

        vm.stopBroadcast();

        _saveDeployJson(deployed, oracle, phasesConfig);
    }

    function _saveDeployJson(
        address deployed,
        address oracle,
        TwoPhaseFrameConfigUpdate.PhasesConfig memory phasesConfig
    ) internal {
        JsonObj memory deployJson = Json.newObj("artifact");

        deployJson.set("TwoPhaseFrameConfigUpdate", deployed);
        deployJson.set("TwoPhaseFrameConfigUpdateParams", abi.encode(config));
        deployJson.set("git-ref", gitRef);

        vm.createDir(artifactDir, true);
        vm.writeJson(deployJson.str, _deployJsonFilename());
    }

    function _deployJsonFilename() internal view returns (string memory) {
        return string(abi.encodePacked(artifactDir, "deploy-", chainName, ".json"));
    }
}
