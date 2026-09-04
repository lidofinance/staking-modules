// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IExitPenalties } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleOnValidatorExitTriggered is ModuleFixtures {
    function test_onValidatorExitTriggered() public assertInvariants {
        uint256 noId = createNodeOperator();
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(IExitPenalties.processTriggeredExit.selector, noId, publicKey, paidFee, exitType)
        );
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
    }

    function test_onValidatorExitTriggered_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = 1;

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.onValidatorExitTriggered(noId, publicKey, paidFee, exitType);
    }
}
