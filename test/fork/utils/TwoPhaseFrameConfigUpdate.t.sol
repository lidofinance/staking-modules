// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

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

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }

    function test_shiftReportWindow() public {
        (, , uint256 genesisTime) = hashConsensus.getChainConfig();

        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 1, 31, 300); // 31-day phase, 1h fast lane

        updater = new TwoPhaseFrameConfigUpdate(address(oracle), phasesConfig);

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        bytes32 adminRole = hashConsensus.getRoleAdmin(manageFrameRole);
        address admin = hashConsensus.getRoleMember(adminRole, 0);
        vm.prank(admin);
        hashConsensus.grantRole(manageFrameRole, address(updater));

        (, uint256 currentEpochsPerFrame, ) = hashConsensus.getFrameConfig();
        (uint256 currentFrameRefSlot, ) = hashConsensus.getCurrentFrame();

        (
            uint256 offsetExpectedProcessingRefSlot,
            uint256 offsetExpirationSlot,
            ,
            ,

        ) = updater.offsetPhase();

        uint256 calculatedOffsetExpectedProcessingRefSlot = currentFrameRefSlot +
                (currentEpochsPerFrame * SLOTS_PER_EPOCH);
        assertEq(
            offsetExpectedProcessingRefSlot,
            calculatedOffsetExpectedProcessingRefSlot,
            "Offset phase expected slot should align with current frame end"
        );

        uint256 calculatedOffsetExpirationSlot = calculatedOffsetExpectedProcessingRefSlot +
                (currentEpochsPerFrame * SLOTS_PER_EPOCH);
        assertEq(
            offsetExpirationSlot,
            calculatedOffsetExpirationSlot,
            "Offset phase expiration should be current frame end + frame size"
        );

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(offsetExpectedProcessingRefSlot) // Simulate report processed for offset phase
        );

        // Warp time to align with offset phase scenario (one frame after deployment)
        {
            uint256 warpTime = genesisTime +
                (offsetExpectedProcessingRefSlot + 47) *
                12; // +47 = random offset within frame
            vm.warp(warpTime);
        }

        assertTrue(
            updater.isReadyForOffsetPhase(),
            "Should be ready for offset phase"
        );
        assertFalse(
            updater.isReadyForRestorePhase(),
            "Should not be ready for restore phase yet"
        );

        updater.executeOffsetPhase();

        // Verify offset frame configuration changes
        {
            (
                uint256 offsetPhaseInitialEpoch,
                uint256 offsetPhaseEpochsPerFrame,
                uint256 offsetPhaseFastLaneSlots
            ) = hashConsensus.getFrameConfig();
            assertEq(
                offsetPhaseInitialEpoch,
                (offsetExpectedProcessingRefSlot + 1) / 32,
                "Initial epoch should change to current frame ref slot epoch"
            );
            assertEq(
                offsetPhaseEpochsPerFrame,
                dayToEpochs(31),
                "Offset phase should set 31-day frames"
            );
            assertEq(
                offsetPhaseFastLaneSlots,
                0,
                "Fast lane slots should be 0 on offset phase"
            );
        }

        // Calculate Offset phase first frame ref slot (after 31-day frame)
        uint256 calculatedOffsetFirstFrameRefSlot = offsetExpectedProcessingRefSlot +
                (dayToEpochs(31) * SLOTS_PER_EPOCH);

        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(calculatedOffsetFirstFrameRefSlot) // Simulate report processed for RestorePhase
        );

        // Warp time to align with one frame processing after offset execution
        {
            uint256 warpTime = genesisTime +
                (calculatedOffsetFirstFrameRefSlot + 34) *
                12; // +34 = random offset within frame
            vm.warp(warpTime);
        }

        (uint256 offsetFirstFrameRefSlot, ) = hashConsensus.getCurrentFrame();
        assertEq(
            offsetFirstFrameRefSlot,
            calculatedOffsetFirstFrameRefSlot,
            "Offset phase frame should progress correctly"
        );

        // Verify Restore phase timing calculations
        {
            (
                uint256 restoreExpectedProcessingRefSlot,
                uint256 restorePhaseExpirationSlot,
                uint256 restorePhaseEpochsPerFrame,
                uint256 restorePhaseFastLaneSlots,

            ) = updater.restorePhase();
            assertEq(
                restoreExpectedProcessingRefSlot,
                offsetFirstFrameRefSlot,
                "Restore phase expected slot should align with Offset phase first frame"
            );

            uint256 calculatedRestorePhaseExpirationSlot = offsetFirstFrameRefSlot +
                    (currentEpochsPerFrame * SLOTS_PER_EPOCH);
            assertEq(
                restorePhaseExpirationSlot,
                calculatedRestorePhaseExpirationSlot,
                "Restore phase expiration should be Offset phase first frame ref slot + Restore phase frame size"
            );

            assertEq(
                restorePhaseEpochsPerFrame,
                currentEpochsPerFrame,
                "Restore phase should keep current frame length"
            );
            assertEq(
                restorePhaseFastLaneSlots,
                300,
                "Fast lane slots should reuse offsetPhase fast lane"
            );
        }

        assertTrue(
            updater.isReadyForRestorePhase(),
            "Should be ready for restore phase"
        );

        updater.executeRestorePhase();

        // Verify Restore phase frame configuration changes
        {
            (
                uint256 restorePhaseInitialEpoch,
                uint256 restorePhaseEpochsPerFrame,
                uint256 restorePhaseFastLaneSlots
            ) = hashConsensus.getFrameConfig();
            assertEq(
                restorePhaseInitialEpoch,
                (calculatedOffsetFirstFrameRefSlot + 1) / 32,
                "Initial epoch should change to Offset phase first frame epoch"
            );
            assertEq(
                restorePhaseEpochsPerFrame,
                dayToEpochs(28),
                "Restore phase should restore 28-day frames"
            );
            assertEq(
                restorePhaseFastLaneSlots,
                300,
                "Fast lane slots should remain 300"
            );
        }

        {
            (, , , , bool offsetPhaseExecuted) = updater.offsetPhase();
            (, , , , bool restorePhaseExecuted) = updater.restorePhase();

            assertTrue(offsetPhaseExecuted, "Offset phase should be executed");
            assertTrue(
                restorePhaseExecuted,
                "Restore phase should be executed"
            );
        }

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced after restore phase"
        );
    }

    function test_renounceRoleWhenOffsetPhaseExpired() public {
        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = hashConsensus.getChainConfig();

        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 1, 31, 300);

        updater = new TwoPhaseFrameConfigUpdate(address(oracle), phasesConfig);

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        bytes32 adminRole = hashConsensus.getRoleAdmin(manageFrameRole);
        address admin = hashConsensus.getRoleMember(adminRole, 0);
        vm.prank(admin);
        hashConsensus.grantRole(manageFrameRole, address(updater));

        (, uint256 offsetPhaseExpirationSlot, , , ) = updater.offsetPhase();

        // Warp past offset phase expiration without executing any phases
        vm.warp(genesisTime + (offsetPhaseExpirationSlot + 1) * secondsPerSlot);

        updater.renounceRoleWhenExpired();

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced when offset phase expired"
        );
    }

    function test_renounceRoleWhenRestorePhaseExpiredAfterOffsetPhase() public {
        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = hashConsensus.getChainConfig();

        TwoPhaseFrameConfigUpdate.PhasesConfig
            memory phasesConfig = createPhasesConfig(1, 1, 31, 300);

        updater = new TwoPhaseFrameConfigUpdate(address(oracle), phasesConfig);

        bytes32 manageFrameRole = hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
        bytes32 adminRole = hashConsensus.getRoleAdmin(manageFrameRole);
        address admin = hashConsensus.getRoleMember(adminRole, 0);
        vm.prank(admin);
        hashConsensus.grantRole(manageFrameRole, address(updater));

        (uint256 offsetExpectedProcessingRefSlot, , , , ) = updater
            .offsetPhase();

        // Mock oracle ref slot to allow offset phase execution
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("getLastProcessingRefSlot()"),
            abi.encode(offsetExpectedProcessingRefSlot)
        );

        // Warp into the offset phase frame window
        vm.warp(
            genesisTime + (offsetExpectedProcessingRefSlot + 1) * secondsPerSlot
        );

        updater.executeOffsetPhase();

        (, uint256 restorePhaseExpirationSlot, , , ) = updater.restorePhase();

        // Warp past restore phase expiration without executing it
        vm.warp(
            genesisTime + (restorePhaseExpirationSlot + 1) * secondsPerSlot
        );

        updater.renounceRoleWhenExpired();

        assertFalse(
            hashConsensus.hasRole(manageFrameRole, address(updater)),
            "Role should be renounced when restore phase expired after offset phase execution"
        );
    }
}
