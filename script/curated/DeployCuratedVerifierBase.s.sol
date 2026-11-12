// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";

import { CuratedVerifier } from "../../src/CuratedVerifier.sol";
import { Verifier } from "../../src/Verifier.sol";
import { ICuratedVerifier } from "../../src/interfaces/ICuratedVerifier.sol";

abstract contract DeployCuratedVerifierBase is Script {
    uint256 internal chainId;
    Verifier internal previous;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error UnexpectedRoleMembersCount(bytes32 role, uint256 actual, uint256 expected);

    constructor(uint256 _chainId, address _previous) {
        chainId = _chainId;
        previous = Verifier(_previous);
    }

    /// @notice Deploy a CuratedVerifier replacing the Curated module Verifier.
    ///         The constructor params and the role holders are taken from that Verifier.
    /// @param gitRef Git revision of the deployed sources.
    function run(string memory gitRef) external {
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });

        bytes32 pauseRole = previous.PAUSE_ROLE();
        bytes32 resumeRole = previous.RESUME_ROLE();
        _checkRoleMembersCount(pauseRole, 2); // CircuitBreaker and ResealManager.
        _checkRoleMembersCount(resumeRole, 1); // ResealManager.

        vm.startBroadcast();
        (, address deployer, ) = vm.readCallers();

        // prettier-ignore
        CuratedVerifier verifier = new CuratedVerifier({
            withdrawalAddress: previous.WITHDRAWAL_ADDRESS(),
            module: address(previous.MODULE()),
            slotsPerEpoch: previous.SLOTS_PER_EPOCH(),
            gindices: ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: previous.GI_FIRST_VALIDATOR_PREV(),
                gIFirstValidatorCurr: previous.GI_FIRST_VALIDATOR_CURR(),
                gIFirstHistoricalSummaryPrev: previous.GI_FIRST_HISTORICAL_SUMMARY_PREV(),
                gIFirstHistoricalSummaryCurr: previous.GI_FIRST_HISTORICAL_SUMMARY_CURR(),
                gIFirstBalanceNodePrev: previous.GI_FIRST_BALANCES_NODE_PREV(),
                gIFirstBalanceNodeCurr: previous.GI_FIRST_BALANCES_NODE_CURR()
            }),
            firstSupportedSlot: previous.FIRST_SUPPORTED_SLOT(),
            pivotSlot: previous.PIVOT_SLOT(),
            capellaSlot: previous.CAPELLA_SLOT(),
            admin: deployer
        });

        // Both verifiers share the role ids.
        verifier.grantRole(pauseRole, previous.getRoleMember(pauseRole, 0));
        verifier.grantRole(pauseRole, previous.getRoleMember(pauseRole, 1));
        verifier.grantRole(resumeRole, previous.getRoleMember(resumeRole, 0));

        _grantAdmins(verifier);
        verifier.revokeRole(verifier.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopBroadcast();

        string memory path = vm.envString("DEPLOY_CONFIG");
        vm.writeJson(vm.toString(address(verifier)), path, ".CuratedVerifier");
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");
    }

    /// @dev Grants the admin role to the admins of the previous Verifier.
    function _grantAdmins(CuratedVerifier verifier) internal virtual;

    function _checkRoleMembersCount(bytes32 role, uint256 expected) internal view {
        uint256 actual = previous.getRoleMemberCount(role);
        if (actual != expected) revert UnexpectedRoleMembersCount(role, actual, expected);
    }
}
