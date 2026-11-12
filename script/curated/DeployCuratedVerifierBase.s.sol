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
    address internal aragonAgent;
    address internal secondAdminAddress;
    address internal circuitBreaker;
    address internal resealManager;

    error ChainIdMismatch(uint256 actual, uint256 expected);
    error PreviousRoleMembersCountMismatch(bytes32 role, uint256 actual, uint256 expected);
    error PreviousRoleMemberMissing(bytes32 role, address account);

    constructor(uint256 _chainId) {
        chainId = _chainId;
    }

    /// @notice Deploy a CuratedVerifier replacing the Curated module Verifier.
    ///         The constructor params are taken from that Verifier, the role holders must match its ones.
    /// @param gitRef Git revision of the deployed sources.
    function run(string memory gitRef) external {
        if (chainId != block.chainid) revert ChainIdMismatch({ actual: block.chainid, expected: chainId });

        bytes32 pauseRole = previous.PAUSE_ROLE();
        _checkPreviousRoleMembersCount(pauseRole, 2);
        _checkPreviousRoleMember(pauseRole, circuitBreaker);
        _checkPreviousRoleMember(pauseRole, resealManager);

        bytes32 resumeRole = previous.RESUME_ROLE();
        _checkPreviousRoleMembersCount(resumeRole, 1);
        _checkPreviousRoleMember(resumeRole, resealManager);

        bytes32 adminRole = previous.DEFAULT_ADMIN_ROLE();
        _checkPreviousRoleMembersCount(adminRole, secondAdminAddress == address(0) ? 1 : 2);
        _checkPreviousRoleMember(adminRole, aragonAgent);
        if (secondAdminAddress != address(0)) _checkPreviousRoleMember(adminRole, secondAdminAddress);

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
        verifier.grantRole(pauseRole, circuitBreaker);
        verifier.grantRole(pauseRole, resealManager);
        verifier.grantRole(resumeRole, resealManager);

        if (secondAdminAddress != address(0)) verifier.grantRole(adminRole, secondAdminAddress);

        verifier.grantRole(adminRole, aragonAgent);
        verifier.revokeRole(adminRole, deployer);
        vm.stopBroadcast();

        string memory path = vm.envString("DEPLOY_CONFIG");
        vm.writeJson(vm.toString(address(verifier)), path, ".CuratedVerifier");
        vm.writeJson(string.concat('"', gitRef, '"'), path, ".git-ref");
    }

    function _checkPreviousRoleMembersCount(bytes32 role, uint256 expected) internal view {
        uint256 actual = previous.getRoleMemberCount(role);
        if (actual != expected) revert PreviousRoleMembersCountMismatch(role, actual, expected);
    }

    function _checkPreviousRoleMember(bytes32 role, address account) internal view {
        if (!previous.hasRole(role, account)) revert PreviousRoleMemberMissing(role, account);
    }
}
