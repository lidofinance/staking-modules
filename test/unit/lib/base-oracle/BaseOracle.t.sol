// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test, Vm } from "forge-std/Test.sol";
import { BaseOracle } from "src/lib/base-oracle/BaseOracle.sol";
import { UnstructuredStorage } from "src/lib/UnstructuredStorage.sol";
import { Utilities, hasLog } from "../../../helpers/Utilities.sol";
import { MockConsensusContract } from "../../../helpers/mocks/ConsensusContractMock.sol";

struct ConsensusReport {
    bytes32 hash;
    uint64 refSlot;
    uint64 processingDeadlineTime;
}

contract BaseOracleTest is Test, Utilities {
    using { hasLog } for Vm.Log[];

    BaseOracleImpl oracle;
    MockConsensusContract consensus;
    address admin;
    address stranger;
    address manager;
    address member;
    address notMember;
    uint256 initialRefSlot;
    uint256 deadline;

    uint256 constant CONSENSUS_VERSION = 1;
    uint256 constant EPOCHS_PER_FRAME = 225;
    uint256 constant GENESIS_TIME = 100;
    uint256 constant INITIAL_EPOCH = 1;
    uint256 constant INITIAL_FAST_LANE_LENGTH_SLOTS = 0;
    uint256 constant SECONDS_PER_SLOT = 12;
    uint256 constant SLOTS_PER_EPOCH = 32;
    uint256 constant SECONDS_PER_EPOCH = SECONDS_PER_SLOT * 32;
    uint256 constant SLOTS_PER_FRAME = EPOCHS_PER_FRAME * 32;

    function setUp() public {
        admin = nextAddress("ADMIN");
        stranger = nextAddress("STRANGER");
        manager = nextAddress("MANAGER");
        member = nextAddress("MEMBER");
        notMember = nextAddress("NOT_MEMBER");

        vm.warp(GENESIS_TIME + SECONDS_PER_EPOCH);
        oracle = new BaseOracleImpl(SECONDS_PER_SLOT, GENESIS_TIME, admin);
        consensus = new MockConsensusContract(
            SECONDS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            INITIAL_EPOCH,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            member
        );
        oracle.initialize(address(consensus), CONSENSUS_VERSION, 0);

        vm.startPrank(admin);
        oracle.grantRole(oracle.MANAGE_CONSENSUS_CONTRACT_ROLE(), admin);
        oracle.grantRole(oracle.MANAGE_CONSENSUS_VERSION_ROLE(), admin);
        vm.stopPrank();
        // forge-lint: disable-next-item(divide-before-multiply) this is intentional here
        initialRefSlot =
            ((oracle.getTime() - GENESIS_TIME) /
                SECONDS_PER_SLOT /
                SLOTS_PER_EPOCH) *
            SLOTS_PER_EPOCH;
        deadline =
            GENESIS_TIME +
            (initialRefSlot + SLOTS_PER_FRAME) *
            SECONDS_PER_SLOT;
    }

    function test_constructor_RevertsWhenSecondsPerSlotIsZero() public {
        vm.expectRevert(BaseOracle.SecondsPerSlotCannotBeZero.selector);
        new BaseOracleImpl(0, GENESIS_TIME, admin);
    }

    function test_setConsensusContract_RevertsIfCallerIsUnauthorized() public {
        bytes32 role = oracle.MANAGE_CONSENSUS_CONTRACT_ROLE();

        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        oracle.setConsensusContract(stranger);
    }

    function test_setConsensusContract_UpdatesWithRole() public {
        MockConsensusContract newConsensus = new MockConsensusContract(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            INITIAL_EPOCH,
            INITIAL_FAST_LANE_LENGTH_SLOTS,
            admin
        );

        bytes32 role = oracle.MANAGE_CONSENSUS_CONTRACT_ROLE();
        vm.prank(admin);
        oracle.grantRole(role, manager);

        vm.prank(manager);
        oracle.setConsensusContract(address(newConsensus));
        assertEq(oracle.getConsensusContract(), address(newConsensus));
    }

    function test_setConsensusVersion_RevertsIfCallerIsUnauthorized() public {
        bytes32 role = oracle.MANAGE_CONSENSUS_VERSION_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        oracle.setConsensusVersion(1);
    }

    function test_setConsensusVersion_UpdatesWithRole() public {
        bytes32 role = oracle.MANAGE_CONSENSUS_VERSION_ROLE();
        vm.prank(admin);
        oracle.grantRole(role, manager);

        vm.prank(manager);
        oracle.setConsensusVersion(3);
        assertEq(oracle.getConsensusVersion(), 3);
    }

    function test_submitConsensusReport_RevertsIfSenderIsNotConsensusContract()
        public
    {
        uint256 refSlot = oracle.getTime();
        vm.prank(stranger);
        vm.expectRevert(BaseOracle.SenderIsNotTheConsensusContract.selector);
        oracle.submitConsensusReport(keccak256("HASH_1"), refSlot, refSlot);
    }

    function test_submitConsensusReport_SubmitsFromConsensusContract() public {
        uint256 refSlot = oracle.getTime();
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            refSlot,
            refSlot + SLOTS_PER_FRAME
        );
        assertEq(oracle.getConsensusReportLastCall().callCount, 1);
    }

    function test_discardConsensusReport_RevertsIfSenderIsNotConsensusContract()
        public
    {
        uint256 refSlot = oracle.getTime();
        vm.prank(stranger);
        vm.expectRevert(BaseOracle.SenderIsNotTheConsensusContract.selector);
        oracle.discardConsensusReport(refSlot);
    }

    function test_discardConsensusReport_DiscardsFromConsensusContract()
        public
    {
        uint256 refSlot = oracle.getTime();
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            refSlot,
            refSlot + SLOTS_PER_FRAME
        );
        assertEq(oracle.getConsensusReportLastCall().callCount, 1);
        vm.prank(address(consensus));
        oracle.discardConsensusReport(refSlot);
    }

    // consensus tests

    function test_setConsensusContract_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(BaseOracle.AddressCannotBeZero.selector);
        oracle.setConsensusContract(address(0));
    }

    function test_setConsensusContract_RevertsOnSameContract() public {
        vm.prank(admin);
        vm.expectRevert(BaseOracle.AddressCannotBeSame.selector);
        oracle.setConsensusContract(address(consensus));
    }

    function test_setConsensusContract_RevertsOnInvalidContract() public {
        vm.prank(admin);
        vm.expectRevert();
        oracle.setConsensusContract(member);
    }

    function test_setConsensusContract_RevertsOnMismatchedConfig() public {
        MockConsensusContract wrongConsensus = new MockConsensusContract(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT + 1,
            GENESIS_TIME + 1,
            EPOCHS_PER_FRAME,
            1,
            0,
            admin
        );

        vm.prank(admin);
        vm.expectRevert(BaseOracle.UnexpectedChainConfig.selector);
        oracle.setConsensusContract(address(wrongConsensus));
    }

    function test_setConsensusContract_RevertsOnInitialRefSlotBehindProcessing()
        public
    {
        uint256 processingRefSlot = 100;

        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            processingRefSlot,
            deadline
        );
        oracle.startProcessing();

        MockConsensusContract wrongConsensus = new MockConsensusContract(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            1,
            0,
            admin
        );

        wrongConsensus.setInitialRefSlot(processingRefSlot - 1);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.InitialRefSlotCannotBeLessThanProcessingOne.selector,
                processingRefSlot - 1,
                processingRefSlot
            )
        );
        oracle.setConsensusContract(address(wrongConsensus));
    }

    function test_setConsensusContract_UpdatesConsensusContract() public {
        MockConsensusContract newConsensus = new MockConsensusContract(
            SLOTS_PER_EPOCH,
            SECONDS_PER_SLOT,
            GENESIS_TIME,
            EPOCHS_PER_FRAME,
            1,
            0,
            admin
        );

        newConsensus.setInitialRefSlot(initialRefSlot);

        vm.prank(admin);
        vm.expectEmit(address(oracle));
        emit BaseOracle.ConsensusHashContractSet(
            address(newConsensus),
            address(consensus)
        );
        oracle.setConsensusContract(address(newConsensus));

        assertEq(oracle.getConsensusContract(), address(newConsensus));
    }

    function test_setConsensusVersion_RevertsOnSameVersion() public {
        vm.prank(admin);
        vm.expectRevert(BaseOracle.VersionCannotBeSame.selector);
        oracle.setConsensusVersion(CONSENSUS_VERSION);
    }

    function test_setConsensusVersion_RevertsIfZero() public {
        vm.prank(admin);
        vm.expectRevert(BaseOracle.VersionCannotBeZero.selector);
        oracle.setConsensusVersion(0);
    }

    function test_setConsensusVersion_UpdatesConsensusVersion() public {
        vm.prank(admin);
        vm.expectEmit(address(oracle));
        emit BaseOracle.ConsensusVersionSet(3, CONSENSUS_VERSION);
        oracle.setConsensusVersion(3);

        assertEq(oracle.getConsensusVersion(), 3);
    }

    function test_checkConsensusData_RevertsOnMismatchedSlot() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        uint256 badSlot = initialRefSlot + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.UnexpectedRefSlot.selector,
                initialRefSlot,
                badSlot
            )
        );
        oracle.checkConsensusData(
            badSlot,
            CONSENSUS_VERSION,
            keccak256("HASH_1")
        );
    }

    function test_checkConsensusData_RevertsOnMismatchedConsensusVersion()
        public
    {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        uint256 badVersion = CONSENSUS_VERSION + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.UnexpectedConsensusVersion.selector,
                CONSENSUS_VERSION,
                badVersion
            )
        );
        oracle.checkConsensusData(
            initialRefSlot,
            badVersion,
            keccak256("HASH_1")
        );
    }

    function test_checkConsensusData_RevertsOnMismatchedHash() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.UnexpectedDataHash.selector,
                keccak256("HASH_1"),
                keccak256("HASH_2")
            )
        );
        oracle.checkConsensusData(
            initialRefSlot,
            CONSENSUS_VERSION,
            keccak256("HASH_2")
        );
    }

    function test_checkConsensusData_ChecksCorrectDataWithoutErrors() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        oracle.checkConsensusData(
            initialRefSlot,
            CONSENSUS_VERSION,
            keccak256("HASH_1")
        );
    }

    function test_checkProcessingDeadline_RevertsIfDeadlineMissed() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.warp(deadline + 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.ProcessingDeadlineMissed.selector,
                deadline
            )
        );
        oracle.checkProcessingDeadline();
    }

    function test_isConsensusMember_ReturnsFalseOnNonMember() public view {
        bool r = oracle.isConsensusMember(notMember);
        assertFalse(r);
    }

    function test_isConsensusMember_ReturnsTrueOnMember() public view {
        bool r = oracle.isConsensusMember(member);
        assertTrue(r);
    }

    // consensus report

    function test_getConsensusReport_ReturnsEmptyState() public view {
        (
            bytes32 hash,
            uint256 refSlot,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();
        assertEq(hash, bytes32(0));
        assertEq(refSlot, 0);
        assertEq(processingDeadlineTime, 0);
        assertFalse(processingStarted);
    }

    function test_getConsensusReport_ReturnsInitialReport() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        (
            bytes32 hash,
            uint256 refSlot,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();
        assertEq(hash, keccak256("HASH_1"));
        assertEq(refSlot, initialRefSlot);
        assertEq(processingDeadlineTime, deadline);
        assertFalse(processingStarted);
    }

    function test_getConsensusReport_ReturnsNextReports() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 nextRefSlotDeadline = deadline + SECONDS_PER_EPOCH;
        vm.prank(address(consensus));
        vm.expectEmit(address(oracle));
        emit BaseOracle.WarnProcessingMissed(initialRefSlot);
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );

        (
            bytes32 hash,
            uint256 refSlot,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();
        assertEq(hash, keccak256("HASH_2"));
        assertEq(refSlot, nextRefSlot);
        assertEq(processingDeadlineTime, nextRefSlotDeadline);
        assertFalse(processingStarted);

        vm.recordLogs();
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_3"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], BaseOracle.ReportSubmitted.selector);
        (hash, refSlot, processingDeadlineTime, processingStarted) = oracle
            .getConsensusReport();
        assertEq(hash, keccak256("HASH_3"));
        assertEq(refSlot, nextRefSlot);
        assertEq(processingDeadlineTime, nextRefSlotDeadline);
        assertFalse(processingStarted);
    }

    function test_getConsensusReport_ReturnsReportWhileProcessing() public {
        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 nextRefSlotDeadline = deadline + SECONDS_PER_EPOCH;

        vm.startPrank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        oracle.submitConsensusReport(
            keccak256("HASH_3"),
            nextRefSlot,
            nextRefSlotDeadline
        );

        oracle.startProcessing();

        (
            bytes32 hash,
            uint256 refSlot,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();
        assertEq(hash, keccak256("HASH_3"));
        assertEq(refSlot, nextRefSlot);
        assertEq(processingDeadlineTime, nextRefSlotDeadline);
        assertTrue(processingStarted);
    }

    function test_startProcessing_RevertsOnEmptyState() public {
        vm.expectRevert(BaseOracle.NoConsensusReportToProcess.selector);
        oracle.startProcessing();
    }

    function test_startProcessing_RevertsOnZeroReportAfterDiscarded() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.prank(address(consensus));
        oracle.discardConsensusReport(initialRefSlot);

        vm.expectRevert(BaseOracle.NoConsensusReportToProcess.selector);
        oracle.startProcessing();
    }

    function test_startProcessing_RevertsOnProcessingSameSlotAgain() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        oracle.startProcessing();

        vm.expectRevert(BaseOracle.RefSlotAlreadyProcessing.selector);
        oracle.startProcessing();
    }

    function test_startProcessing_RevertsOnMissedDeadline() public {
        uint256 refSlot2 = initialRefSlot + 2 * SLOTS_PER_EPOCH;
        uint256 refSlot2Deadline = deadline + 2 * SECONDS_PER_EPOCH;
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_3"),
            refSlot2,
            refSlot2Deadline
        );

        vm.warp(refSlot2Deadline + SECONDS_PER_SLOT * 10);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.ProcessingDeadlineMissed.selector,
                refSlot2Deadline
            )
        );
        oracle.startProcessing();
    }

    function test_startProcessing_StartsReportProcessing() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.expectEmit(address(oracle));
        emit BaseOracle.ProcessingStarted(initialRefSlot, keccak256("HASH_1"));
        vm.expectEmit(address(oracle));
        emit BaseOracleImpl.MockStartProcessingResult(0);
        oracle.startProcessing();
    }

    function test_startProcessing_AdvancesStateOnNextReportProcessing() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        oracle.startProcessing();
        uint256 refSlot1 = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 refSlot1Deadline = deadline + SECONDS_PER_EPOCH;

        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            refSlot1,
            refSlot1Deadline
        );

        vm.expectEmit(address(oracle));
        emit BaseOracle.ProcessingStarted(refSlot1, keccak256("HASH_2"));
        vm.expectEmit(address(oracle));
        emit BaseOracleImpl.MockStartProcessingResult(initialRefSlot);
        oracle.startProcessing();
        assertEq(oracle.getLastProcessingRefSlot(), refSlot1);
    }

    function test_submitConsensusReport_RevertsIfDeadlinePassed() public {
        vm.warp(deadline + 1);
        vm.prank(address(consensus));
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.ProcessingDeadlineMissed.selector,
                deadline
            )
        );
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
    }

    function test_submitConsensusReport_RevertsIfNotCalledByConsensusContract()
        public
    {
        vm.expectRevert(BaseOracle.SenderIsNotTheConsensusContract.selector);
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
    }

    function test_submitConsensusReport_RevertsIfZeroHash() public {
        vm.prank(address(consensus));
        vm.expectRevert(BaseOracle.HashCannotBeZero.selector);
        oracle.submitConsensusReport(bytes32(0), initialRefSlot, deadline);
    }

    function test_submitConsensusReport_RevertsIfSubmittingOlderReport()
        public
    {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        uint256 badSlot = initialRefSlot - 1;
        vm.prank(address(consensus));
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.RefSlotCannotDecrease.selector,
                badSlot,
                initialRefSlot
            )
        );
        oracle.submitConsensusReport(keccak256("HASH_1"), badSlot, deadline);
    }

    function test_submitConsensusReport_RevertsIfResubmitAlreadyProcessingReport()
        public
    {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        oracle.startProcessing();

        vm.prank(address(consensus));
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.RefSlotMustBeGreaterThanProcessingOne.selector,
                initialRefSlot,
                initialRefSlot
            )
        );
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
    }

    function test_submitConsensusReport_SubmitsInitialReport() public {
        uint256 beforeCallCount = oracle.getConsensusReportLastCall().callCount;
        assertEq(beforeCallCount, 0);

        vm.prank(address(consensus));
        vm.expectEmit(address(oracle));
        emit BaseOracle.ReportSubmitted(
            initialRefSlot,
            keccak256("HASH_1"),
            deadline
        );
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        BaseOracleImpl.HandleConsensusReportLastCall memory lastCall = oracle
            .getConsensusReportLastCall();
        assertEq(lastCall.callCount, 1);
        assertEq(lastCall.report.hash, keccak256("HASH_1"));
        assertEq(lastCall.report.refSlot, initialRefSlot);
        assertEq(lastCall.report.processingDeadlineTime, deadline);
    }

    function test_submitConsensusReport_EmitsWarningEventOnNewerReport()
        public
    {
        uint256 secondRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 thirdRefSlot = secondRefSlot + SLOTS_PER_EPOCH;
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            secondRefSlot,
            deadline
        );

        vm.prank(address(consensus));
        vm.expectEmit(address(oracle));
        emit BaseOracle.WarnProcessingMissed(secondRefSlot);
        vm.expectEmit(address(oracle));
        emit BaseOracle.ReportSubmitted(
            thirdRefSlot,
            keccak256("HASH_1"),
            deadline
        );
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            thirdRefSlot,
            deadline
        );
        assertEq(oracle.getConsensusReportLastCall().callCount, 2);
    }

    function test_discardConsensusReport_RevertsIfSlotInvalid() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        uint256 badSlot = initialRefSlot - 1;

        vm.prank(address(consensus));
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseOracle.RefSlotCannotDecrease.selector,
                badSlot,
                initialRefSlot
            )
        );
        oracle.discardConsensusReport(badSlot);
    }

    function test_discardConsensusReport_RevertsIfProcessingStarted() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        oracle.startProcessing();

        vm.prank(address(consensus));
        vm.expectRevert(BaseOracle.RefSlotAlreadyProcessing.selector);
        oracle.discardConsensusReport(initialRefSlot);
    }

    function test_discardConsensusReport_DoesNotDiscardWhenNoReportExists()
        public
    {
        vm.prank(address(consensus));

        vm.recordLogs();
        oracle.discardConsensusReport(initialRefSlot);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_discardConsensusReport_DoesNotDiscardFutureReport() public {
        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        vm.prank(address(consensus));
        vm.recordLogs();
        oracle.discardConsensusReport(nextRefSlot);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_discardConsensusReport_DiscardsReport() public {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.prank(address(consensus));
        vm.expectEmit(address(oracle));
        emit BaseOracle.ReportDiscarded(initialRefSlot, keccak256("HASH_1"));
        oracle.discardConsensusReport(initialRefSlot);

        (bytes32 hash, , , ) = oracle.getConsensusReport();
        assertEq(hash, bytes32(0));
    }

    function test_discardConsensusReport_CallsHandleConsensusReportDiscarded()
        public
    {
        vm.prank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.prank(address(consensus));
        oracle.discardConsensusReport(initialRefSlot);

        (bytes32 hash, , ) = oracle.lastDiscardedReport();
        assertEq(hash, keccak256("HASH_1"));
    }

    function test_discardConsensusReport_AllowsResubmittingReport() public {
        vm.startPrank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            initialRefSlot,
            deadline
        );
        oracle.discardConsensusReport(initialRefSlot);

        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            initialRefSlot,
            deadline
        );
        (bytes32 hash, , , ) = oracle.getConsensusReport();
        assertEq(hash, keccak256("HASH_2"));
    }

    function test_discardConsensusReport_NoPrevReport() public {
        vm.startPrank(address(consensus));

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );

        oracle.discardConsensusReport(initialRefSlot);

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            initialRefSlot,
            deadline
        );
        entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );
    }

    function test_discardConsensusReport_PrevFrameProcessed() public {
        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 nextRefSlotDeadline = deadline + SECONDS_PER_EPOCH;
        // initial report
        vm.startPrank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        oracle.startProcessing();

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );

        oracle.discardConsensusReport(nextRefSlot);

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );
    }

    function test_discardConsensusReport_SkippedProcessing() public {
        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH * 2;
        uint256 nextRefSlotDeadline = deadline + SECONDS_PER_EPOCH * 2;
        // initial report
        vm.startPrank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );
        oracle.startProcessing();
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            initialRefSlot + SLOTS_PER_EPOCH,
            deadline + SECONDS_PER_EPOCH
        );

        vm.expectEmit(address(oracle));
        emit BaseOracle.WarnProcessingMissed(initialRefSlot + SLOTS_PER_EPOCH);
        oracle.submitConsensusReport(
            keccak256("HASH_3"),
            nextRefSlot,
            nextRefSlotDeadline
        );

        oracle.discardConsensusReport(nextRefSlot);

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_3"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );
    }

    function test_discardConsensusReport_NoPrevProcessing() public {
        uint256 nextRefSlot = initialRefSlot + SLOTS_PER_EPOCH;
        uint256 nextRefSlotDeadline = deadline + SECONDS_PER_EPOCH;
        // initial report
        vm.startPrank(address(consensus));
        oracle.submitConsensusReport(
            keccak256("HASH_1"),
            initialRefSlot,
            deadline
        );

        vm.expectEmit(address(oracle));
        emit BaseOracle.WarnProcessingMissed(initialRefSlot);
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );

        oracle.discardConsensusReport(nextRefSlot);

        vm.recordLogs();
        oracle.submitConsensusReport(
            keccak256("HASH_2"),
            nextRefSlot,
            nextRefSlotDeadline
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertFalse(
            entries.hasLog(BaseOracle.WarnProcessingMissed.selector),
            "Unexpected WarnProcessingMissed event was emitted"
        );
    }
}

contract BaseOracleImpl is BaseOracle {
    using UnstructuredStorage for bytes32;
    uint256 internal _time;

    event MockStartProcessingResult(uint256 prevProcessingRefSlot);

    struct HandleConsensusReportLastCall {
        ConsensusReport report;
        uint256 prevSubmittedRefSlot;
        uint256 prevProcessingRefSlot;
        uint256 callCount;
    }
    HandleConsensusReportLastCall internal _handleConsensusReportLastCall;
    ConsensusReport public lastDiscardedReport;

    constructor(
        uint256 secondsPerSlot,
        uint256 genesisTime,
        address admin
    ) BaseOracle(secondsPerSlot, genesisTime) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        CONTRACT_VERSION_POSITION.setStorageUint256(0);
        require(
            genesisTime <= block.timestamp,
            "GENESIS_TIME_CANNOT_BE_MORE_THAN_MOCK_TIME"
        );
    }

    function initialize(
        address consensusContract,
        uint256 consensusVersion,
        uint256 lastProcessingRefSlot
    ) external {
        _initialize(consensusContract, consensusVersion, lastProcessingRefSlot);
    }

    function getTime() external view returns (uint256) {
        return _getTime();
    }

    function _handleConsensusReport(
        ConsensusReport memory report,
        uint256 prevSubmittedRefSlot,
        uint256 prevProcessingRefSlot
    ) internal virtual override {
        _handleConsensusReportLastCall.report = report;
        _handleConsensusReportLastCall
            .prevSubmittedRefSlot = prevSubmittedRefSlot;
        _handleConsensusReportLastCall
            .prevProcessingRefSlot = prevProcessingRefSlot;
        ++_handleConsensusReportLastCall.callCount;
    }

    function _handleConsensusReportDiscarded(
        ConsensusReport memory report
    ) internal override {
        lastDiscardedReport = report;
        super._handleConsensusReportDiscarded(report);
    }

    function getConsensusReportLastCall()
        external
        view
        returns (HandleConsensusReportLastCall memory)
    {
        return _handleConsensusReportLastCall;
    }

    function startProcessing() external {
        uint256 _res = _startProcessing();
        emit MockStartProcessingResult(_res);
    }

    function isConsensusMember(address addr) external view returns (bool) {
        return _isConsensusMember(addr);
    }

    function checkConsensusData(
        uint256 refSlot,
        uint256 consensusVersion,
        bytes32 hash
    ) external view {
        _checkConsensusData(refSlot, consensusVersion, hash);
    }

    function checkProcessingDeadline() external view {
        _checkProcessingDeadline(
            _storageConsensusReport().value.processingDeadlineTime
        );
    }
}
