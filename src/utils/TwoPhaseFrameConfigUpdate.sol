// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IReportAsyncProcessor } from "../lib/base-oracle/interfaces/IReportAsyncProcessor.sol";
import { IConsensusContract } from "../lib/base-oracle/interfaces/IConsensusContract.sol";

/// @notice A helper to offset the Oracle report schedule (e.g., move the report window by N epochs).
///         This is achieved via a two-phase frame configuration update in the HashConsensus contract used by the Oracle:
///         - Offset phase: set a transitional frame size (shorter or longer than the original) and disable the fast
///         lane after the Oracle has completed main phase in report processing for a defined number of reports with the original frame config.
///         - Restore phase: set the original frame size and the desired fast lane length after the Oracle has
///         completed main phase in report processing for a defined number of reports with the transitional config.
///         As a result, the Oracle report window is shifted by the following calculation:
///          - If currentEpochsPerFrame > offsetPhaseEpochsPerFrame:
///            `shift = reportsToProcessBeforeRestorePhase * (currentEpochsPerFrame - offsetPhaseEpochsPerFrame)`
///          - If offsetPhaseEpochsPerFrame > currentEpochsPerFrame:
///            `shift = reportsToProcessBeforeRestorePhase * (offsetPhaseEpochsPerFrame - currentEpochsPerFrame)`
///         ---
///         Due to the CSM Oracle off-chain sanity checks, the frame config cannot be changed if there is a missing
///         report. Also, the frame config for the CSM oracle should not be changed such that the new reference slot is
///         in the past.
/// @dev    The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted on the
///         `HashConsensus` contract in order to be able to call `setFrameConfig`.
contract TwoPhaseFrameConfigUpdate {
    struct PhasesConfig {
        /// @notice Reports to complete main phase in report processing from the `lastProcessingRefSlot` (as of deployment) to enable the offset phase.
        uint256 reportsToProcessBeforeOffsetPhase;
        /// @notice Reports to complete main phase in report processing after the offset phase completion to enable the restore phase.
        uint256 reportsToProcessBeforeRestorePhase;
        /// @notice Offset phase epochs per frame.
        uint256 offsetPhaseEpochsPerFrame;
        /// @notice Restore phase fast lane length in slots.
        uint256 restorePhaseFastLaneLengthSlots;
    }

    struct PhaseState {
        /// @notice Expected oracle's last processing ref slot for phase execution.
        ///         This phase can be executed when ORACLE.getLastProcessingRefSlot()
        ///         equals this value (i.e., oracle has completed the expected number of main phases in report processing).
        uint256 expectedProcessingRefSlot;
        /// @notice Slot when this phase expires.
        ///         This phase expires when the current slot (calculated from block.timestamp)
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

    /// @dev Fast lane is expected to be disabled during the offset phase.
    uint256 public constant OFFSET_PHASE_FAST_LANE_LENGTH = 0;

    PhaseState public offsetPhase;
    PhaseState public restorePhase;

    event OffsetPhaseExecuted();
    event RestorePhaseExecuted();

    error ZeroOracleAddress();
    error ZeroEpochsPerFrame();
    error ZeroReportsToEnableUpdate();
    error CurrentReportMainPhaseIsNotCompleted();
    error FastLanePeriodCannotBeLongerThanFrame();
    error FastLaneTooShort();
    error NoneOfPhasesExpired();

    error PhaseAlreadyExecuted();
    error OffsetPhaseNotExecuted();
    error PhaseExpired(uint256 currentSlot, uint256 deadlineSlot);
    error UnexpectedLastProcessingRefSlot(uint256 actual, uint256 expected);

    constructor(address oracle, PhasesConfig memory phasesConfig) {
        if (oracle == address(0)) {
            revert ZeroOracleAddress();
        }

        if (phasesConfig.reportsToProcessBeforeOffsetPhase == 0) {
            revert ZeroReportsToEnableUpdate();
        }

        if (phasesConfig.reportsToProcessBeforeRestorePhase == 0) {
            revert ZeroReportsToEnableUpdate();
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

        (uint256 currentRefSlot, ) = HASH_CONSENSUS.getCurrentFrame();
        if (currentRefSlot != lastProcessingRefSlot) {
            revert CurrentReportMainPhaseIsNotCompleted();
        }

        // Typically, the Lido oracles wait for ref slot finalization, which takes at least 2 epochs.
        if (
            phasesConfig.restorePhaseFastLaneLengthSlots < SLOTS_PER_EPOCH * 2
        ) {
            revert FastLaneTooShort();
        }

        if (
            phasesConfig.restorePhaseFastLaneLengthSlots >
            currentEpochsPerFrame * slotsPerEpoch
        ) {
            revert FastLanePeriodCannotBeLongerThanFrame();
        }

        // Calculate pivot ref slot for the offset phase (based on the last processing ref slot as of deployment)
        uint256 offsetExpectedProcessingRefSlot = lastProcessingRefSlot +
            (phasesConfig.reportsToProcessBeforeOffsetPhase *
                currentEpochsPerFrame *
                slotsPerEpoch);

        uint256 minEpochsPerFrame = Math.min(
            phasesConfig.offsetPhaseEpochsPerFrame,
            currentEpochsPerFrame
        );

        // Ensure that after offset phase execution we won't end up having a missing report (offsetPhaseEpochsPerFrame <
        // currentEpochsPerFrame) and we haven't started reaching consensus for the extra report
        // (offsetPhaseEpochsPerFrame > currentEpochsPerFrame).
        // Example: currentEpochsPerFrame = 28 days, offsetPhaseEpochsPerFrame = 20 days
        //        if offset phase is executed after more than 20 days since the last report,
        //        we will have a missing report for the new frame config.
        uint256 offsetExpirationSlot = offsetExpectedProcessingRefSlot +
            minEpochsPerFrame *
            slotsPerEpoch;

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= offsetExpirationSlot) {
            revert PhaseExpired(currentSlot, offsetExpirationSlot);
        }

        // Calculate pivot ref slot for the restore phase (based on the offset phase completion)
        uint256 restoreExpectedProcessingRefSlot = offsetExpectedProcessingRefSlot +
                (phasesConfig.reportsToProcessBeforeRestorePhase *
                    phasesConfig.offsetPhaseEpochsPerFrame *
                    slotsPerEpoch);

        // See the comment above for the offsetExpirationSlot.
        uint256 restoreExpirationSlot = restoreExpectedProcessingRefSlot +
            minEpochsPerFrame *
            slotsPerEpoch;

        offsetPhase = PhaseState({
            expectedProcessingRefSlot: offsetExpectedProcessingRefSlot,
            expirationSlot: offsetExpirationSlot,
            epochsPerFrame: phasesConfig.offsetPhaseEpochsPerFrame,
            fastLaneLengthSlots: OFFSET_PHASE_FAST_LANE_LENGTH,
            executed: false
        });

        restorePhase = PhaseState({
            expectedProcessingRefSlot: restoreExpectedProcessingRefSlot,
            expirationSlot: restoreExpirationSlot,
            epochsPerFrame: currentEpochsPerFrame,
            fastLaneLengthSlots: phasesConfig.restorePhaseFastLaneLengthSlots,
            executed: false
        });
    }

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
        if (!_isExpired(offsetPhase) && !_isExpired(restorePhase)) {
            revert NoneOfPhasesExpired();
        }

        _renounceRole();
    }

    function isReadyForOffsetPhase() external view returns (bool ready) {
        return _isReady(offsetPhase);
    }

    function isReadyForRestorePhase() external view returns (bool ready) {
        if (!offsetPhase.executed) {
            return false;
        }

        return _isReady(restorePhase);
    }

    function getExpirationStatus()
        external
        view
        returns (bool offsetExpired, bool restoreExpired)
    {
        return (_isExpired(offsetPhase), _isExpired(restorePhase));
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
            revert UnexpectedLastProcessingRefSlot(
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
        PhaseState storage phaseState
    ) internal view returns (bool ready) {
        if (
            phaseState.executed ||
            _getCurrentSlot() >= phaseState.expirationSlot
        ) {
            return false;
        }
        (ready, ) = _hasExpectedRefSlot(phaseState);
    }

    function _isExpired(
        PhaseState storage phaseState
    ) internal view returns (bool expired) {
        return
            !phaseState.executed &&
            _getCurrentSlot() >= phaseState.expirationSlot;
    }

    function _hasExpectedRefSlot(
        PhaseState storage phaseState
    ) internal view returns (bool matches, uint256 lastProcessingRefSlot) {
        lastProcessingRefSlot = ORACLE.getLastProcessingRefSlot();
        matches = lastProcessingRefSlot == phaseState.expectedProcessingRefSlot;
    }
}
