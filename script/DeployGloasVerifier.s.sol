// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { Verifier } from "../src/Verifier.sol";
import { CuratedModule } from "../src/CuratedModule.sol";
import { ILidoLocator } from "../src/interfaces/ILidoLocator.sol";
import { Slot } from "../src/lib/Types.sol";
import { WCType, toWC } from "./utils/WithdrawalCredentials.sol";

struct GloasVerifierParams {
    address lidoLocatorAddress;
    address aragonAgent;
    uint64 slotsPerEpoch;
    uint64 verifierFirstSupportedSlot;
    uint64 capellaSlot;
    uint256 minWithdrawalRatio;
    WCType verifierWcType;
    address circuitBreaker;
    address resealManager;
    address secondAdminAddress;
}

abstract contract DeployGloasVerifierBase is Script {
    string public chainName;
    uint256 internal chainId;
    GloasVerifierParams internal config;
    address internal module;
    uint64 public verifierGloasSlot;
    address internal deployer;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error CannotBeUsedInMainnet();
    error InvalidSecondAdmin();

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    /// @notice Deploy the Gloas Verifier and update the deployment artifact.
    /// @param gitRef Git revision of the deployed sources.
    /// @param paramsKey Deployment parameters key in the artifact.
    function run(string memory gitRef, string memory paramsKey) public virtual {
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });
        string memory path = vm.envString("DEPLOY_CONFIG");

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");

        Verifier verifier = _deployVerifier();

        vm.stopBroadcast();

        // writeJson with a key only upserts that key, leaving the rest of the artifact intact
        vm.writeJson(vm.toString(address(verifier)), path, ".VerifierGloas");
        vm.writeJson(vm.toString(verifierGloasSlot), path, string.concat(paramsKey, ".verifierGloasSlot"));
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");
    }

    function _deployCuratedModule() internal {
        CuratedModule cm = CuratedModule(module);

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

        string memory path = vm.envString("DEPLOY_CONFIG");
        vm.writeJson(vm.toString(address(implementation)), path, ".CuratedModuleImpl");
    }

    function _deployVerifier() internal returns (Verifier verifier) {
        verifier = new Verifier({
            withdrawalCredentials: toWC(
                ILidoLocator(config.lidoLocatorAddress).withdrawalVault(),
                config.verifierWcType
            ),
            module: module,
            slotsPerEpoch: config.slotsPerEpoch,
            firstSupportedSlot: Slot.wrap(config.verifierFirstSupportedSlot),
            gloasSlot: Slot.wrap(verifierGloasSlot),
            capellaSlot: Slot.wrap(config.capellaSlot),
            minWithdrawalRatio: config.minWithdrawalRatio,
            admin: deployer
        });

        if (config.secondAdminAddress != address(0)) {
            if (config.secondAdminAddress == deployer) revert InvalidSecondAdmin();
            if (keccak256(abi.encodePacked(chainName)) == keccak256("mainnet")) revert CannotBeUsedInMainnet();
            verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.secondAdminAddress);
        }

        verifier.grantRole(verifier.PAUSE_ROLE(), config.resealManager);
        verifier.grantRole(verifier.RESUME_ROLE(), config.resealManager);
        verifier.grantRole(verifier.PAUSE_ROLE(), config.circuitBreaker);
        verifier.grantRole(verifier.DEFAULT_ADMIN_ROLE(), config.aragonAgent);
        verifier.revokeRole(verifier.DEFAULT_ADMIN_ROLE(), deployer);
    }
}
