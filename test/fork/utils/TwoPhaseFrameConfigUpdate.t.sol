// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { TwoPhaseFrameConfigUpdate } from "../../../src/utils/TwoPhaseFrameConfigUpdate.sol";

contract TwoPhaseFrameConfigUpdateTest is Test, Utilities, DeploymentFixtures {
    TwoPhaseFrameConfigUpdate public updater;

    uint256 constant SLOTS_PER_EPOCH = 32;
    uint256 constant EPOCHS_PER_DAY = 225;

    function dayToEpochs(uint256 dayCount) internal pure returns (uint256) {
        return dayCount * EPOCHS_PER_DAY;
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

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }

    function test_shift24To28DaysFrameSize() public {
        (, , uint256 genesisTime) = hashConsensus.getChainConfig();

        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase1Config = createPhaseConfig(1, 24, 0); // 24-day phase
        TwoPhaseFrameConfigUpdate.PhaseConfig
            memory phase2Config = createPhaseConfig(1, 28, 0); // 28-day phase

        updater = new TwoPhaseFrameConfigUpdate(
            address(oracle),
            phase1Config,
            phase2Config
        );

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        address roleAdmin = hashConsensus.getRoleMember(0x00, 0);
        vm.prank(roleAdmin);
        hashConsensus.grantRole(manageFrameRole, address(updater));

        (
            uint256 currentInitialEpoch,
            uint256 currentEpochsPerFrame,
            uint256 currentFastLaneSlots
        ) = hashConsensus.getFrameConfig();
        (uint256 currentFrameRefSlot, ) = hashConsensus.getCurrentFrame();

        (
            uint256 phase1ExpectedProcessingRefSlot,
            uint256 phase1ExpirationSlot,
            ,
            ,

        ) = updater.phase1();

        uint256 calculatedPhase1ExpectedProcessingRefSlot = currentFrameRefSlot +
                (currentEpochsPerFrame * SLOTS_PER_EPOCH);
        assertEq(
            phase1ExpectedProcessingRefSlot,
            calculatedPhase1ExpectedProcessingRefSlot,
            "Phase 1 expected slot should align with current frame end"
        );

        uint256 calculatedPhase1ExpirationSlot = calculatedPhase1ExpectedProcessingRefSlot +
                (dayToEpochs(24) * SLOTS_PER_EPOCH);
        assertEq(
            phase1ExpirationSlot,
            calculatedPhase1ExpirationSlot,
            "Phase 1 expiration should be current frame end + frame size"
        );

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(phase1ExpectedProcessingRefSlot) // Simulate report processed for Phase1
        );

        // Warp time to align with phase 1 scenario (one frame after deployment)
        {
            uint256 warpTime = genesisTime +
                (phase1ExpectedProcessingRefSlot + 47) *
                12; // +47 = random offset within frame
            vm.warp(warpTime);
        }

        assertTrue(updater.isReadyForPhase1(), "Should be ready for phase 1");
        assertFalse(
            updater.isReadyForPhase2(),
            "Should not be ready for phase 2 yet"
        );

        updater.executePhase1();

        // Verify Phase 1 frame configuration changes
        {
            (
                uint256 phase1InitialEpoch,
                uint256 phase1EpochsPerFrame,
                uint256 phase1FastLaneSlots
            ) = hashConsensus.getFrameConfig();
            assertEq(
                phase1InitialEpoch,
                (phase1ExpectedProcessingRefSlot + 1) / 32,
                "Initial epoch should change to current frame ref slot epoch"
            );
            assertEq(
                phase1EpochsPerFrame,
                dayToEpochs(24),
                "Phase 1 should set 24-day frames"
            );
            assertEq(phase1FastLaneSlots, 0, "Fast lane slots should be 0");
        }

        // Calculate Phase 1 first frame ref slot (after 24-day frame)
        uint256 calculatedPhase1FirstFrameRefSlot = phase1ExpectedProcessingRefSlot +
                (dayToEpochs(24) * SLOTS_PER_EPOCH);

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(calculatedPhase1FirstFrameRefSlot) // Simulate report processed for Phase2
        );

        // Warp time to align with one frame processing after phase 1 execution
        {
            uint256 warpTime = genesisTime +
                (calculatedPhase1FirstFrameRefSlot + 34) *
                12; // +34 = random offset within frame
            vm.warp(warpTime);
        }

        (uint256 phase1FirstFrameRefSlot, ) = hashConsensus.getCurrentFrame();
        assertEq(
            phase1FirstFrameRefSlot,
            calculatedPhase1FirstFrameRefSlot,
            "Phase 1 frame should progress correctly"
        );

        // Verify Phase 2 timing calculations
        {
            (
                uint256 phase2ExpectedProcessingRefSlot,
                uint256 phase2ExpirationSlot,
                ,
                ,

            ) = updater.phase2();
            assertEq(
                phase2ExpectedProcessingRefSlot,
                phase1FirstFrameRefSlot,
                "Phase 2 expected slot should align with Phase 1 first frame"
            );

            uint256 calculatedPhase2ExpirationSlot = phase1FirstFrameRefSlot +
                (dayToEpochs(24) * SLOTS_PER_EPOCH);
            assertEq(
                phase2ExpirationSlot,
                calculatedPhase2ExpirationSlot,
                "Phase 2 expiration should be Phase 1 first frame ref slot + frame size"
            );
        }

        assertTrue(updater.isReadyForPhase2(), "Should be ready for phase 2");

        updater.executePhase2();

        // Verify Phase 2 frame configuration changes
        {
            (
                uint256 phase2InitialEpoch,
                uint256 phase2EpochsPerFrame,
                uint256 phase2FastLaneSlots
            ) = hashConsensus.getFrameConfig();
            assertEq(
                phase2InitialEpoch,
                (calculatedPhase1FirstFrameRefSlot + 1) / 32,
                "Initial epoch should change to Phase 1 first frame epoch"
            );
            assertEq(
                phase2EpochsPerFrame,
                dayToEpochs(28),
                "Phase 2 should restore 28-day frames"
            );
            assertEq(phase2FastLaneSlots, 0, "Fast lane slots should remain 0");
        }

        {
            (
                TwoPhaseFrameConfigUpdate.PhaseState memory phase1State,
                TwoPhaseFrameConfigUpdate.PhaseState memory phase2State
            ) = updater.getPhaseConfigs();

            assertTrue(phase1State.executed, "Phase 1 should be executed");
            assertTrue(phase2State.executed, "Phase 2 should be executed");
        }

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced after phase 2"
        );
    }
}
