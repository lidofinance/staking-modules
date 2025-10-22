// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { CSExitPenalties } from "src/CSExitPenalties.sol";
import { ICSExitPenalties, ExitPenaltyInfo } from "src/interfaces/ICSExitPenalties.sol";
import { ICSAccounting } from "src/interfaces/ICSAccounting.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { CSParametersRegistryMock } from "../helpers/mocks/CSParametersRegistryMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { CSStrikesMock } from "../helpers/mocks/CSStrikesMock.sol";

contract CSExitPenaltiesTestBase is Test, Utilities, Fixtures {
    CSExitPenalties internal exitPenalties;
    CSMMock internal csm;
    CSStrikesMock internal strikes;
    address internal stranger;
    address internal admin;
    ICSAccounting internal accounting;
    CSParametersRegistryMock internal parametersRegistry;
    uint256 internal constant noId = 0;

    function setUp() public {
        csm = new CSMMock();
        parametersRegistry = CSParametersRegistryMock(
            address(csm.PARAMETERS_REGISTRY())
        );
        accounting = CSMMock(csm).accounting();
        strikes = new CSStrikesMock();
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");

        exitPenalties = new CSExitPenalties(
            address(csm),
            address(parametersRegistry),
            address(strikes)
        );
        _enableInitializers(address(exitPenalties));
    }
}

contract CSExitPenaltiesTestMisc is CSExitPenaltiesTestBase {
    function test_constructor() public {
        exitPenalties = new CSExitPenalties(
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
        vm.expectRevert(ICSExitPenalties.ZeroModuleAddress.selector);
        new CSExitPenalties(
            address(0),
            address(parametersRegistry),
            address(strikes)
        );
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress()
        public
    {
        vm.expectRevert(
            ICSExitPenalties.ZeroParametersRegistryAddress.selector
        );
        new CSExitPenalties(address(csm), address(0), address(strikes));
    }

    function test_constructor_RevertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(ICSExitPenalties.ZeroStrikesAddress.selector);
        new CSExitPenalties(
            address(csm),
            address(parametersRegistry),
            address(0)
        );
    }
}

contract CSExitPenaltiesTestProcessExitDelayReport is CSExitPenaltiesTestBase {
    function test_processExitDelayReport() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getExitDelayFee(0);

        vm.expectEmit(address(exitPenalties));
        emit ICSExitPenalties.ValidatorExitDelayProcessed(
            noId,
            publicKey,
            penalty
        );
        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(noId, publicKey, eligibleToExit);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(exitPenaltyInfo.delayFee.value, penalty);
    }

    function test_processExitDelayReport_revertWhen_notApplicable() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        vm.expectRevert(
            ICSExitPenalties.ValidatorExitDelayNotApplicable.selector
        );
        exitPenalties.processExitDelayReport(
            noId,
            publicKey,
            eligibleToExit - 1 seconds
        );
        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(
            exitPenaltyInfo.delayFee.isValue,
            false,
            "Penalty should not be applied"
        );
    }

    function test_processExitDelayReport_ignoreWhen_alreadyReported() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getExitDelayFee(0);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(noId, publicKey, eligibleToExit);

        parametersRegistry.setExitDelayFee(0, penalty + 1);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(
            noId,
            publicKey,
            eligibleToExit + 1
        );
        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(
            exitPenaltyInfo.delayFee.value,
            penalty,
            "Penalty should not be updated"
        );
    }

    function test_processExitDelayReport_revertWhen_SenderIsNotModule() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(stranger);
        vm.expectRevert(ICSExitPenalties.SenderIsNotModule.selector);
        exitPenalties.processExitDelayReport(noId, publicKey, eligibleToExit);
    }
}

contract CSExitPenaltiesTestProcessTriggeredExit is CSExitPenaltiesTestBase {
    function test_processTriggeredExit() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.expectEmit(address(exitPenalties));
        emit ICSExitPenalties.TriggeredExitFeeRecorded(
            noId,
            exitType,
            publicKey,
            paidFee,
            paidFee
        );
        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(noId, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, paidFee);
    }

    function test_processTriggeredExit_zeroMaxFeeValue() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        parametersRegistry.setMaxWithdrawalRequestFee(0, 0);

        vm.expectEmit(address(exitPenalties));
        emit ICSExitPenalties.TriggeredExitFeeRecorded(
            noId,
            exitType,
            publicKey,
            paidFee,
            0
        );
        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(noId, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.isValue, true);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, 0);
    }

    function test_processTriggeredExit_voluntaryExit() public {
        bytes memory publicKey = randomBytes(48);
        uint256 paidFee = 0.1 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID();

        vm.recordLogs();

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(noId, publicKey, paidFee, exitType);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(exitPenaltyInfo.withdrawalRequestFee.value, 0);
    }

    function test_processTriggeredExit_doubleReporting() public {
        bytes memory publicKey = randomBytes(48);
        uint256 initialPaidFee = 0.1 ether;
        uint256 newPaidFee = 0.2 ether;
        uint256 exitType = exitPenalties.VOLUNTARY_EXIT_TYPE_ID() + 1;

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(
            noId,
            publicKey,
            initialPaidFee,
            exitType
        );

        vm.recordLogs();

        vm.prank(address(csm));
        exitPenalties.processTriggeredExit(
            noId,
            publicKey,
            newPaidFee,
            exitType
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
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
        exitPenalties.processTriggeredExit(noId, publicKey, paidFee, exitType);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
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
        vm.expectRevert(ICSExitPenalties.SenderIsNotModule.selector);
        exitPenalties.processTriggeredExit(noId, publicKey, paidFee, exitType);
    }
}

contract CSExitPenaltiesTestProcessStrikesReport is CSExitPenaltiesTestBase {
    function test_processStrikesReport() public {
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getBadPerformancePenalty(0);

        vm.expectEmit(address(exitPenalties));
        emit ICSExitPenalties.StrikesPenaltyProcessed(noId, publicKey, penalty);
        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(noId, publicKey);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(exitPenaltyInfo.strikesPenalty.value, penalty);
    }

    function test_processStrikesReport_doubleReporting() public {
        bytes memory publicKey = randomBytes(48);
        uint256 penalty = parametersRegistry.getBadPerformancePenalty(0);

        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(noId, publicKey);

        parametersRegistry.setBadPerformancePenalty(0, penalty + 1);

        vm.recordLogs();
        vm.prank(address(strikes));
        exitPenalties.processStrikesReport(noId, publicKey);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties
            .getExitPenaltyInfo(noId, publicKey);
        assertEq(
            exitPenaltyInfo.strikesPenalty.value,
            penalty,
            "penalty should not be updated"
        );
    }

    function test_processStrikesReport_revertWhen_SenderIsNotStrikes() public {
        bytes memory publicKey = randomBytes(48);
        vm.prank(stranger);
        vm.expectRevert(ICSExitPenalties.SenderIsNotStrikes.selector);
        exitPenalties.processStrikesReport(noId, publicKey);
    }
}

contract CSExitPenaltiesTestIsValidatorExitDelayPenaltyApplicable is
    CSExitPenaltiesTestBase
{
    function test_isValidatorExitDelayPenaltyApplicable_notDelayedYet() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId);
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            noId,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable, "Penalty should not be applicable yet");
    }

    function test_isValidatorExitDelayPenaltyApplicable_delayed() public {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            noId,
            publicKey,
            eligibleToExit
        );
        assertTrue(applicable, "Penalty should be applicable");
    }

    function test_isValidatorExitDelayPenaltyApplicable_alreadyReported()
        public
    {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(address(csm));
        exitPenalties.processExitDelayReport(noId, publicKey, eligibleToExit);

        vm.prank(address(csm));
        bool applicable = exitPenalties.isValidatorExitDelayPenaltyApplicable(
            noId,
            publicKey,
            eligibleToExit
        );
        assertFalse(applicable, "Penalty should not be applicable anymore");
    }

    function test_isValidatorExitDelayPenaltyApplicable_revertWhen_SenderIsNotModule()
        public
    {
        uint256 eligibleToExit = csm.exitDeadlineThreshold(noId) + 1;
        bytes memory publicKey = randomBytes(48);

        vm.prank(stranger);
        vm.expectRevert(ICSExitPenalties.SenderIsNotModule.selector);
        exitPenalties.isValidatorExitDelayPenaltyApplicable(
            noId,
            publicKey,
            eligibleToExit
        );
    }
}
