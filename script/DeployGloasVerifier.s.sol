// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { Verifier } from "../src/Verifier.sol";
import { CuratedVerifier } from "../src/CuratedVerifier.sol";
import { ILidoLocator } from "../src/interfaces/ILidoLocator.sol";
import { Slot } from "../src/lib/Types.sol";
import { WCType, toWC } from "./utils/WithdrawalCredentials.sol";
import { GloasVerifierSwap, VoteConfig } from "./utils/Votes.sol";
import { DualGovernance } from "./utils/DualGovernance.sol";
import { JsonBindings } from "./utils/JsonBindings.sol";

struct GloasVerifierParams {
    address lidoLocatorAddress;
    address aragonAgent;
    uint64 slotsPerEpoch;
    uint64 verifierFirstSupportedSlot;
    uint64 capellaSlot;
    /// @dev Unused by `CuratedVerifier`.
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
    /// @dev The Curated module is served by `CuratedVerifier`, the other modules by `Verifier`.
    bool internal curated;
    uint64 public verifierGloasSlot;
    address internal deployer;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error GloasSlotNotSet();
    error CannotBeUsedInMainnet();
    error InvalidSecondAdmin();
    error VoteAlreadySubmitted(uint256 dgProposalId);

    constructor(string memory _chainName, uint256 _chainId) {
        chainName = _chainName;
        chainId = _chainId;
    }

    function run(string memory gitRef, string memory paramsKey) external {
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });
        if (verifierGloasSlot == type(uint64).max) revert GloasSlotNotSet();

        string memory path = vm.envString("DEPLOY_CONFIG");
        address oldVerifier = vm.parseJsonAddress(vm.readFile(path), ".Verifier");

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        vm.label(deployer, "DEPLOYER");

        address newVerifier = _deployVerifier();

        vm.stopBroadcast();

        // writeJson with a key only upserts that key, leaving the rest of the artifact intact
        vm.writeJson(vm.toString(newVerifier), path, ".Verifier");
        vm.writeJson(vm.toString(verifierGloasSlot), path, string.concat(paramsKey, ".verifierGloasSlot"));
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");

        _addToVote(
            GloasVerifierSwap({
                module: module,
                circuitBreaker: config.circuitBreaker,
                oldVerifier: oldVerifier,
                newVerifier: newVerifier
            })
        );
    }

    /// @dev Adds the swap to the vote at `VOTE_CONFIG`, replacing an earlier one of the same module.
    function _addToVote(GloasVerifierSwap memory swap) internal {
        string memory path = vm.envString("VOTE_CONFIG");
        VoteConfig memory vote;
        if (vm.isFile(path)) {
            vote = JsonBindings.deserializeVoteConfig(vm.readFile(path));
            if (vote.dgProposalId != 0) revert VoteAlreadySubmitted(vote.dgProposalId);
        } else {
            vote.dgTimelock = DualGovernance.getTimelock(config.resealManager);
        }

        GloasVerifierSwap[] memory swaps = vote.gloasVerifiers;
        uint256 i;
        while (i < swaps.length && swaps[i].module != swap.module) ++i;
        if (i == swaps.length) {
            swaps = new GloasVerifierSwap[](i + 1);
            for (uint256 j; j < i; ++j) swaps[j] = vote.gloasVerifiers[j];
        }
        swaps[i] = swap;
        vote.gloasVerifiers = swaps;

        vm.writeJson(JsonBindings.serialize(vote), path);
    }

    function _deployVerifier() internal returns (address addr) {
        bytes32 withdrawalCredentials = toWC(
            ILidoLocator(config.lidoLocatorAddress).withdrawalVault(),
            config.verifierWcType
        );

        if (curated) {
            addr = address(
                new CuratedVerifier({
                    withdrawalCredentials: withdrawalCredentials,
                    module: module,
                    slotsPerEpoch: config.slotsPerEpoch,
                    firstSupportedSlot: Slot.wrap(config.verifierFirstSupportedSlot),
                    gloasSlot: Slot.wrap(verifierGloasSlot),
                    capellaSlot: Slot.wrap(config.capellaSlot),
                    admin: deployer
                })
            );
        } else {
            addr = address(
                new Verifier({
                    withdrawalCredentials: withdrawalCredentials,
                    module: module,
                    slotsPerEpoch: config.slotsPerEpoch,
                    firstSupportedSlot: Slot.wrap(config.verifierFirstSupportedSlot),
                    gloasSlot: Slot.wrap(verifierGloasSlot),
                    capellaSlot: Slot.wrap(config.capellaSlot),
                    minWithdrawalRatio: config.minWithdrawalRatio,
                    admin: deployer
                })
            );
        }

        // Both verifiers share the role ids and the access control interface.
        Verifier verifier = Verifier(addr);

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
