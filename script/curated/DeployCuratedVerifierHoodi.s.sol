// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCuratedVerifierBase } from "./DeployCuratedVerifierBase.s.sol";
import { Verifier } from "../../src/Verifier.sol";

contract DeployCuratedVerifierHoodi is DeployCuratedVerifierBase {
    constructor() DeployCuratedVerifierBase(560048) {
        previous = Verifier(0x209190Ebc2Be80367a15d05e626784Eb94d6A880);
        aragonAgent = 0x0534aA41907c9631fae990960bCC72d75fA7cfeD;
        secondAdminAddress = 0x4AF43Ee34a6fcD1fEcA1e1F832124C763561dA53;
        circuitBreaker = 0x44a5789dFeDa59cD176Ab5709ec2F4829dE4d555;
        resealManager = 0x05172CbCDb7307228F781436b327679e4DAE166B;
    }
}
