// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract GateSealVettedTest is CSMIntegrationBase {
    function setUp() public {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_sealVettedGate() public {
        address[] memory sealables = new address[](1);
        sealables[0] = address(vettedGate);
        vm.prank(gateSeal.get_sealing_committee());
        gateSeal.seal(sealables);

        assertTrue(vettedGate.isPaused());
        assertFalse(module.isPaused());
        assertFalse(accounting.isPaused());
        assertFalse(oracle.isPaused());
        assertFalse(verifier.isPaused());
    }
}
