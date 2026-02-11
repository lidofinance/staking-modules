// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CuratedGate } from "../../../../src/CuratedGate.sol";
import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract GateSealCuratedTest is CuratedIntegrationBase {
    function setUp() public {
        _setUpModule();
    }

    function test_sealCuratedGates() public {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates");

        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(curatedGates);

        for (uint256 i = 0; i < gatesCount; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            assertTrue(gate.isPaused());
        }
    }
}
