// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import "forge-std/Test.sol";
import "src/utils/TwoPhaseFrameConfigUpdate.sol";
import { ReportProcessorMock } from "../helpers/mocks/ReportProcessorMock.sol";
import { MockConsensusContract } from "../helpers/mocks/ConsensusContractMock.sol";

contract TwoPhaseFrameConfigUpdateTest is Test {
    TwoPhaseFrameConfigUpdate public updater;
    ReportProcessorMock public mockOracle;
    MockConsensusContract public mockConsensus;

    // Network constants
    uint256 constant SLOTS_PER_EPOCH = 32;
    uint256 constant SECONDS_PER_SLOT = 12;
    uint256 constant EPOCHS_PER_DAY = 225;
    uint256 constant DEFAULT_EPOCHS_PER_FRAME = 13 * EPOCHS_PER_DAY; // 13 days

    // Helper functions for calculating slots and epochs
    function dayToEpochs(uint256 dayCount) internal pure returns (uint256) {
        return dayCount * EPOCHS_PER_DAY;
    }

    function epochEndSlot(uint256 dayCount) internal pure returns (uint256) {
        // Last slot of the epoch at end of given day count
        // Each day = 225 epochs, each epoch = 32 slots
        // End of day N = slot (N * 225 * 32 - 1)
        return dayCount * EPOCHS_PER_DAY * SLOTS_PER_EPOCH - 1;
    }

    function calculateExpectedSlot(
        uint256 fromRefSlot,
        uint256 reportsToProcess,
        uint256 epochsPerFrame
    ) internal pure returns (uint256) {
        // Offset phase uses currentEpochsPerFrame (from consensus contract).
        // Restore phase uses offsetPhaseEpochsPerFrame for slot calculation.
        return
            fromRefSlot + (reportsToProcess * epochsPerFrame * SLOTS_PER_EPOCH);
    }

    function calculateDeadlineSlot(
        uint256 expectedSlot,
        uint256 epochsPerFrame
    ) internal pure returns (uint256) {
        return expectedSlot + (epochsPerFrame * SLOTS_PER_EPOCH);
    }

    function calculateExpirationSlot(
        uint256 expectedSlot,
        uint256 epochsPerFrame1,
        uint256 epochsPerFrame2
    ) internal pure returns (uint256) {
        uint256 minEpochs = epochsPerFrame1 < epochsPerFrame2
            ? epochsPerFrame1
            : epochsPerFrame2;
        return expectedSlot + (minEpochs * SLOTS_PER_EPOCH);
    }

    function setUp() public {
        address mockMember = address(0x1234);
        mockConsensus = new MockConsensusContract(
            SLOTS_PER_EPOCH, // slotsPerEpoch
            SECONDS_PER_SLOT, // secondsPerSlot
            0, // genesisTime
            DEFAULT_EPOCHS_PER_FRAME, // epochsPerFrame - 13 days (2925 epochs = 13 days)
            1, // initialEpoch
            0, // fastLaneLengthSlots
            mockMember
        );
        mockOracle = new ReportProcessorMock(1);
        mockOracle.setConsensusContract(address(mockConsensus));
    }

    function mockLastProcessingRefSlot(uint256 lastProcessingRefSlot) internal {
        mockOracle.setLastProcessingStartedRefSlot(lastProcessingRefSlot);
        mockConsensus.setCurrentFrame(
            0,
            lastProcessingRefSlot,
            lastProcessingRefSlot + 100
        );
    }

    function createUpdater(
        TwoPhaseFrameConfigUpdate.PhasesConfig memory phasesConfig
    ) internal {
        updater = new TwoPhaseFrameConfigUpdate(
            address(mockOracle),
            phasesConfig
        );
    }

    function createPhasesConfig(
        uint256 reportsToProcessBeforeOffsetPhase,
        uint256 reportsToProcessBeforeRestorePhase,
        uint256 daysPerFrame,
        uint256 fastLaneSlots
    ) internal pure returns (TwoPhaseFrameConfigUpdate.PhasesConfig memory) {
        return
            TwoPhaseFrameConfigUpdate.PhasesConfig({
                reportsToProcessBeforeOffsetPhase: reportsToProcessBeforeOffsetPhase,
                reportsToProcessBeforeRestorePhase: reportsToProcessBeforeRestorePhase,
                offsetPhaseEpochsPerFrame: dayToEpochs(daysPerFrame),
                restorePhaseFastLaneLengthSlots: fastLaneSlots
            });
    }

    function test_constructor_Success() public {
        uint256 offsetReportsToProcess = 1;
        uint256 offsetDaysPerFrame = 1;
        uint256 offsetFastLaneSlots = 64;

        uint256 restoreReportsToProcess = 2;

        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(
                offsetReportsToProcess,
                restoreReportsToProcess,
                offsetDaysPerFrame,
                offsetFastLaneSlots
            );

        uint256 fromRefSlot = epochEndSlot({ dayCount: 1 });

        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        assertEq(address(updater.ORACLE()), address(mockOracle));
        assertEq(address(updater.HASH_CONSENSUS()), address(mockConsensus));

        (uint256 offsetExpectedProcessingRefSlot, , , , ) = updater
            .offsetPhase();
        (uint256 restoreExpectedProcessingRefSlot, , , , ) = updater
            .restorePhase();

        // fromRefSlot(7199) + (1 report * 2925 epochs * 32 slots) = 7199 + 93600 = 100799
        assertEq(offsetExpectedProcessingRefSlot, 100799);

        // offsetSlot(100799) + (2 reports * 225 epochs * 32 slots) = 100799 + 14400 = 115199
        assertEq(restoreExpectedProcessingRefSlot, 115199);

        // Verify execution status
        (, , , , bool offsetPhaseExecuted) = updater.offsetPhase();
        (, , , , bool restorePhaseExecuted) = updater.restorePhase();
        assertFalse(offsetPhaseExecuted);
        assertFalse(restorePhaseExecuted);
    }

    function test_constructor_RevertWhen_ZeroOracleAddress() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64);

        vm.expectRevert(TwoPhaseFrameConfigUpdate.ZeroOracleAddress.selector);
        new TwoPhaseFrameConfigUpdate(address(0), phasesConfig);
    }

    function test_constructor_RevertWhen_ZeroReportsToProcessBeforeOffsetPhase()
        public
    {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(0, 2, 1, 64); // Zero reportsToProcess for offsetPhase

        uint256 testDay = 10;
        mockLastProcessingRefSlot(epochEndSlot(testDay));

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.ZeroReportsToEnableUpdate.selector
        );
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_RevertWhen_ZeroReportsToProcessBeforeRestorePhase()
        public
    {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 0, 1, 64); // Zero reportsToProcess for restorePhase

        uint256 testDay = 10;
        mockLastProcessingRefSlot(epochEndSlot(testDay));

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.ZeroReportsToEnableUpdate.selector
        );
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_RevertWhen_ZeroEpochsPerFrame() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 0, 64); // Zero epochsPerFrame for offsetPhase

        uint256 testDay = 10;
        mockLastProcessingRefSlot(epochEndSlot(testDay));

        phasesConfig.offsetPhaseEpochsPerFrame = 0;

        vm.expectRevert(TwoPhaseFrameConfigUpdate.ZeroEpochsPerFrame.selector);
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_RevertWhen_CurrentReportMainPhaseIsNotCompleted()
        public
    {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64);

        uint256 lastProcessingRefSlot = epochEndSlot(1);
        uint256 differentCurrentRefSlot = epochEndSlot(2);

        mockOracle.setLastProcessingStartedRefSlot(lastProcessingRefSlot);
        mockConsensus.setCurrentFrame(
            0,
            differentCurrentRefSlot,
            differentCurrentRefSlot + 100
        );

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate
                .CurrentReportMainPhaseIsNotCompleted
                .selector
        );
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_RevertWhen_FastLaneTooShort() public {
        mockLastProcessingRefSlot(epochEndSlot(1));

        // Fast lane too short (less than 2 epochs = 64 slots)
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 63); // 63 < 64 (2 * 32)

        vm.expectRevert(TwoPhaseFrameConfigUpdate.FastLaneTooShort.selector);
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);

        // Fast lane with exactly 1 epoch
        phasesConfig.restorePhaseFastLaneLengthSlots = 32; // 1 epoch = 32 slots
        vm.expectRevert(TwoPhaseFrameConfigUpdate.FastLaneTooShort.selector);
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);

        // Fast lane with 0 slots
        phasesConfig.restorePhaseFastLaneLengthSlots = 0;
        vm.expectRevert(TwoPhaseFrameConfigUpdate.FastLaneTooShort.selector);
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_RevertWhen_FastLanePeriodTooLong() public {
        mockLastProcessingRefSlot(epochEndSlot(1));

        // Restore phase fast lane longer than current frame
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(
                1,
                1,
                1,
                DEFAULT_EPOCHS_PER_FRAME * SLOTS_PER_EPOCH + 1
            );
        vm.expectRevert(
            TwoPhaseFrameConfigUpdate
                .FastLanePeriodCannotBeLongerThanFrame
                .selector
        );
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_constructor_DefaultsRestorePhaseConfig() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 3, 2, 64); // only reportsToProcess provided

        uint256 fromRefSlot = epochEndSlot({ dayCount: 1 });
        mockLastProcessingRefSlot(fromRefSlot);

        createUpdater(phasesConfig);

        (, uint256 currentEpochsPerFrame, ) = mockConsensus.getFrameConfig();
        (
            uint256 restoreExpectedProcessingRefSlot,
            uint256 restoreExpirationSlot,
            uint256 restorePhaseEpochsPerFrame,
            uint256 restorePhaseFastLaneSlots,
            bool restorePhaseExecuted
        ) = updater.restorePhase();

        // offsetExpected = fromRef + 1 report * currentEpochsPerFrame * slotsPerEpoch
        uint256 offsetExpectedProcessingRefSlot = fromRefSlot +
            (phasesConfig.reportsToProcessBeforeOffsetPhase *
                DEFAULT_EPOCHS_PER_FRAME *
                SLOTS_PER_EPOCH);

        // restorePhase expected uses offsetPhase frame length
        uint256 expectedRestorePhaseProcessingRefSlot = offsetExpectedProcessingRefSlot +
                (phasesConfig.reportsToProcessBeforeRestorePhase *
                    phasesConfig.offsetPhaseEpochsPerFrame *
                    SLOTS_PER_EPOCH);
        assertEq(
            restoreExpectedProcessingRefSlot,
            expectedRestorePhaseProcessingRefSlot,
            "restorePhase expected ref slot"
        );

        // Defaults: epochsPerFrame -> currentEpochsPerFrame, fastLane -> offsetPhase fast lane
        assertEq(
            restorePhaseEpochsPerFrame,
            currentEpochsPerFrame,
            "restorePhase epochs per frame defaulted to current"
        );
        assertEq(
            restorePhaseFastLaneSlots,
            phasesConfig.restorePhaseFastLaneLengthSlots,
            "restorePhase fast lane defaulted to offsetPhase"
        );

        // Expiration uses min(offsetPhase epochs, restorePhase epochs)
        uint256 minEpochs = currentEpochsPerFrame <
            phasesConfig.offsetPhaseEpochsPerFrame
            ? currentEpochsPerFrame
            : phasesConfig.offsetPhaseEpochsPerFrame;
        uint256 expectedRestorePhaseExpiration = expectedRestorePhaseProcessingRefSlot +
                (minEpochs * SLOTS_PER_EPOCH);
        assertEq(restoreExpirationSlot, expectedRestorePhaseExpiration);

        assertFalse(restorePhaseExecuted, "restorePhase not executed");
    }

    function test_constructor_RevertWhen_OffsetPhaseAlreadyExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // 1 report, 1 day, 10 fast lane slots

        uint256 startingDay = 20;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);

        uint256 offsetExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phasesConfig.reportsToProcessBeforeOffsetPhase,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        uint256 offsetDeadlineSlot = calculateExpirationSlot(
            offsetExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME,
            dayToEpochs(1)
        );

        // Try to deploy contract after offset phase deadline
        vm.warp((offsetDeadlineSlot + 1) * SECONDS_PER_SLOT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                offsetDeadlineSlot + 1,
                offsetDeadlineSlot
            )
        );
        new TwoPhaseFrameConfigUpdate(address(mockOracle), phasesConfig);
    }

    function test_executeOffsetPhase_Success() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // 1 report, 1 day, 10 fast lane slots, restorePhase defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        // Calculate expected offset phase slot
        uint256 offsetExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phasesConfig.reportsToProcessBeforeOffsetPhase,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);

        assertTrue(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());

        vm.expectEmit(address(updater));
        emit TwoPhaseFrameConfigUpdate.OffsetPhaseExecuted();
        updater.executeOffsetPhase();

        (, , , , bool offsetPhaseExecuted) = updater.offsetPhase();
        (, , , , bool restorePhaseExecuted) = updater.restorePhase();
        assertTrue(offsetPhaseExecuted);
        assertFalse(restorePhaseExecuted);
        assertFalse(updater.isReadyForOffsetPhase());
    }

    function test_executeOffsetPhase_RevertWhen_UnexpectedLastProcessingRefSlot()
        public
    {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // 1 report, 1 day, 10 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 expectedOffsetPhaseSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phasesConfig.reportsToProcessBeforeOffsetPhase,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        uint256 wrongSlot = 7000;
        mockOracle.setLastProcessingStartedRefSlot(wrongSlot);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate
                    .UnexpectedLastProcessingRefSlot
                    .selector,
                wrongSlot,
                expectedOffsetPhaseSlot
            )
        );
        updater.executeOffsetPhase();
    }

    function test_executeOffsetPhase_RevertWhen_AlreadyExecuted() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // 1 report, 1 day, 10 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 offsetExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phasesConfig.reportsToProcessBeforeOffsetPhase,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.PhaseAlreadyExecuted.selector
        );
        updater.executeOffsetPhase();
    }

    function test_executeOffsetPhase_RevertWhen_DeadlineExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // 1 report, 1 day, 10 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 offsetExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phasesConfig.reportsToProcessBeforeOffsetPhase,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);

        uint256 deadlineSlot = calculateExpirationSlot(
            offsetExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME,
            phasesConfig.offsetPhaseEpochsPerFrame
        );
        vm.warp((deadlineSlot + 1) * SECONDS_PER_SLOT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                (deadlineSlot + 1),
                deadlineSlot
            )
        );
        updater.executeOffsetPhase();
    }

    function test_executeRestorePhase_Success() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // defaults: current frame & offsetPhase fast lane

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        // Grant role to test renunciation
        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        // Execute Offset phase
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        // Execute Restore phase
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);

        assertTrue(updater.isReadyForRestorePhase());
        vm.expectEmit(address(updater));
        emit TwoPhaseFrameConfigUpdate.RestorePhaseExecuted();
        updater.executeRestorePhase();

        (, , , , bool offsetPhaseExecuted) = updater.offsetPhase();
        (, , , , bool restorePhaseExecuted) = updater.restorePhase();
        assertTrue(offsetPhaseExecuted);
        assertTrue(restorePhaseExecuted);

        assertEq(
            mockConsensus.lastSetEpochsPerFrame(),
            DEFAULT_EPOCHS_PER_FRAME
        );
        assertEq(mockConsensus.lastSetFastLaneLengthSlots(), 64);

        // Verify role was renounced
        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );

        assertFalse(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());
    }

    function test_executeRestorePhase_RevertWhen_WithoutOffsetPhase() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        // Try to execute restore phase without executing offset phase
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.OffsetPhaseNotExecuted.selector
        );
        updater.executeRestorePhase();
    }

    function test_executeRestorePhase_RevertWhen_UnexpectedLastProcessingRefSlot()
        public
    {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 wrongSlot = 16000; // Some arbitrary wrong slot
        mockOracle.setLastProcessingStartedRefSlot(wrongSlot);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate
                    .UnexpectedLastProcessingRefSlot
                    .selector,
                wrongSlot,
                restoreExpectedSlot
            )
        );
        updater.executeRestorePhase();
    }

    function test_executeRestorePhase_RevertWhen_AlreadyExecuted() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);
        updater.executeRestorePhase();

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.PhaseAlreadyExecuted.selector
        );
        updater.executeRestorePhase();
    }

    function test_executeRestorePhase_RevertWhen_WithDeadlineExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);

        // Calculate deadline: expected slot + min frame duration
        uint256 deadlineSlot = calculateExpirationSlot(
            restoreExpectedSlot,
            dayToEpochs(1), // offsetPhase epochs
            dayToEpochs(2) // restorePhase epochs
        );
        uint256 deadlineTimestamp = deadlineSlot * SECONDS_PER_SLOT;
        vm.warp(deadlineTimestamp);

        uint256 currentSlot = block.timestamp / SECONDS_PER_SLOT;
        (, uint256 restoreExpirationSlot, , , ) = updater.restorePhase();

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                currentSlot,
                restoreExpirationSlot
            )
        );
        updater.executeRestorePhase();
    }

    function test_renounceRoleWhenExpired_WhenOffsetPhaseExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );
        assertTrue(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );

        // Calculate when offset phase expires
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 offsetDeadlineSlot = calculateExpirationSlot(
            offsetExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME,
            dayToEpochs(1)
        );
        vm.warp(offsetDeadlineSlot * SECONDS_PER_SLOT);

        (bool offsetExpired, ) = updater.getExpirationStatus();
        assertTrue(offsetExpired);

        updater.renounceRoleWhenExpired();

        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );
    }

    function test_renounceRoleWhenExpired_WhenRestorePhaseExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 30;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        // Execute offset phase
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        // Calculate when restore phase expires and set time past that
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 restoreDeadlineSlot = calculateExpirationSlot(
            restoreExpectedSlot,
            dayToEpochs(1), // offsetPhase epochs
            dayToEpochs(2) // restorePhase epochs
        );
        vm.warp(restoreDeadlineSlot * SECONDS_PER_SLOT);

        (, bool restoreExpired) = updater.getExpirationStatus();
        assertTrue(restoreExpired);

        updater.renounceRoleWhenExpired();

        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );
    }

    function test_renounceRoleWhenExpired_WhenNoPhasesExpired() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 20;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        (bool offsetExpired, bool restoreExpired) = updater
            .getExpirationStatus();
        assertFalse(offsetExpired);
        assertFalse(restoreExpired);

        vm.expectRevert(TwoPhaseFrameConfigUpdate.NoneOfPhasesExpired.selector);
        updater.renounceRoleWhenExpired();
    }

    function test_phaseStatesInitialized() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        (
            uint256 offsetExpectedProcessingRefSlot,
            ,
            uint256 offsetEpochsPerFrame,
            uint256 offsetFastLaneLengthSlots,
            bool offsetExecuted
        ) = updater.offsetPhase();
        (
            uint256 restoreExpectedProcessingRefSlot,
            ,
            uint256 restoreEpochsPerFrame,
            uint256 restoreFastLaneLengthSlots,
            bool restoreExecuted
        ) = updater.restorePhase();

        uint256 expectedOffsetPhaseSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 expectedRestorePhaseSlot = calculateExpectedSlot(
            expectedOffsetPhaseSlot,
            2,
            EPOCHS_PER_DAY
        );

        assertEq(offsetExpectedProcessingRefSlot, expectedOffsetPhaseSlot);
        assertEq(offsetEpochsPerFrame, EPOCHS_PER_DAY); // offsetPhase config uses 1 day (225 epochs)
        assertEq(offsetFastLaneLengthSlots, 0);
        assertFalse(offsetExecuted);

        assertEq(restoreExpectedProcessingRefSlot, expectedRestorePhaseSlot);
        assertEq(restoreEpochsPerFrame, DEFAULT_EPOCHS_PER_FRAME);
        assertEq(
            restoreFastLaneLengthSlots,
            phasesConfig.restorePhaseFastLaneLengthSlots
        );
        assertFalse(restoreExecuted);
    }

    function test_readinessStates() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        // Initial state - not ready
        assertFalse(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());

        // Ready for offset phase
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        assertTrue(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());

        // Execute offset phase
        updater.executeOffsetPhase();
        assertFalse(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());

        // Ready for restore phase
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);
        assertFalse(updater.isReadyForOffsetPhase());
        assertTrue(updater.isReadyForRestorePhase());

        // Execute restore phase
        updater.executeRestorePhase();
        assertFalse(updater.isReadyForOffsetPhase());
        assertFalse(updater.isReadyForRestorePhase());
    }

    function test_getExpirationStatus() public {
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 2, 1, 64); // restorePhase uses defaults

        uint256 startingDay = 1; // Use smaller day to avoid overlaps with large DEFAULT_EPOCHS_PER_FRAME
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        // Initially neither expired
        (bool offsetExpired, bool restoreExpired) = updater
            .getExpirationStatus();
        assertFalse(offsetExpired);
        assertFalse(restoreExpired);

        // Calculate phase deadlines
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 offsetDeadlineSlot = calculateExpirationSlot(
            offsetExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME,
            dayToEpochs(1)
        );

        // Past offset phase deadline
        vm.warp(offsetDeadlineSlot * SECONDS_PER_SLOT);
        (offsetExpired, restoreExpired) = updater.getExpirationStatus();
        assertTrue(offsetExpired);

        // Execute offset phase (reset time first to before any deadlines)
        uint256 safeTime = offsetExpectedSlot * SECONDS_PER_SLOT;
        vm.warp(safeTime);
        mockOracle.setLastProcessingStartedRefSlot(offsetExpectedSlot);
        updater.executeOffsetPhase();

        // Calculate restore phase deadline
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 restoreDeadlineSlot = calculateExpirationSlot(
            restoreExpectedSlot,
            dayToEpochs(1), // offsetPhase epochs
            dayToEpochs(2) // restorePhase epochs
        );

        // Test restore phase expiration independently
        vm.warp(restoreDeadlineSlot * SECONDS_PER_SLOT);
        (offsetExpired, restoreExpired) = updater.getExpirationStatus();
        assertFalse(offsetExpired); // Offset phase executed, so not expired
        assertTrue(restoreExpired);

        // Execute restore phase (reset time first)
        vm.warp(restoreExpectedSlot * SECONDS_PER_SLOT);
        mockOracle.setLastProcessingStartedRefSlot(restoreExpectedSlot);
        updater.executeRestorePhase();

        // Neither expired (both executed)
        vm.warp(restoreDeadlineSlot * SECONDS_PER_SLOT);
        (offsetExpired, restoreExpired) = updater.getExpirationStatus();
        assertFalse(offsetExpired);
        assertFalse(restoreExpired);
    }

    function test_expirationSlotCalculation() public {
        // Test that expiration slots use minimum of current and new frame durations

        // Case 1: Offset phase with new frame smaller than current (1 day < 13 days)
        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 1, 1, 64); // defaults

        uint256 fromRefSlot = epochEndSlot(1);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phasesConfig);

        (, uint256 offsetExpirationSlot, , , ) = updater.offsetPhase();
        (, uint256 restoreExpirationSlot, , , ) = updater.restorePhase();

        // Offset phase expected slot
        uint256 offsetExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        // Offset phase expiration should use min(DEFAULT_EPOCHS_PER_FRAME=2925, dayToEpochs(1)=225) = 225
        uint256 expectedOffsetPhaseExpiration = offsetExpectedSlot +
            (dayToEpochs(1) * SLOTS_PER_EPOCH);
        assertEq(
            offsetExpirationSlot,
            expectedOffsetPhaseExpiration,
            "Offset phase should use minimum frame duration (1 day)"
        );

        // Restore phase expected slot
        uint256 restoreExpectedSlot = calculateExpectedSlot(
            offsetExpectedSlot,
            1,
            dayToEpochs(1)
        );
        // Restore phase expiration should use min(dayToEpochs(1)=225, DEFAULT=2925) = 225
        uint256 expectedRestorePhaseExpiration = restoreExpectedSlot +
            (dayToEpochs(1) * SLOTS_PER_EPOCH);
        assertEq(
            restoreExpirationSlot,
            expectedRestorePhaseExpiration,
            "Restore phase should use minimum frame duration (1 day)"
        );
    }
}
