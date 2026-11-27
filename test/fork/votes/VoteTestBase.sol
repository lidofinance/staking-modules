// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { Votes } from "../../../script/votes/Votes.sol";

/// @dev The tests of a vote run while it is pending, on `RPC_URL` where `just vote-pending` simulated it right after
///      the block `VOTE_PREV_BLOCK`, to compare the state at that block with the one after the vote.
abstract contract VoteTestBase is Test, DeploymentFixtures {
    uint256 private afterVoteFork;

    /// @dev Skips unless the vote is pending, returns its file with the state after the vote selected.
    function _setUpVote(string memory name) internal returns (string memory json) {
        Env memory env = envVars();
        vm.skip(_isEmpty(vm.envOr("VOTES_DIR", string(""))), "VOTES_DIR is not set");
        string memory file = Votes.path(name);
        vm.skip(!vm.isFile(file), string.concat("No pending vote at ", file));

        afterVoteFork = vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        json = vm.readFile(file);
        vm.skip(Votes.isExecuted(json), string.concat("The vote is executed: ", file));
    }

    function _selectBeforeVote() internal {
        Env memory env = envVars();
        assertNotEq(env.VOTE_PREV_BLOCK, 0, "VOTE_PREV_BLOCK is not set");
        vm.createSelectFork(env.RPC_URL, env.VOTE_PREV_BLOCK);
    }

    function _selectAfterVote() internal {
        vm.selectFork(afterVoteFork);
    }

    /// @dev The sections of the module under test are keyed by the directory of its artifact.
    function _moduleKey() internal returns (string memory) {
        string[] memory parts = vm.split(envVars().DEPLOY_CONFIG, "/");
        return parts[parts.length - 2];
    }
}
