// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/utils/TwoPhaseFrameConfigUpdate.sol";
import { ReportProcessorMock } from "../helpers/mocks/ReportProcessorMock.sol";
import { MockConsensusContract } from "../helpers/mocks/ConsensusContractMock.sol";

contract TwoPhaseFrameConfigUpdateTest is Test {
    TwoPhaseFrameConfigUpdate public updater;
    ReportProcessorMock public mockFeeOracle;
    MockConsensusContract public mockConsensus;

    event Phase1Executed();
    event Phase2Executed();

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
        // Phase 1 uses currentEpochsPerFrame (from consensus contract), not phase1Config.newEpochsPerFrame
        // Phase 2 uses phase1Config.newEpochsPerFrame for slot calculation, not phase2Config
        return
            fromRefSlot + (reportsToProcess * epochsPerFrame * SLOTS_PER_EPOCH);
    }

    function calculateDeadlineSlot(
        uint256 expectedSlot,
        uint256 epochsPerFrame
    ) internal pure returns (uint256) {
        return expectedSlot + (epochsPerFrame * SLOTS_PER_EPOCH);
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
        mockFeeOracle = new ReportProcessorMock(1);
        mockFeeOracle.setConsensusContract(address(mockConsensus));
    }

    function mockLastProcessingRefSlot(uint256 lastProcessingRefSlot) internal {
        mockFeeOracle.setLastProcessingStartedRefSlot(lastProcessingRefSlot);
    }

    function createUpdater(
        TwoPhaseFrameConfigUpdate.PhaseConfig memory phase1Config,
        TwoPhaseFrameConfigUpdate.PhaseConfig memory phase2Config
    ) internal {
        updater = new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );
    }

    function createPhaseConfig(
        uint256 reportsToProcess,
        uint256 daysPerFrame,
        uint256 fastLaneSlots
    ) internal pure returns (TwoPhaseFrameConfigUpdate.PhaseConfig memory) {
        return
            TwoPhaseFrameConfigUpdate.PhaseConfig({
                reportsToProcess: reportsToProcess,
                newEpochsPerFrame: dayToEpochs(daysPerFrame),
                newFastLaneLengthSlots: fastLaneSlots
            });
    }

    function test_constructor_Success() public {
        uint256 phase1ReportsToProcess = 1;
        uint256 phase1DaysPerFrame = 1;
        uint256 phase1FastLaneSlots = 10;

        uint256 phase2ReportsToProcess = 2;
        uint256 phase2DaysPerFrame = 2;
        uint256 phase2FastLaneSlots = 20;

        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(
                phase1ReportsToProcess,
                phase1DaysPerFrame,
                phase1FastLaneSlots
            );
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(
                phase2ReportsToProcess,
                phase2DaysPerFrame,
                phase2FastLaneSlots
            );

        uint256 fromRefSlot = epochEndSlot({ dayCount: 1 });

        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        assertEq(address(updater.FEE_ORACLE()), address(mockFeeOracle));
        assertEq(address(updater.HASH_CONSENSUS()), address(mockConsensus));

        (uint256 phase1ExpectedProcessingRefSlot, , , , ) = updater.phase1();
        (uint256 phase2ExpectedProcessingRefSlot, , , , ) = updater.phase2();

        // fromRefSlot(7199) + (1 report * 2925 epochs * 32 slots) = 7199 + 93600 = 100799
        assertEq(phase1ExpectedProcessingRefSlot, 100799);

        // phase1Slot(100799) + (2 reports * 225 epochs * 32 slots) = 100799 + 14400 = 115199
        assertEq(phase2ExpectedProcessingRefSlot, 115199);

        // Verify execution status
        (, , , , bool phase1Executed) = updater.phase1();
        (, , , , bool phase2Executed) = updater.phase2();
        assertFalse(phase1Executed);
        assertFalse(phase2Executed);
    }

    function test_constructor_RevertWhen_InvalidParams() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        // Zero fee oracle address
        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.ZeroFeeOracleAddress.selector
        );
        new TwoPhaseFrameConfigUpdate(address(0), phase1Config, phase2Config);

        // Zero from ref slot
        mockFeeOracle.setLastProcessingStartedRefSlot(0);
        vm.expectRevert(TwoPhaseFrameConfigUpdate.ZeroFromRefSlot.selector);
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );

        // Zero reportsToProcess for phase1
        uint256 testDay = 10;
        mockFeeOracle.setLastProcessingStartedRefSlot(epochEndSlot(testDay));
        phase1Config.reportsToProcess = 0;
        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.ZeroReportsPassedToEnableUpdate.selector
        );
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );

        // Zero reportsToProcess for phase2
        phase1Config.reportsToProcess = 1;
        phase2Config.reportsToProcess = 0;
        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.ZeroReportsPassedToEnableUpdate.selector
        );
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );

        // Zero epochsPerFrame for phase1
        phase2Config.reportsToProcess = 2;
        phase1Config.newEpochsPerFrame = 0;
        vm.expectRevert(TwoPhaseFrameConfigUpdate.ZeroEpochsPerFrame.selector);
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );

        // Zero epochsPerFrame for phase2
        phase1Config.newEpochsPerFrame = EPOCHS_PER_DAY;
        phase2Config.newEpochsPerFrame = 0;
        vm.expectRevert(TwoPhaseFrameConfigUpdate.ZeroEpochsPerFrame.selector);
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );
    }

    function test_constructor_RevertWhen_Phase1AlreadyExpired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 20;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);

        uint256 phase1ExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phase1Config.reportsToProcess,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        uint256 phase1DeadlineSlot = calculateDeadlineSlot(
            phase1ExpectedSlot,
            dayToEpochs(1)
        );

        // Try to deploy contract after phase 1 deadline
        vm.warp((phase1DeadlineSlot + 1) * SECONDS_PER_SLOT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                phase1DeadlineSlot + 1,
                phase1DeadlineSlot
            )
        );
        new TwoPhaseFrameConfigUpdate(
            address(mockFeeOracle),
            phase1Config,
            phase2Config
        );
    }

    function test_executePhase1_Success() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        // Calculate expected phase 1 slot
        uint256 phase1ExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phase1Config.reportsToProcess,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);

        assertTrue(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());

        vm.expectEmit(address(updater));
        emit Phase1Executed();
        updater.executePhase1();

        (, , , , bool phase1Executed) = updater.phase1();
        (, , , , bool phase2Executed) = updater.phase2();
        assertTrue(phase1Executed);
        assertFalse(phase2Executed);
        assertFalse(updater.isReadyForPhase1());
    }

    function test_executePhase1_RevertWhen_UnexpectedRefSlot() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 expectedPhase1Slot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phase1Config.reportsToProcess,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        uint256 wrongSlot = 7000;
        mockFeeOracle.setLastProcessingStartedRefSlot(wrongSlot);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.UnexpectedRefSlot.selector,
                expectedPhase1Slot,
                wrongSlot
            )
        );
        updater.executePhase1();
    }

    function test_executePhase1_RevertWhen_AlreadyExecuted() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 phase1ExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phase1Config.reportsToProcess,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.Phase1AlreadyExecuted.selector
        );
        updater.executePhase1();
    }

    function test_executePhase1_RevertWhen_DeadlineExpired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 phase1ExpectedSlot = calculateExpectedSlot({
            fromRefSlot: fromRefSlot,
            reportsToProcess: phase1Config.reportsToProcess,
            epochsPerFrame: DEFAULT_EPOCHS_PER_FRAME
        });
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);

        uint256 deadlineSlot = calculateDeadlineSlot({
            expectedSlot: phase1ExpectedSlot,
            epochsPerFrame: phase1Config.newEpochsPerFrame
        });
        vm.warp((deadlineSlot + 1) * SECONDS_PER_SLOT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                (deadlineSlot + 1),
                deadlineSlot
            )
        );
        updater.executePhase1();
    }

    function test_executePhase2_Success() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        // Grant role to test renunciation
        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        // Execute Phase 1
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        // Execute Phase 2
        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);

        assertTrue(updater.isReadyForPhase2());
        vm.expectEmit(address(updater));
        emit Phase2Executed();
        updater.executePhase2();

        (, , , , bool phase1Executed) = updater.phase1();
        (, , , , bool phase2Executed) = updater.phase2();
        assertTrue(phase1Executed);
        assertTrue(phase2Executed);

        assertEq(mockConsensus.lastSetEpochsPerFrame(), dayToEpochs(2));
        assertEq(mockConsensus.lastSetFastLaneLengthSlots(), 20);

        // Verify role was renounced
        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );

        assertFalse(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());
    }

    function test_executePhase2_RevertWhen_WithoutPhase1() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        // Try to execute phase 2 without executing phase 1
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);

        vm.expectRevert(TwoPhaseFrameConfigUpdate.Phase1NotExecuted.selector);
        updater.executePhase2();
    }

    function test_executePhase2_RevertWhen_WithUnexpectedRefSlot() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 wrongSlot = 16000; // Some arbitrary wrong slot
        mockFeeOracle.setLastProcessingStartedRefSlot(wrongSlot);

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.UnexpectedRefSlot.selector,
                phase2ExpectedSlot,
                wrongSlot
            )
        );
        updater.executePhase2();
    }

    function test_executePhase2_RevertWhen_AlreadyExecuted() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);
        updater.executePhase2();

        vm.expectRevert(
            TwoPhaseFrameConfigUpdate.Phase2AlreadyExecuted.selector
        );
        updater.executePhase2();
    }

    function test_executePhase2_RevertWhen_WithDeadlineExpired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);

        // Calculate deadline: expected slot + frame duration
        uint256 deadlineSlot = calculateDeadlineSlot(
            phase2ExpectedSlot,
            dayToEpochs(2)
        );
        uint256 deadlineTimestamp = deadlineSlot * SECONDS_PER_SLOT;
        vm.warp(deadlineTimestamp);

        uint256 currentSlot = block.timestamp / SECONDS_PER_SLOT;
        (, uint256 phase2ExpirationSlot, , , ) = updater.phase2();

        vm.expectRevert(
            abi.encodeWithSelector(
                TwoPhaseFrameConfigUpdate.PhaseExpired.selector,
                currentSlot,
                phase2ExpirationSlot
            )
        );
        updater.executePhase2();
    }

    function test_renounceRoleWhenExpired_WhenPhase1Expired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

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

        // Calculate when phase 1 expires
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 phase1DeadlineSlot = calculateDeadlineSlot(
            phase1ExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME
        );
        vm.warp(phase1DeadlineSlot * SECONDS_PER_SLOT);

        (bool phase1Expired, ) = updater.getExpirationStatus();
        assertTrue(phase1Expired);

        updater.renounceRoleWhenExpired();

        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );
    }

    function test_renounceRoleWhenExpired_WhenPhase2Expired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 30;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        // Execute phase 1
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        // Calculate when phase 2 expires and set time past that
        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 phase2DeadlineSlot = calculateDeadlineSlot(
            phase2ExpectedSlot,
            dayToEpochs(2)
        );
        vm.warp(phase2DeadlineSlot * SECONDS_PER_SLOT);

        (, bool phase2Expired) = updater.getExpirationStatus();
        assertTrue(phase2Expired);

        updater.renounceRoleWhenExpired();

        assertFalse(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );
    }

    function test_renounceRoleWhenExpired_WhenNoPhasesExpired() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 20;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        mockConsensus.grantRole(
            mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
            address(updater)
        );

        (bool phase1Expired, bool phase2Expired) = updater
            .getExpirationStatus();
        assertFalse(phase1Expired);
        assertFalse(phase2Expired);

        updater.renounceRoleWhenExpired();

        assertTrue(
            mockConsensus.hasRole(
                mockConsensus.MANAGE_FRAME_CONFIG_ROLE(),
                address(updater)
            )
        );
    }

    function test_getPhaseConfigs() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        (
            TwoPhaseFrameConfigUpdate.PhaseState memory phase1State,
            TwoPhaseFrameConfigUpdate.PhaseState memory phase2State
        ) = updater.getPhaseConfigs();

        uint256 expectedPhase1Slot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 expectedPhase2Slot = calculateExpectedSlot(
            expectedPhase1Slot,
            2,
            EPOCHS_PER_DAY
        );

        assertEq(phase1State.expectedProcessingRefSlot, expectedPhase1Slot);
        assertEq(phase1State.newEpochsPerFrame, EPOCHS_PER_DAY); // phase1 config uses 1 day (225 epochs)
        assertEq(phase1State.newFastLaneLengthSlots, 10);
        assertFalse(phase1State.executed);

        assertEq(phase2State.expectedProcessingRefSlot, expectedPhase2Slot);
        assertEq(phase2State.newEpochsPerFrame, dayToEpochs(2));
        assertEq(phase2State.newFastLaneLengthSlots, 20);
        assertFalse(phase2State.executed);
    }

    function test_readinessStates() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 10;
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        // Initial state - not ready
        assertFalse(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());

        // Ready for phase 1
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        assertTrue(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());

        // Execute phase 1
        updater.executePhase1();
        assertFalse(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());

        // Ready for phase 2
        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);
        assertFalse(updater.isReadyForPhase1());
        assertTrue(updater.isReadyForPhase2());

        // Execute phase 2
        updater.executePhase2();
        assertFalse(updater.isReadyForPhase1());
        assertFalse(updater.isReadyForPhase2());
    }

    function test_getExpirationStatus() public {
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 1, 10); // 1 report, 1 day, 10 fast lane slots
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(2, 2, 20); // 2 reports, 2 days, 20 fast lane slots

        uint256 startingDay = 1; // Use smaller day to avoid overlaps with large DEFAULT_EPOCHS_PER_FRAME
        uint256 fromRefSlot = epochEndSlot(startingDay);
        mockLastProcessingRefSlot(fromRefSlot);
        createUpdater(phase1Config, phase2Config);

        // Initially neither expired
        (bool phase1Expired, bool phase2Expired) = updater
            .getExpirationStatus();
        assertFalse(phase1Expired);
        assertFalse(phase2Expired);

        // Calculate phase deadlines
        uint256 phase1ExpectedSlot = calculateExpectedSlot(
            fromRefSlot,
            1,
            DEFAULT_EPOCHS_PER_FRAME
        );
        uint256 phase1DeadlineSlot = calculateDeadlineSlot(
            phase1ExpectedSlot,
            DEFAULT_EPOCHS_PER_FRAME
        );

        // Past phase 1 deadline
        vm.warp(phase1DeadlineSlot * SECONDS_PER_SLOT);
        (phase1Expired, phase2Expired) = updater.getExpirationStatus();
        assertTrue(phase1Expired);

        // Execute phase 1 (reset time first to before any deadlines)
        uint256 safeTime = phase1ExpectedSlot * SECONDS_PER_SLOT;
        vm.warp(safeTime);
        mockFeeOracle.setLastProcessingStartedRefSlot(phase1ExpectedSlot);
        updater.executePhase1();

        // Calculate phase 2 deadline
        uint256 phase2ExpectedSlot = calculateExpectedSlot(
            phase1ExpectedSlot,
            2,
            EPOCHS_PER_DAY
        );
        uint256 phase2DeadlineSlot = calculateDeadlineSlot(
            phase2ExpectedSlot,
            dayToEpochs(2)
        );

        // Test phase 2 expiration independently
        vm.warp(phase2DeadlineSlot * SECONDS_PER_SLOT);
        (phase1Expired, phase2Expired) = updater.getExpirationStatus();
        assertFalse(phase1Expired); // Phase 1 executed, so not expired
        assertTrue(phase2Expired);

        // Execute phase 2 (reset time first)
        vm.warp(phase2ExpectedSlot * SECONDS_PER_SLOT);
        mockFeeOracle.setLastProcessingStartedRefSlot(phase2ExpectedSlot);
        updater.executePhase2();

        // Neither expired (both executed)
        vm.warp(phase2DeadlineSlot * SECONDS_PER_SLOT);
        (phase1Expired, phase2Expired) = updater.getExpirationStatus();
        assertFalse(phase1Expired);
        assertFalse(phase2Expired);
    }
}
