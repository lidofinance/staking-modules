// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test, Vm } from "forge-std/Test.sol";
import { ExitPenalties } from "src/ExitPenalties.sol";
import { IExitPenalties, ExitPenaltyInfo } from "src/interfaces/IExitPenalties.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { ParametersRegistryMock } from "../helpers/mocks/ParametersRegistryMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { ValidatorStrikesMock } from "../helpers/mocks/ValidatorStrikesMock.sol";

contract ExitPenaltiesTestBase is Test, Utilities, Fixtures {
    ExitPenalties internal exitPenalties;
    CSMMock internal csm;
    ValidatorStrikesMock internal strikes;
    address internal stranger;
    address internal admin;
    IAccounting internal accounting;
    ParametersRegistryMock internal parametersRegistry;
    uint256 internal constant NO_ID = 0;

    function setUp() public {
        csm = new CSMMock();
        parametersRegistry = ParametersRegistryMock(
            address(csm.PARAMETERS_REGISTRY())
        );
        accounting = CSMMock(csm).accounting();
        strikes = new ValidatorStrikesMock();
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");

        exitPenalties = new ExitPenalties(
            address(csm),
            address(parametersRegistry),
            address(strikes)
        );
        _enableInitializers(address(exitPenalties));
    }
}

contract ExitPenaltiesTestMisc is ExitPenaltiesTestBase {
    function test_constructor() public {
        exitPenalties = new ExitPenalties(
            address(csm),
            address(parametersRegistry),
            address(strikes)
        );
        assertEq(address(exitPenalties.MODULE()), address(csm));
        assertEq(
            address(exitPenalties.PARAMETERS_REGISTRY()),
            address(parametersRegistry)
        );
        assertEq(address(exitPenalties.ACCOUNTING()), address(accounting));
        assertEq(address(exitPenalties.STRIKES()), address(strikes));
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IExitPenalties.ZeroModuleAddress.selector);
        new ExitPenalties(
            address(0),
            address(parametersRegistry),
            address(strikes)
        );
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress()
        public
    {
        vm.expectRevert(IExitPenalties.ZeroParametersRegistryAddress.selector);
        new ExitPenalties(address(csm), address(0), address(strikes));
    }

    function test_constructor_RevertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(IExitPenalties.ZeroStrikesAddress.selector);
        new ExitPenalties(
            address(csm),
            address(parametersRegistry),
            address(0)
        );
    }
}

contract ExitPenaltiesTestProcessExitDelayReport is ExitPenaltiesTestBase {
    function test_processExitDelayReport() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getExitDelayFee(0);

        vm.expectEmit(address(exitPenalties));
        emit IExitPenalties.ValidatorExitDelayProcessed(
            NO_ID,
            publicKey,
            penalty
        );
        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(NO_ID, publicKey, eligibleToExit);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.delayFee.value, penalty);
    }

    function test_processExitDelayReport_revertWhen_notApplicable() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        vm.expectRevert(
            IExitPenalties.ValidatorExitDelayNotApplicable.selector
        );
        exitPenalties.processExitDelayReport(
            NO_ID,
            publicKey,
            eligibleToExit - 1 seconds
        );
        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(
            exitPenaltyInfo.delayFee.isValue,
            false,
            "Penalty should not be applied"
        );
    }

    function test_processExitDelayReport_ignoreWhen_alreadyReported() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getExitDelayFee(0);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(NO_ID, publicKey, eligibleToExit);

        parametersRegistry.setExitDelayFee(0, penalty + 1);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(
            NO_ID,
            publicKey,
            eligibleToExit + 1
        );
        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(
            exitPenaltyInfo.delayFee.value,
            penalty,
            "Penalty should not be updated"
        );
    }

    function test_processExitDelayReport_revertWhen_SenderIsNotModule() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(stranger);
        vm.expectRevert(IExitPenalties.SenderIsNotModule.selector);
        exitPenalties.processExitDelayReport(NO_ID, publicKey, eligibleToExit);
    }
}

contract ExitPenaltiesTestProcessTriggeredExit is ExitPenaltiesTestBase {
    function test_processTriggeredExit() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.expectEmit(address(exitPenalties));
        emit IExitPenalties.TriggeredExitFeeRecorded(
            NO_ID,
            exitType,
            publicKey,
            paidFee,
            paidFee
        );
        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(NO_ID, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, paidFee);
    }

    function test_processTriggeredExit_zeroMaxFeeValue() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        parametersRegistry.setMaxWithdrawalRequestFee(0, 0);

        vm.expectEmit(address(exitPenalties));
        emit IExitPenalties.TriggeredExitFeeRecorded(
            NO_ID,
            exitType,
            publicKey,
            paidFee,
            0
        );
        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(NO_ID, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.isValue, true);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, 0);
    }

    function test_processTriggeredExit_voluntaryExit() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID();

        vm.recordLogs();

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(NO_ID, publicKey, paidFee, exitType);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, 0);
    }

    function test_processTriggeredExit_doubleReporting() public {
        bytes memory publicKey = randomBytes(48);
        uint256 initialPaidFee = 0.1 ether;
        uint256 newPaidFee = 0.2 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(
            NO_ID,
            publicKey,
            initialPaidFee,
            exitType
        );

        vm.recordLogs();

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(
            NO_ID,
            publicKey,
            newPaidFee,
            exitType
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(
            exitPenaltyInfo.withdrawalRequestFee.value,
            initialPaidFee,
            "paid fee should not be updated"
        );
    }

    function test_processTriggeredExit_feeMoreThanMax() public {
        bytes memory publicKey = randomBytes(48);
        uint256 maxFee = parametersRegistry.getMaxWithdrawalRequestFee(0);
        uint256 paidFee = maxFee + 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(NO_ID, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(
            exitPenaltyInfo.withdrawalRequestFee.value,
            maxFee,
            "paid fee should be capped to max fee"
        );
    }

    function test_processTriggeredExit_revertWhen_SenderIsNotModule() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.prank(stranger);
        vm.expectRevert(IExitPenalties.SenderIsNotModule.selector);
        exitPenalties.processTriggeredExit(NO_ID, publicKey, paidFee, exitType);
    }
}

contract ExitPenaltiesTestProcessStrikesReport is ExitPenaltiesTestBase {
    function test_processStrikesReport() public {
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getBadPerformancePenalty(0);

        vm.expectEmit(address(exitPenalties));
        emit IExitPenalties.StrikesPenaltyProcessed(NO_ID, publicKey, penalty);
        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(NO_ID, publicKey);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.strikesPenalty.value, penalty);
    }

    function test_processStrikesReport_doubleReporting() public {
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getBadPerformancePenalty(0);

        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(NO_ID, publicKey);

        parametersRegistry.setBadPerformancePenalty(0, penalty + 1);

        vm.recordLogs();
        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(NO_ID, publicKey);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(
            exitPenaltyInfo.strikesPenalty.value,
            penalty,
            "penalty should not be updated"
        );
    }

    function test_processStrikesReport_revertWhen_SenderIsNotStrikes() public {
        bytes memory publicKey = randomBytes(48);
        vm.prank(stranger);
        vm.expectRevert(IExitPenalties.SenderIsNotStrikes.selector);
        exitPenalties.processStrikesReport(NO_ID, publicKey);
    }
}

contract ExitPenaltiesTestIsValidatorExitDelayPenaltyApplicable is
    ExitPenaltiesTestBase
{
    function test_isValidatorExitDelayPenaltyApplicable_notDelayedYet() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID);
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            NO_ID,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable, "Penalty should not be applicable yet");
    }

    function test_isValidatorExitDelayPenaltyApplicable_delayed() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            NO_ID,
            publicKey,
            eligibleToExit
        );
        assertTrue(applicable, "Penalty should be applicable");
    }

    function test_isValidatorExitDelayPenaltyApplicable_alreadyReported()
        public
    {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(NO_ID, publicKey, eligibleToExit);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            NO_ID,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable, "Penalty should not be applicable anymore");
    }

    function test_isValidatorExitDelayPenaltyApplicable_revertWhen_SenderIsNotModule()
        public
    {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(NO_ID) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(stranger);
        vm.expectRevert(IExitPenalties.SenderIsNotModule.selector);
        exitPenalties.isValidatorExitDelayPenaltyApplicable(
            NO_ID,
            publicKey,
            eligibleToExit
        );
    }
}
