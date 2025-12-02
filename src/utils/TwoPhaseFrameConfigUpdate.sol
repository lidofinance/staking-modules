// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IReportAsyncProcessor } from "../lib/base-oracle/interfaces/IReportAsyncProcessor.sol";
import { IConsensusContract } from "../lib/base-oracle/interfaces/IConsensusContract.sol";

/// @notice A helper to offset CSM Oracle report cadence (e.g., move report window by N slots).
///         This is achieved via a two-phase frame configuration update
///         in `HashConsensus` contract used by `CSFeeOracle`.
///         Phase2 cannot be executed until Phase1 is completed.
/// @dev The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted in the
///      `HashConsensus` contract in order to be able to call `setFrameConfig`.
///      The role should be revoked after both phases are executed.
contract TwoPhaseFrameConfigUpdate {
    struct PhaseConfig {
        /// @notice Number of reports that must be processed by the oracle
        ///         to enable this phase execution.
        ///         For phase1: from `lastProcessingRefSlot` at deployment time.
        ///         For phase2: from phase1 completion.
        uint256 reportsToProcess;
        uint256 newEpochsPerFrame;
        uint256 newFastLaneLengthSlots;
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
        uint256 newEpochsPerFrame;
        uint256 newFastLaneLengthSlots;
        bool executed;
    }

    IReportAsyncProcessor public immutable FEE_ORACLE;
    IConsensusContract public immutable HASH_CONSENSUS;

    PhaseState public phase1;
    PhaseState public phase2;

    event Phase1Executed();
    event Phase2Executed();

    error ZeroFeeOracleAddress();
    error ZeroEpochsPerFrame();
    error ZeroReportsPassedToEnableUpdate();
    error ZeroFromRefSlot();
    error Phase1AlreadyExecuted();
    error Phase2AlreadyExecuted();
    error Phase1NotExecuted();
    error PhaseExpired(uint256 currentRefSlot, uint256 deadlineRefSlot);
    error UnexpectedRefSlot(uint256 expected, uint256 actual);

    constructor(
        address feeOracle,
        PhaseConfig memory phase1Config,
        PhaseConfig memory phase2Config
    ) {
        if (feeOracle == address(0)) {
            revert ZeroFeeOracleAddress();
        }

        if (phase1Config.reportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phase2Config.reportsToProcess == 0) {
            revert ZeroReportsPassedToEnableUpdate();
        }

        if (phase1Config.newEpochsPerFrame == 0) {
            revert ZeroEpochsPerFrame();
        }

        if (phase2Config.newEpochsPerFrame == 0) {
            revert ZeroEpochsPerFrame();
        }

        FEE_ORACLE = IReportAsyncProcessor(feeOracle);
        HASH_CONSENSUS = IConsensusContract(FEE_ORACLE.getConsensusContract());

        (uint256 slotsPerEpoch, , ) = HASH_CONSENSUS.getChainConfig();
        (, uint256 currentEpochsPerFrame, ) = HASH_CONSENSUS.getFrameConfig();
        uint256 lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();

        if (lastProcessingRefSlot == 0) {
            revert ZeroFromRefSlot();
        }

        // Calculate pivot ref slot for phase 1 (based on last processing ref slot at deployment time)
        uint256 phase1ExpectedProcessingRefSlot = lastProcessingRefSlot +
            (phase1Config.reportsToProcess *
                currentEpochsPerFrame *
                slotsPerEpoch);

        // Calculate deadline for phase 1 (before next original frame report processing or next frame with new possible config)
        uint256 minPhase1EpochsPerFrame = currentEpochsPerFrame <
            phase1Config.newEpochsPerFrame
            ? currentEpochsPerFrame
            : phase1Config.newEpochsPerFrame;
        uint256 phase1ExpirationSlot = phase1ExpectedProcessingRefSlot +
            (minPhase1EpochsPerFrame * slotsPerEpoch);

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= phase1ExpirationSlot) {
            revert PhaseExpired(currentSlot, phase1ExpirationSlot);
        }

        // Calculate pivot ref slot for phase 2 (based on phase 1 completion)
        uint256 phase2ExpectedProcessingRefSlot = phase1ExpectedProcessingRefSlot +
                (phase2Config.reportsToProcess *
                    phase1Config.newEpochsPerFrame *
                    slotsPerEpoch);

        // Calculate deadline for phase 2 (before next phase 1 frame report processing or next possible frame with new config)
        uint256 minPhase2EpochsPerFrame = phase1Config.newEpochsPerFrame <
            phase2Config.newEpochsPerFrame
            ? phase1Config.newEpochsPerFrame
            : phase2Config.newEpochsPerFrame;
        uint256 phase2ExpirationSlot = phase2ExpectedProcessingRefSlot +
            (minPhase2EpochsPerFrame * slotsPerEpoch);

        phase1 = PhaseState({
            expectedProcessingRefSlot: phase1ExpectedProcessingRefSlot,
            expirationSlot: phase1ExpirationSlot,
            newEpochsPerFrame: phase1Config.newEpochsPerFrame,
            newFastLaneLengthSlots: phase1Config.newFastLaneLengthSlots,
            executed: false
        });

        phase2 = PhaseState({
            expectedProcessingRefSlot: phase2ExpectedProcessingRefSlot,
            expirationSlot: phase2ExpirationSlot,
            newEpochsPerFrame: phase2Config.newEpochsPerFrame,
            newFastLaneLengthSlots: phase2Config.newFastLaneLengthSlots,
            executed: false
        });
    }

    /// @dev Can only be called when oracle is at the expected pivot ref slot for phase 1.
    function executePhase1() external {
        _validatePhaseExecution(phase1, true);

        HASH_CONSENSUS.setFrameConfig(
            phase1.newEpochsPerFrame,
            phase1.newFastLaneLengthSlots
        );

        phase1.executed = true;
        emit Phase1Executed();
    }

    /// @dev Can only be called after phase1 is executed and when oracle is at the expected pivot ref slot for phase 2.
    function executePhase2() external {
        _validatePhaseExecution(phase2, false);

        HASH_CONSENSUS.setFrameConfig(
            phase2.newEpochsPerFrame,
            phase2.newFastLaneLengthSlots
        );

        phase2.executed = true;
        emit Phase2Executed();

        _renounceRole();
    }

    /// @dev Fallback to renounce the role if phases are expired.
    function renounceRoleWhenExpired() external {
        bool phase1Expired = _isPhaseExpired(phase1);
        bool phase2Expired = _isPhaseExpired(phase2);
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
        return _isPhaseReady(phase1, true);
    }

    function isReadyForPhase2() external view returns (bool ready) {
        return _isPhaseReady(phase2, false);
    }

    function getExpirationStatus()
        external
        view
        returns (bool phase1Expired, bool phase2Expired)
    {
        return (_isPhaseExpired(phase1), _isPhaseExpired(phase2));
    }

    function _getCurrentSlot() internal view returns (uint256 currentSlot) {
        (, uint256 secondsPerSlot, uint256 genesisTime) = HASH_CONSENSUS
            .getChainConfig();
        return (block.timestamp - genesisTime) / secondsPerSlot;
    }

    function _validatePhaseExecution(
        PhaseState storage phaseState,
        bool isPhase1
    ) internal view {
        if (isPhase1 && phase1.executed) {
            revert Phase1AlreadyExecuted();
        }
        if (!isPhase1) {
            if (!phase1.executed) {
                revert Phase1NotExecuted();
            }
            if (phase2.executed) {
                revert Phase2AlreadyExecuted();
            }
        }

        uint256 lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();
        if (lastProcessingRefSlot != phaseState.expectedProcessingRefSlot) {
            revert UnexpectedRefSlot(
                phaseState.expectedProcessingRefSlot,
                lastProcessingRefSlot
            );
        }

        uint256 currentSlot = _getCurrentSlot();
        if (currentSlot >= phaseState.expirationSlot) {
            revert PhaseExpired(currentSlot, phaseState.expirationSlot);
        }
    }

    function _isPhaseReady(
        PhaseState storage phaseState,
        bool isPhase1
    ) internal view returns (bool ready) {
        if (phaseState.executed) {
            return false;
        }

        if (!isPhase1 && !phase1.executed) {
            return false;
        }

        uint256 lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();
        uint256 currentSlot = _getCurrentSlot();

        return
            lastProcessingRefSlot == phaseState.expectedProcessingRefSlot &&
            currentSlot < phaseState.expirationSlot;
    }

    function _isPhaseExpired(
        PhaseState storage phaseState
    ) internal view returns (bool expired) {
        return
            !phaseState.executed &&
            _getCurrentSlot() >= phaseState.expirationSlot;
    }
}
