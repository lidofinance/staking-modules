// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

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
        parametersRegistry = ParametersRegistryMock(address(csm.PARAMETERS_REGISTRY()));
        accounting = CSMMock(csm).accounting();
        strikes = new ValidatorStrikesMock();
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");

        exitPenalties = new ExitPenalties(address(csm), address(strikes));
        _enableInitializers(address(exitPenalties));
    }
}

contract ExitPenaltiesTestMisc is ExitPenaltiesTestBase {
    function test_constructor() public {
        exitPenalties = new ExitPenalties(address(csm), address(strikes));
        assertEq(address(exitPenalties.MODULE()), address(csm));
        assertEq(address(exitPenalties.PARAMETERS_REGISTRY()), address(parametersRegistry));
        assertEq(address(exitPenalties.ACCOUNTING()), address(accounting));
        assertEq(address(exitPenalties.STRIKES()), address(strikes));
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IExitPenalties.ZeroModuleAddress.selector);
        new ExitPenalties(address(0), address(strikes));
    }

    function test_constructor_RevertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(IExitPenalties.ZeroStrikesAddress.selector);
        new ExitPenalties(address(csm), address(0));
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

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties.getExitPenaltyInfo(NO_ID, publicKey);
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

        ExitPenaltyInfo memory exitPenaltyInfo = exitPenalties.getExitPenaltyInfo(NO_ID, publicKey);
        assertEq(exitPenaltyInfo.strikesPenalty.value, penalty, "penalty should not be updated");
    }

    function test_processStrikesReport_revertWhen_SenderIsNotStrikes() public {
        bytes memory publicKey = randomBytes(48);
        vm.prank(stranger);
        vm.expectRevert(IExitPenalties.SenderIsNotStrikes.selector);
        exitPenalties.processStrikesReport(NO_ID, publicKey);
    }
}
