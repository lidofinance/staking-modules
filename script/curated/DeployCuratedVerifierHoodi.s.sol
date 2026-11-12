// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCuratedVerifierBase } from "./DeployCuratedVerifierBase.s.sol";
import { CuratedVerifier } from "../../src/CuratedVerifier.sol";

contract DeployCuratedVerifierHoodi is DeployCuratedVerifierBase {
    constructor() DeployCuratedVerifierBase(560048, 0x209190Ebc2Be80367a15d05e626784Eb94d6A880) {}

    function _grantAdmins(CuratedVerifier verifier) internal override {
        bytes32 role = previous.DEFAULT_ADMIN_ROLE();
        _checkRoleMembersCount(role, 2); // Agent and the second admin.
        verifier.grantRole(role, previous.getRoleMember(role, 0));
        verifier.grantRole(role, previous.getRoleMember(role, 1));
    }
}
