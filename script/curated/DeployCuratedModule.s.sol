// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";
import { CuratedModule } from "../../src/CuratedModule.sol";

contract DeployCuratedModule is Script {
    error ChainIdMismatch(uint256 actual, uint256 expected);

    /// @notice Deploy a CuratedModule implementation preserving the deployed module's immutables.
    /// @param gitRef Git revision of the deployed sources.
    function run(string memory gitRef) external {
        string memory path = vm.envString("DEPLOY_CONFIG");
        string memory artifact = vm.readFile(path);
        uint256 chainId = vm.parseJsonUint(artifact, ".ChainId");
        if (chainId != block.chainid) revert ChainIdMismatch(block.chainid, chainId);

        CuratedModule cm = CuratedModule(vm.parseJsonAddress(artifact, ".CuratedModule"));

        vm.startBroadcast();
        CuratedModule implementation = new CuratedModule({
            moduleType: cm.getType(),
            lidoLocator: address(cm.LIDO_LOCATOR()),
            parametersRegistry: address(cm.PARAMETERS_REGISTRY()),
            accounting: address(cm.ACCOUNTING()),
            exitPenalties: address(cm.EXIT_PENALTIES()),
            metaRegistry: address(cm.META_REGISTRY())
        });
        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(implementation)), path, ".CuratedModuleImpl");
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");
    }
}
