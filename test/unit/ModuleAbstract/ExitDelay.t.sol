// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { console } from "forge-std/console.sol";
import { Test, Vm } from "forge-std/Test.sol";

import { Batch } from "src/lib/DepositQueueLib.sol";
import { BaseModule } from "src/abstract/BaseModule.sol";
import { BondLock } from "src/abstract/BondLock.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IExitPenalties, ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IGeneralPenalty } from "src/lib/GeneralPenaltyLib.sol";
import { ILidoLocator } from "src/interfaces/ILidoLocator.sol";
import { INOAddresses } from "src/lib/NOAddresses.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { AccountingMock } from "../../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../../helpers/mocks/ParametersRegistryMock.sol";
import { ERC20Testable } from "../../helpers/ERCTestable.sol";
import { ExitPenaltiesMock } from "../../helpers/mocks/ExitPenaltiesMock.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { Stub } from "../../helpers/mocks/Stub.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleExitDeadlineThreshold is ModuleFixtures {
    function test_exitDeadlineThreshold() public assertInvariants {
        uint256 noId = createNodeOperator();
        uint256 exitDeadlineThreshold = module.exitDeadlineThreshold(noId);
        assertEq(exitDeadlineThreshold, parametersRegistry.allowedExitDelay());
    }

    function test_exitDeadlineThreshold_RevertWhenNoNodeOperator()
        public
        assertInvariants
    {
        uint256 noId = 0;
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.exitDeadlineThreshold(noId);
    }
}

abstract contract ModuleIsValidatorExitDelayPenaltyApplicable is
    ModuleFixtures
{
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
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
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
        bool applicable = module.isValidatorExitDelayPenaltyApplicable(
            noId,
            154,
            publicKey,
            eligibleToExit
        );
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
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDeadlineThreshold
        );
    }

    function test_reportValidatorExitDelay_RevertWhen_noNodeOperator() public {
        uint256 noId = 0;
        bytes memory publicKey = randomBytes(48);
        uint256 exitDelay = parametersRegistry.allowedExitDelay();

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorExitDelay(
            noId,
            block.timestamp,
            publicKey,
            exitDelay
        );
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
            abi.encodeWithSelector(
                IExitPenalties.processTriggeredExit.selector,
                noId,
                publicKey,
                paidFee,
                exitType
            )
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
