// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BaseModule } from "../../../src/abstract/BaseModule.sol";
import { ICircuitBreaker } from "../../../src/interfaces/ICircuitBreaker.sol";
import { GloasVerifiers, VerifierSwap } from "../../../script/votes/GloasVerifiers.sol";
import { VoteTestBase } from "./VoteTestBase.sol";

contract GloasVerifiersVoteTest is VoteTestBase {
    VerifierSwap internal swap;

    function setUp() public {
        string memory json = _setUpVote(GloasVerifiers.NAME);
        string memory moduleKey = _moduleKey();
        (bool found, VerifierSwap memory s) = GloasVerifiers.read(json, moduleKey);
        vm.skip(!found, string.concat("No Verifier swap for ", moduleKey));
        swap = s;
    }

    function test_oldVerifierRoles_beforeVote() public {
        _selectBeforeVote();
        _assertOnlyVerifier(swap.oldVerifier);
    }

    function test_pauser_beforeVote() public {
        _selectBeforeVote();
        assertNotEq(swap.pauser, address(0), "pauser");
        assertEq(ICircuitBreaker(swap.circuitBreaker).getPauser(swap.oldVerifier), swap.pauser, "old Verifier");
    }

    function test_swapMatchesDeployment() public view {
        assertEq(swap.module, address(module), "module");
        assertEq(swap.circuitBreaker, address(circuitBreaker), "circuitBreaker");
        assertEq(swap.newVerifier, address(verifier), "newVerifier");
        assertEq(address(verifier.MODULE()), swap.module, "newVerifier module");
    }

    function test_newVerifier_beforeVote() public {
        _selectBeforeVote();
        BaseModule m = BaseModule(swap.module);
        assertFalse(m.hasRole(m.VERIFIER_ROLE(), swap.newVerifier), "VERIFIER_ROLE");
        assertFalse(
            m.hasRole(m.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE(), swap.newVerifier),
            "REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE"
        );
        assertEq(ICircuitBreaker(swap.circuitBreaker).getPauser(swap.newVerifier), address(0), "pauser");
    }

    function test_newVerifierRoles_afterVote() public view {
        _assertOnlyVerifier(swap.newVerifier);
    }

    function test_pauser_afterVote() public {
        ICircuitBreaker cb = ICircuitBreaker(swap.circuitBreaker);
        _selectBeforeVote();
        address pauser = cb.getPauser(swap.oldVerifier);
        _selectAfterVote();
        assertEq(cb.getPauser(swap.newVerifier), pauser, "new Verifier");
        assertEq(cb.getPauser(swap.oldVerifier), address(0), "old Verifier");
    }

    function _assertOnlyVerifier(address account) internal view {
        BaseModule m = BaseModule(swap.module);
        bytes32 verifierRole = m.VERIFIER_ROLE();
        bytes32 reportRole = m.REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE();
        assertEq(m.getRoleMemberCount(verifierRole), 1, "VERIFIER_ROLE holders");
        assertEq(m.getRoleMember(verifierRole, 0), account, "VERIFIER_ROLE");
        assertEq(m.getRoleMemberCount(reportRole), 1, "REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE holders");
        assertEq(m.getRoleMember(reportRole, 0), account, "REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE");
    }
}
