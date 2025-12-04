// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IReportAsyncProcessor } from "../lib/base-oracle/interfaces/IReportAsyncProcessor.sol";
import { IConsensusContract } from "../lib/base-oracle/interfaces/IConsensusContract.sol";

/// @notice A helper to offset Oracle report cadence (e.g., move report window by N epochs).
///         This is achieved via a two-phase frame configuration update
///         in HashConsensus contract used by Oracle:
///         - Phase 1: set new frame size (shorter or longer than original) and fast lane length
///                    after Oracle has processed a defined number of reports with the original frame config.
///         - Phase 2: set the original frame size and remains Phase 1 fast lane length
///                    after Oracle has processed a defined number of reports with the phase 1 config.
///         As a result, the Oracle report window is shifted by the difference between
///         the original and phase 1 frame sizes.
///         ---
///         Due to off-chain Oracle sanity checks, frame config can be changed only when
///         Oracle has no missing reports at the moment and before current or possible (by executed phase) frame reference slot.
///         In other words, only between reports processing for two consecutive frames.
/// @dev The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted in the
///      `HashConsensus` contract in order to be able to call `setFrameConfig`.
///      The role should be revoked after both phases are executed.
contract TwoPhaseFrameConfigUpdate {
    struct PhasesConfig {
        /// @notice Reports to process from `lastProcessingRefSlot` at deployment to enable phase1.
        uint256 beforePhase1ReportsToProcess;
        /// @notice Reports to process after phase1 completion to enable phase2.
        uint256 afterPhase1ReportsToProcess;
        /// @notice Phase1 epochs per frame.
        uint256 transitionalEpochsPerFrame;
        /// @notice Phase1 fast lane length in slots.
        uint256 finalFastLaneLengthSlots;
    }

    struct PhaseState {
        /// @notice Expected oracle's last processing ref slot for phase execution.
        ///         This phase can be executed when FEE_ORACLE.getLastProcessingRefSlot()
        ///         equals this value (i.e., oracle has processed the expected number of reports).
        uint256 expectedProcessingRefSlot;
        /// @notice Slot when this phase expires.
        ///         This phase expires when current slot (calculated from block.timestamp)
        ///         is greater than or equal to this value.
        uint256 expirationSlot;
        uint256 epochsPerFrame;
        uint256 fastLaneLengthSlots;
        bool executed;
    }

    IReportAsyncProcessor public immutable FEE_ORACLE;
    IConsensusContract public immutable HASH_CONSENSUS;
    uint256 public immutable SECONDS_PER_SLOT;
    uint256 public immutable GENESIS_TIME;
    uint256 public immutable SLOTS_PER_EPOCH;

    PhaseState public phase1;
    PhaseState public phase2;

    event Phase1Executed();
    event Phase2Executed();

    error ZeroFeeOracleAddress();
    error ZeroEpochsPerFrame();
    error ZeroReportsPassedToEnableUpdate();
    error ZeroFromRefSlot();
    error FastLanePeriodCannotBeLongerThanFrame();

    error Phase1AlreadyExecuted();
    error Phase2AlreadyExecuted();
    error Phase1NotExecuted();
    error PhaseExpired(uint256 currentRefSlot, uint256 deadlineRefSlot);
    error UnexpectedRefSlot(uint256 expected, uint256 actual);

    constructor(address feeOracle, PhasesConfig memory phasesConfig) {
        if (feeOracle == address(0)) {
            revert ZeroFeeOracleAddress();
        }

        if (phasesConfig.beforePhase1ReportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.afterPhase1ReportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.transitionalEpochsPerFrame == 0) {
            revert ZeroEpochsPerFrame();
        }

        FEE_ORACLE = IReportAsyncProcessor(feeOracle);
        HASH_CONSENSUS = IConsensusContract(FEE_ORACLE.getConsensusContract());

        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = HASH_CONSENSUS.getChainConfig();
        SLOTS_PER_EPOCH = slotsPerEpoch;
        SECONDS_PER_SLOT = secondsPerSlot;
        GENESIS_TIME = genesisTime;

        (, uint256 currentEpochsPerFrame, ) = HASH_CONSENSUS.getFrameConfig();
        uint256 lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();

        if (lastProcessingRefSlot == 0) {
            revert ZeroFromRefSlot();
        }

        _ensureFastLaneFitsFrame(
            currentEpochsPerFrame,
            phasesConfig.finalFastLaneLengthSlots,
            slotsPerEpoch
        );
        _ensureFastLaneFitsFrame(
            phasesConfig.transitionalEpochsPerFrame,
            phasesConfig.finalFastLaneLengthSlots,
            slotsPerEpoch
        );

        // Calculate pivot ref slot for phase 1 (based on last processing ref slot at deployment time)
        uint256 phase1ExpectedProcessingRefSlot = lastProcessingRefSlot +
            (phasesConfig.beforePhase1ReportsToProcess *
                currentEpochsPerFrame *
                slotsPerEpoch);

        // Calculate deadline for phase 1 (before next original frame report processing or next frame with new possible config)
        uint256 phase1ExpirationSlot = phase1ExpectedProcessingRefSlot +
            (_min(
                currentEpochsPerFrame,
                phasesConfig.transitionalEpochsPerFrame
            ) * slotsPerEpoch);

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= phase1ExpirationSlot) {
            revert PhaseExpired(currentSlot, phase1ExpirationSlot);
        }

        // Calculate pivot ref slot for phase 2 (based on phase 1 completion)
        uint256 phase2ExpectedProcessingRefSlot = phase1ExpectedProcessingRefSlot +
                (phasesConfig.afterPhase1ReportsToProcess *
                    phasesConfig.transitionalEpochsPerFrame *
                    slotsPerEpoch);

        // Calculate deadline for phase 2 (before next phase 1 frame report processing or next possible frame with new config)
        uint256 phase2ExpirationSlot = phase2ExpectedProcessingRefSlot +
            (_min(
                phasesConfig.transitionalEpochsPerFrame,
                currentEpochsPerFrame
            ) * slotsPerEpoch);

        phase1 = PhaseState({
            expectedProcessingRefSlot: phase1ExpectedProcessingRefSlot,
            expirationSlot: phase1ExpirationSlot,
            epochsPerFrame: phasesConfig.transitionalEpochsPerFrame,
            fastLaneLengthSlots: phasesConfig.finalFastLaneLengthSlots,
            executed: false
        });

        phase2 = PhaseState({
            expectedProcessingRefSlot: phase2ExpectedProcessingRefSlot,
            expirationSlot: phase2ExpirationSlot,
            epochsPerFrame: currentEpochsPerFrame,
            fastLaneLengthSlots: phasesConfig.finalFastLaneLengthSlots,
            executed: false
        });
    }

    /// @dev Can only be called when oracle is at the expected pivot ref slot for phase 1.
    function executePhase1() external {
        PhaseState storage p = phase1;
        if (p.executed) {
            revert Phase1AlreadyExecuted();
        }
        _ensurePhaseAlignment(p);

        uint256 epochsPerFrame = p.epochsPerFrame;
        uint256 fastLaneLength = p.fastLaneLengthSlots;

        HASH_CONSENSUS.setFrameConfig(epochsPerFrame, fastLaneLength);

        p.executed = true;
        emit Phase1Executed();
    }

    /// @dev Can only be called after phase1 is executed and when oracle is at the expected pivot ref slot for phase 2.
    function executePhase2() external {
        if (!phase1.executed) {
            revert Phase1NotExecuted();
        }
        PhaseState storage p = phase2;
        if (p.executed) {
            revert Phase2AlreadyExecuted();
        }
        _ensurePhaseAlignment(p);

        uint256 epochsPerFrame = p.epochsPerFrame;
        uint256 fastLaneLength = p.fastLaneLengthSlots;

        HASH_CONSENSUS.setFrameConfig(epochsPerFrame, fastLaneLength);

        p.executed = true;
        emit Phase2Executed();

        _renounceRole();
    }

    /// @dev Fallback to renounce the role if phases are expired.
    function renounceRoleWhenExpired() external {
        uint256 currentSlot = _getCurrentSlot();
        bool phase1Expired = _isPhaseExpiredAtSlot(phase1, currentSlot);
        bool phase2Expired = _isPhaseExpiredAtSlot(phase2, currentSlot);
        if (phase1Expired || phase2Expired) {
            _renounceRole();
        }
    }

    function _renounceRole() internal {
        IAccessControl(address(HASH_CONSENSUS)).renounceRole(
            HASH_CONSENSUS.MANAGE_FRAME_CONFIG_ROLE(),
            address(this)
        );
    }

    function getPhaseConfigs()
        external
        view
        returns (PhaseState memory phase1Config, PhaseState memory phase2Config)
    {
        return (phase1, phase2);
    }

    function isReadyForPhase1() external view returns (bool ready) {
        uint256 currentSlot = _getCurrentSlot();
        return _canExecutePhaseAtSlot(phase1, currentSlot);
    }

    function isReadyForPhase2() external view returns (bool ready) {
        if (!phase1.executed) {
            return false;
        }
        uint256 currentSlot = _getCurrentSlot();
        return _canExecutePhaseAtSlot(phase2, currentSlot);
    }

    function getExpirationStatus()
        external
        view
        returns (bool phase1Expired, bool phase2Expired)
    {
        uint256 currentSlot = _getCurrentSlot();
        return (
            _isPhaseExpiredAtSlot(phase1, currentSlot),
            _isPhaseExpiredAtSlot(phase2, currentSlot)
        );
    }

    function _getCurrentSlot() internal view returns (uint256 currentSlot) {
        return (block.timestamp - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function _isPhaseExpiredAtSlot(
        PhaseState storage phaseState,
        uint256 currentSlot
    ) internal view returns (bool expired) {
        return !phaseState.executed && currentSlot >= phaseState.expirationSlot;
    }

    function _canExecutePhaseAtSlot(
        PhaseState storage phaseState,
        uint256 currentSlot
    ) internal view returns (bool) {
        if (phaseState.executed) {
            return false;
        }

        return
            _hasExpectedRefSlot(phaseState) &&
            _isBeforeExpirationAtSlot(phaseState, currentSlot);
    }

    function _ensurePhaseAlignment(
        PhaseState storage phaseState
    ) internal view {
        _ensureExpectedRefSlot(phaseState);
        _ensureNotExpired(phaseState);
    }

    function _ensureExpectedRefSlot(
        PhaseState storage phaseState
    ) internal view {
        (bool matches, uint256 lastProcessingRefSlot) = _refSlotMatches(
            phaseState
        );
        if (!matches) {
            revert UnexpectedRefSlot(
                phaseState.expectedProcessingRefSlot,
                lastProcessingRefSlot
            );
        }
    }

    function _ensureNotExpired(PhaseState storage phaseState) internal view {
        uint256 currentSlot = _getCurrentSlot();
        if (!_isBeforeExpirationAtSlot(phaseState, currentSlot)) {
            revert PhaseExpired(currentSlot, phaseState.expirationSlot);
        }
    }

    function _hasExpectedRefSlot(
        PhaseState storage phaseState
    ) internal view returns (bool) {
        (bool matches, ) = _refSlotMatches(phaseState);
        return matches;
    }

    function _refSlotMatches(
        PhaseState storage phaseState
    ) internal view returns (bool matches, uint256 lastProcessingRefSlot) {
        lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();
        matches = lastProcessingRefSlot == phaseState.expectedProcessingRefSlot;
    }

    function _isBeforeExpirationAtSlot(
        PhaseState storage phaseState,
        uint256 currentSlot
    ) internal view returns (bool) {
        return currentSlot < phaseState.expirationSlot;
    }

    function _ensureFastLaneFitsFrame(
        uint256 epochsPerFrame,
        uint256 fastLaneLengthSlots,
        uint256 slotsPerEpoch
    ) internal pure {
        if (fastLaneLengthSlots > epochsPerFrame * slotsPerEpoch) {
            revert FastLanePeriodCannotBeLongerThanFrame();
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
