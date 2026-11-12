// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCuratedVerifierBase } from "./DeployCuratedVerifierBase.s.sol";
import { Verifier } from "../../src/Verifier.sol";

contract DeployCuratedVerifierMainnet is DeployCuratedVerifierBase {
    constructor() DeployCuratedVerifierBase(1) {
        previous = Verifier(0xC392F457960f1B13Ebaf1aa6C065479dD507E1E3);
        aragonAgent = 0x3e40D73EB977Dc6a537aF587D48316feE66E9C8c;
        circuitBreaker = 0x6019CB557978296BA3C08a7B73225C0975DFB2F7;
        resealManager = 0x7914b5a1539b97Bd0bbd155757F25FD79A522d24;
    }
}
