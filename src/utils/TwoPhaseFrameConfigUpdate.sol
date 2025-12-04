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
        uint256 beforeOffsetPhaseReportsToProcess;
        /// @notice Reports to process after offset phase completion to enable the restore phase.
        uint256 beforeRestorePhaseReportsToProcess;
        /// @notice Offset phase epochs per frame.
        uint256 offsetPhaseEpochsPerFrame;
        /// @notice Offset fast lane length in slots (kept for restore).
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

    PhaseState public offsetPhase;
    PhaseState public restorePhase;

    event OffsetPhaseExecuted();
    event RestorePhaseExecuted();

    error ZeroFeeOracleAddress();
    error ZeroEpochsPerFrame();
    error ZeroReportsPassedToEnableUpdate();
    error ZeroFromRefSlot();
    error FastLanePeriodCannotBeLongerThanFrame();

    error OffsetPhaseAlreadyExecuted();
    error RestorePhaseAlreadyExecuted();
    error OffsetPhaseNotExecuted();
    error PhaseExpired(uint256 currentRefSlot, uint256 deadlineRefSlot);
    error UnexpectedRefSlot(uint256 expected, uint256 actual);

    constructor(address feeOracle, PhasesConfig memory phasesConfig) {
        if (feeOracle == address(0)) {
            revert ZeroFeeOracleAddress();
        }

        if (phasesConfig.beforeOffsetPhaseReportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.beforeRestorePhaseReportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phasesConfig.offsetPhaseEpochsPerFrame == 0) {
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
            phasesConfig.offsetPhaseEpochsPerFrame,
            phasesConfig.finalFastLaneLengthSlots,
            slotsPerEpoch
        );

        // Calculate pivot ref slot for the offset phase (based on last processing ref slot at deployment time)
        uint256 offsetExpectedProcessingRefSlot = lastProcessingRefSlot +
            (phasesConfig.beforeOffsetPhaseReportsToProcess *
                currentEpochsPerFrame *
                slotsPerEpoch);

        // Calculate deadline for the offset phase (before next original frame report processing or next frame with new possible config)
        uint256 offsetExpirationSlot = offsetExpectedProcessingRefSlot +
            (_min(
                currentEpochsPerFrame,
                phasesConfig.offsetPhaseEpochsPerFrame
            ) * slotsPerEpoch);

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= offsetExpirationSlot) {
            revert PhaseExpired(currentSlot, offsetExpirationSlot);
        }

        // Calculate pivot ref slot for the restore phase (based on offset phase completion)
        uint256 restoreExpectedProcessingRefSlot = offsetExpectedProcessingRefSlot +
                (phasesConfig.beforeRestorePhaseReportsToProcess *
                    phasesConfig.offsetPhaseEpochsPerFrame *
                    slotsPerEpoch);

        // Calculate deadline for the restore phase (before next offset-phase frame report processing or next possible frame with new config)
        uint256 restoreExpirationSlot = restoreExpectedProcessingRefSlot +
            (_min(
                phasesConfig.offsetPhaseEpochsPerFrame,
                currentEpochsPerFrame
            ) * slotsPerEpoch);

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
        PhaseState storage p = offsetPhase;
        if (p.executed) {
            revert OffsetPhaseAlreadyExecuted();
        }
        _ensurePhaseAlignment(p);

        uint256 epochsPerFrame = p.epochsPerFrame;
        uint256 fastLaneLength = p.fastLaneLengthSlots;

        HASH_CONSENSUS.setFrameConfig(epochsPerFrame, fastLaneLength);

        p.executed = true;
        emit OffsetPhaseExecuted();
    }

    /// @dev Executes the restore phase after offset phase is executed
    ///      and oracle is at the expected pivot ref slot but before expiration.
    function executeRestorePhase() external {
        if (!offsetPhase.executed) {
            revert OffsetPhaseNotExecuted();
        }
        PhaseState storage p = restorePhase;
        if (p.executed) {
            revert RestorePhaseAlreadyExecuted();
        }
        _ensurePhaseAlignment(p);

        uint256 epochsPerFrame = p.epochsPerFrame;
        uint256 fastLaneLength = p.fastLaneLengthSlots;

        HASH_CONSENSUS.setFrameConfig(epochsPerFrame, fastLaneLength);

        p.executed = true;
        emit RestorePhaseExecuted();

        _renounceRole();
    }

    /// @dev Fallback to renounce the role if phases are expired.
    function renounceRoleWhenExpired() external {
        uint256 currentSlot = _getCurrentSlot();
        bool offsetPhaseExpired = _isPhaseExpiredAtSlot(
            offsetPhase,
            currentSlot
        );
        bool restorePhaseExpired = _isPhaseExpiredAtSlot(
            restorePhase,
            currentSlot
        );
        if (offsetPhaseExpired || restorePhaseExpired) {
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
        returns (
            PhaseState memory offsetConfig,
            PhaseState memory restoreConfig
        )
    {
        return (offsetPhase, restorePhase);
    }

    function isReadyForOffsetPhase() external view returns (bool ready) {
        uint256 currentSlot = _getCurrentSlot();
        return _canExecutePhaseAtSlot(offsetPhase, currentSlot);
    }

    function isReadyForRestorePhase() external view returns (bool ready) {
        if (!offsetPhase.executed) {
            return false;
        }
        uint256 currentSlot = _getCurrentSlot();
        return _canExecutePhaseAtSlot(restorePhase, currentSlot);
    }

    function getExpirationStatus()
        external
        view
        returns (bool offsetExpired, bool restoreExpired)
    {
        uint256 currentSlot = _getCurrentSlot();
        return (
            _isPhaseExpiredAtSlot(offsetPhase, currentSlot),
            _isPhaseExpiredAtSlot(restorePhase, currentSlot)
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
