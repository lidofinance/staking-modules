// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCuratedVerifierBase } from "./DeployCuratedVerifierBase.s.sol";
import { CuratedVerifier } from "../../src/CuratedVerifier.sol";

contract DeployCuratedVerifierMainnet is DeployCuratedVerifierBase {
    constructor() DeployCuratedVerifierBase(1, 0xC392F457960f1B13Ebaf1aa6C065479dD507E1E3) {}

    function _grantAdmins(CuratedVerifier verifier) internal override {
        bytes32 role = previous.DEFAULT_ADMIN_ROLE();
        _checkRoleMembersCount(role, 1); // Agent.
        verifier.grantRole(role, previous.getRoleMember(role, 0));
    }
}
