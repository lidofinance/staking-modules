// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { CuratedVerifier } from "../../src/CuratedVerifier.sol";
import { ICuratedVerifier } from "../../src/interfaces/ICuratedVerifier.sol";
import { ILidoLocator } from "../../src/interfaces/ILidoLocator.sol";
import { Slot } from "../../src/lib/Types.sol";

import { CuratedDeployParams } from "./DeployBase.s.sol";
import { JsonBindings } from "../utils/JsonBindings.sol";

contract DeployCuratedVerifier is Script {
    error ChainIdMismatch(uint256 actual, uint256 expected);

    /// @notice Deploy a CuratedVerifier for the deployed CuratedModule using the module's deployment params.
    /// @param gitRef Git revision of the deployed sources.
    function run(string memory gitRef) external {
        string memory path = vm.envString("DEPLOY_CONFIG");
        string memory artifact = vm.readFile(path);
        uint256 chainId = vm.parseJsonUint(artifact, ".ChainId");
        if (chainId != block.chainid) revert ChainIdMismatch(block.chainid, chainId);

        address curatedModule = vm.parseJsonAddress(artifact, ".CuratedModule");
        CuratedDeployParams memory config = JsonBindings.deserializeCuratedDeployParams(
            artifact,
            ".CuratedDeployParams"
        );

        vm.startBroadcast();
        (, address deployer, ) = vm.readCallers();

        // prettier-ignore
        CuratedVerifier verifier = new CuratedVerifier({
            withdrawalAddress: ILidoLocator(config.lidoLocatorAddress).withdrawalVault(),
            module: curatedModule,
            slotsPerEpoch: uint64(config.slotsPerEpoch),
            gindices: ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: config.gIFirstValidator,
                gIFirstValidatorCurr: config.gIFirstValidator,
                gIFirstHistoricalSummaryPrev: config.gIFirstHistoricalSummary,
                gIFirstHistoricalSummaryCurr: config.gIFirstHistoricalSummary,
                gIFirstBalanceNodePrev: config.gIFirstBalanceNode,
                gIFirstBalanceNodeCurr: config.gIFirstBalanceNode
            }),
            firstSupportedSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
            pivotSlot: Slot.wrap(uint64(config.verifierFirstSupportedSlot)),
            capellaSlot: Slot.wrap(uint64(config.capellaSlot)),
            admin: deployer
        });

        verifier.grantRole(verifier.PAUSE_ROLE(), config.circuitBreaker);
        verifier.grantRole(verifier.PAUSE_ROLE(), config.resealManager);
        verifier.grantRole(verifier.RESUME_ROLE(), config.resealManager);

        if (config.secondAdminAddress != address(0)) {
            verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        }

        verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
        verifier.revokeRole(verifier.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(verifier)), path, ".CuratedVerifier");
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");
    }
}
