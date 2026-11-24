// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { DualGovernance } from "../utils/DualGovernance.sol";

/// @dev A pending vote of a chain is the file `<VOTES_DIR>/<name>.json`. It holds every value the vote hard-codes,
///      keyed by the artifact directory of the module it changes (`csm`, `csm0x02`, `curated`) or by another
///      component, and the Dual Governance proposal of the vote, `dgProposalId` being zero until it is submitted.
library Votes {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error VoteAlreadySubmitted(string file, uint256 dgProposalId);

    function path(string memory name) internal view returns (string memory) {
        return string.concat(vm.envString("VOTES_DIR"), "/", name, ".json");
    }

    /// @dev Creates the vote file if missing, so that deploy scripts can add their sections to it.
    function open(string memory name, address dgTimelock) internal returns (string memory file) {
        file = path(name);
        if (vm.isFile(file)) {
            uint256 dgProposalId = vm.parseJsonUint(vm.readFile(file), ".dgProposalId");
            if (dgProposalId != 0) revert VoteAlreadySubmitted(file, dgProposalId);
            return file;
        }

        vm.createDir(vm.envString("VOTES_DIR"), true);
        vm.writeJson(string.concat('{"dgTimelock":"', vm.toString(dgTimelock), '","dgProposalId":0}'), file);
    }

    function isExecuted(string memory json) internal view returns (bool) {
        return
            DualGovernance.isProposalExecuted(
                vm.parseJsonAddress(json, ".dgTimelock"),
                vm.parseJsonUint(json, ".dgProposalId")
            );
    }
}
