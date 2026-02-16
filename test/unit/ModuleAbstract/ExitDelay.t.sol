// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IExitPenalties } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleExitDeadlineThreshold is ModuleFixtures {
    function test_exitDeadlineThreshold() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        assertEq(exitDeadlineThreshold, parametersRegistry.allowedExitDelay());
    }

    function test_exitDeadlineThreshold_RevertWhenNoNodeOperator() public assertInvariants {
        uint256 noId = 0;
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.exitDeadlineThreshold(noId);
    }
}

abstract contract ModuleIsValidatorExitDelayPenaltyApplicable is ModuleFixtures {
    function test_isValidatorExitDelayPenaltyApplicable_notApplicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(false);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(noId, 154, publicKey, eligibleToExit);
        assertFalse(applicable);
    }

    function test_isValidatorExitDelayPenaltyApplicable_applicable() public {
        uint256 noId = createNodeOperator();
        uint256 eligibleToExit = module.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        exitPenalties.mock_isValidatorExitDelayPenaltyApplicable(true);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.isValidatorExitDelayPenaltyApplicable.selector,
                noId,
                publicKey,
                eligibleToExit
            )
        );
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(noId, 154, publicKey, eligibleToExit);
        assertTrue(applicable);
    }
}

abstract contract ModuleReportValidatorExitDelay is ModuleFixtures {
    function test_reportValidatorExitDelay() public {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        vm.expectCall(
            address(exitPenalties),
            abi.encodeWithSelector(
                IExitPenalties.processExitDelayReport.selector,
                noId,
                publicKey,
                exitDeadlineThreshold
            )
        );
        module.reportValidatorExitDelay(noId, block.timestamp, publicKey, exitDeadlineThreshold);
    }

    function test_reportValidatorExitDelay_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 exitDelay = parametersRegistry.allowedExitDelay();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorExitDelay(noId, block.timestamp, publicKey, exitDelay);
    }
}

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
