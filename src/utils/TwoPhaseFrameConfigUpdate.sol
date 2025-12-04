// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IReportAsyncProcessor } from "../lib/base-oracle/interfaces/IReportAsyncProcessor.sol";
import { IConsensusContract } from "../lib/base-oracle/interfaces/IConsensusContract.sol";

/// @notice A helper to offset Oracle report cadence (e.g., move report window by N epochs).
///         This is achieved via a two-phase frame configuration update
///         in HashConsensus contract used by Oracle:
///         - Offset phase: set transitional frame size (shorter or longer than original) and fast lane length
///                        after Oracle has processed a defined number of reports with the original frame config.
///         - Restore phase: set the original frame size while keeping offset fast lane length
///                        after Oracle has processed a defined number of reports with the offset config.
///         As a result, the Oracle report window is shifted by the difference between
///         the original and transitional frame sizes.
///         ---
///         Due to off-chain Oracle sanity checks, frame config can be changed only when
///         Oracle has no missing reports at the moment and before current or possible (by executed phase) frame reference slot.
///         In other words, only between reports processing for two consecutive frames.
/// @dev The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted in the
///      `HashConsensus` contract in order to be able to call `setFrameConfig`.
///      The role should be revoked after both phases are executed.
contract TwoPhaseFrameConfigUpdate {
    struct PhasesConfig {
        /// @notice Reports to process from `lastProcessingRefSlot` at deployment to enable the offset phase.
        uint256 reportsToProcessBeforeOffsetPhase;
        /// @notice Reports to process after offset phase completion to enable the restore phase.
        uint256 reportsToProcessBeforeRestorePhase;
        /// @notice Offset phase epochs per frame.
        uint256 offsetPhaseEpochsPerFrame;
        /// @notice Offset fast lane length in slots (kept for restore).
        uint256 finalFastLaneLengthSlots;
    }

    struct PhaseState {
        /// @notice Expected oracle's last processing ref slot for phase execution.
        ///         This phase can be executed when ORACLE.getLastProcessingRefSlot()
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

    IReportAsyncProcessor public immutable ORACLE;
    IConsensusContract public immutable HASH_CONSENSUS;
    uint256 public immutable SECONDS_PER_SLOT;
    uint256 public immutable GENESIS_TIME;
    uint256 public immutable SLOTS_PER_EPOCH;

    PhaseState public offsetPhase;
    PhaseState public restorePhase;

    event OffsetPhaseExecuted();
    event RestorePhaseExecuted();

    error ZeroOracleAddress();
    error ZeroEpochsPerFrame();
    error ZeroReportsPassedToEnableUpdate();
    error ZeroFromRefSlot();
    error FastLanePeriodCannotBeLongerThanFrame();

    error PhaseAlreadyExecuted();
    error OffsetPhaseNotExecuted();
    error PhaseExpired(uint256 currentRefSlot, uint256 deadlineRefSlot);
    error UnexpectedRefSlot(uint256 actual, uint256 expected);

    constructor(address oracle, PhasesConfig memory phasesConfig) {
        if (oracle == address(0)) {
            revert ZeroOracleAddress();
        }

        if (phasesConfig.reportsToProcessBeforeOffsetPhase == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.reportsToProcessBeforeRestorePhase == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.offsetPhaseEpochsPerFrame == 0) {
            revert ZeroEpochsPerFrame();
        }

        ORACLE = IReportAsyncProcessor(oracle);
        HASH_CONSENSUS = IConsensusContract(ORACLE.getConsensusContract());

        (
            uint256 slotsPerEpoch,
            uint256 secondsPerSlot,
            uint256 genesisTime
        ) = HASH_CONSENSUS.getChainConfig();
        SLOTS_PER_EPOCH = slotsPerEpoch;
        SECONDS_PER_SLOT = secondsPerSlot;
        GENESIS_TIME = genesisTime;

        (, uint256 currentEpochsPerFrame, ) = HASH_CONSENSUS.getFrameConfig();
        uint256 lastProcessingRefSlot = ORACLE.getLastProcessingRefSlot();

        if (lastProcessingRefSlot == 0) {
            revert ZeroFromRefSlot();
        }

        uint256 minEpochsPerFrame = currentEpochsPerFrame <
            phasesConfig.offsetPhaseEpochsPerFrame
            ? currentEpochsPerFrame
            : phasesConfig.offsetPhaseEpochsPerFrame;

        _ensureFastLaneFitsFrame(
            minEpochsPerFrame,
            phasesConfig.finalFastLaneLengthSlots,
            slotsPerEpoch
        );

        // Calculate pivot ref slot for the offset phase (based on last processing ref slot at deployment time)
        uint256 offsetExpectedProcessingRefSlot = lastProcessingRefSlot +
            (phasesConfig.reportsToProcessBeforeOffsetPhase *
                currentEpochsPerFrame *
                slotsPerEpoch);

        // Calculate deadline for the offset phase (before next original frame report processing or next frame with new possible config)
        uint256 offsetExpirationSlot = offsetExpectedProcessingRefSlot +
            minEpochsPerFrame *
            slotsPerEpoch;

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= offsetExpirationSlot) {
            revert PhaseExpired(currentSlot, offsetExpirationSlot);
        }

        // Calculate pivot ref slot for the restore phase (based on offset phase completion)
        uint256 restoreExpectedProcessingRefSlot = offsetExpectedProcessingRefSlot +
                (phasesConfig.reportsToProcessBeforeRestorePhase *
                    phasesConfig.offsetPhaseEpochsPerFrame *
                    slotsPerEpoch);

        // Calculate deadline for the restore phase (before next offset-phase frame report processing or next possible frame with new config)
        uint256 restoreExpirationSlot = restoreExpectedProcessingRefSlot +
            minEpochsPerFrame *
            slotsPerEpoch;

        offsetPhase = PhaseState({
            expectedProcessingRefSlot: offsetExpectedProcessingRefSlot,
            expirationSlot: offsetExpirationSlot,
            epochsPerFrame: phasesConfig.offsetPhaseEpochsPerFrame,
            fastLaneLengthSlots: phasesConfig.finalFastLaneLengthSlots,
            executed: false
        });

        restorePhase = PhaseState({
            expectedProcessingRefSlot: restoreExpectedProcessingRefSlot,
            expirationSlot: restoreExpirationSlot,
            epochsPerFrame: currentEpochsPerFrame,
            fastLaneLengthSlots: phasesConfig.finalFastLaneLengthSlots,
            executed: false
        });
    }

    /// @dev Executes the offset phase when oracle is at the expected pivot ref slot but before expiration.
    function executeOffsetPhase() external {
        PhaseState storage phase = offsetPhase;
        _validate(phase);
        HASH_CONSENSUS.setFrameConfig(
            phase.epochsPerFrame,
            phase.fastLaneLengthSlots
        );

        phase.executed = true;
        emit OffsetPhaseExecuted();
    }

    /// @dev Executes the restore phase after offset phase is executed
    ///      and oracle is at the expected pivot ref slot but before expiration.
    function executeRestorePhase() external {
        if (!offsetPhase.executed) {
            revert OffsetPhaseNotExecuted();
        }
        PhaseState storage phase = restorePhase;
        _validate(phase);
        HASH_CONSENSUS.setFrameConfig(
            phase.epochsPerFrame,
            phase.fastLaneLengthSlots
        );

        phase.executed = true;
        emit RestorePhaseExecuted();

        _renounceRole();
    }

    /// @dev Fallback to renounce the role if phases are expired.
    function renounceRoleWhenExpired() external {
        uint256 currentSlot = _getCurrentSlot();

        // If offset phase is expired, both phases cannot be executed anymore
        if (_isExpired(offsetPhase, currentSlot)) {
            _renounceRole();
            return;
        }

        if (_isExpired(restorePhase, currentSlot)) {
            _renounceRole();
        }
    }

    function isReadyForOffsetPhase() external view returns (bool ready) {
        uint256 currentSlot = _getCurrentSlot();
        return _isReady(offsetPhase, currentSlot);
    }

    function isReadyForRestorePhase() external view returns (bool ready) {
        if (!offsetPhase.executed) {
            return false;
        }
        uint256 currentSlot = _getCurrentSlot();
        return _isReady(restorePhase, currentSlot);
    }

    function getExpirationStatus()
        external
        view
        returns (bool offsetExpired, bool restoreExpired)
    {
        uint256 currentSlot = _getCurrentSlot();
        return (
            _isExpired(offsetPhase, currentSlot),
            _isExpired(restorePhase, currentSlot)
        );
    }

    function _renounceRole() internal {
        IAccessControl(address(HASH_CONSENSUS)).renounceRole(
            HASH_CONSENSUS.MANAGE_FRAME_CONFIG_ROLE(),
            address(this)
        );
    }

    function _validate(PhaseState storage phaseState) internal view {
        if (phaseState.executed) {
            revert PhaseAlreadyExecuted();
        }

        (
            bool hasExpectedRefSlot,
            uint256 lastProcessingRefSlot
        ) = _hasExpectedRefSlot(phaseState);
        if (!hasExpectedRefSlot) {
            revert UnexpectedRefSlot(
                lastProcessingRefSlot,
                phaseState.expectedProcessingRefSlot
            );
        }

        uint256 currentSlot = _getCurrentSlot();
        uint256 expirationSlot = phaseState.expirationSlot;
        if (currentSlot >= expirationSlot) {
            revert PhaseExpired(currentSlot, expirationSlot);
        }
    }

    function _getCurrentSlot() internal view returns (uint256 currentSlot) {
        return (block.timestamp - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    function _isReady(
        PhaseState storage phaseState,
        uint256 currentSlot
    ) internal view returns (bool ready) {
        if (phaseState.executed || currentSlot >= phaseState.expirationSlot) {
            return false;
        }
        (ready, ) = _hasExpectedRefSlot(phaseState);
    }

    function _isExpired(
        PhaseState storage phaseState,
        uint256 currentSlot
    ) internal view returns (bool expired) {
        return !phaseState.executed && currentSlot >= phaseState.expirationSlot;
    }

    function _hasExpectedRefSlot(
        PhaseState storage phaseState
    ) internal view returns (bool matches, uint256 lastProcessingRefSlot) {
        lastProcessingRefSlot = ORACLE.getLastProcessingRefSlot();
        matches = lastProcessingRefSlot == phaseState.expectedProcessingRefSlot;
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
}
