// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { IReportAsyncProcessor } from "../lib/base-oracle/interfaces/IReportAsyncProcessor.sol";
import { IConsensusContract } from "../lib/base-oracle/interfaces/IConsensusContract.sol";

/// @notice Helper to perform sequential updates of the frame configuration
///        in the HashConsensus contract used by the CSFeeOracle.
///        It helps to safely change the frame configuration on expected oracle report,
///        ensuring that there is no missing frame(s) during the update.
/// @dev The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted in the
///      HashConsensus contract in order to be able to call `setFrameConfig`.
///      The role should be revoked after all planned updates are executed.
contract FrameConfigUpdateQueue {
    struct FrameConfigUpdateInput {
        uint256 pivotRefSlot;
        uint256 newEpochsPerFrame;
        uint256 newFastLaneLengthSlots;
    }

    struct FrameConfigUpdate {
        uint256 pivotRefSlot;
        uint256 newEpochsPerFrame;
        uint256 newFastLaneLengthSlots;
        bool executed;
    }

    IReportAsyncProcessor public immutable FEE_ORACLE;
    IConsensusContract public immutable HASH_CONSENSUS;

    FrameConfigUpdate[] public frameConfigUpdateQueue;

    event FrameConfigUpdateExecuted(uint256 updateIndex);

    error ZeroFeeOracleAddress();
    error ZeroPivotRefSlot();
    error ZeroEpochsPerFrame();
    error InconsistentUpdateQueue(
        uint256 prevPivotRefSlot,
        uint256 nextPivotRefSlot
    );

    error InvalidUpdateIndex();
    error AlreadyExecuted();
    error PreviousNotExecuted();
    error UnexpectedRefSlot(uint256 expected, uint256 actual);

    constructor(
        address feeOracle,
        FrameConfigUpdateInput[] memory frameConfigUpdateInputs
    ) {
        if (feeOracle == address(0)) {
            revert ZeroFeeOracleAddress();
        }

        for (uint256 i = 0; i < frameConfigUpdateInputs.length; i++) {
            FrameConfigUpdateInput memory input = frameConfigUpdateInputs[i];

            if (input.pivotRefSlot == 0) {
                revert ZeroPivotRefSlot();
            }

            if (input.newEpochsPerFrame == 0) {
                revert ZeroEpochsPerFrame();
            }

            if (i > 0) {
                uint256 prevPivotRefSlot = frameConfigUpdateInputs[i - 1]
                    .pivotRefSlot;
                if (prevPivotRefSlot >= input.pivotRefSlot) {
                    revert InconsistentUpdateQueue(
                        prevPivotRefSlot,
                        input.pivotRefSlot
                    );
                }
            }

            frameConfigUpdateQueue.push(
                FrameConfigUpdate({
                    pivotRefSlot: input.pivotRefSlot,
                    newEpochsPerFrame: input.newEpochsPerFrame,
                    newFastLaneLengthSlots: input.newFastLaneLengthSlots,
                    executed: false
                })
            );
        }

        FEE_ORACLE = IReportAsyncProcessor(feeOracle);
        HASH_CONSENSUS = IConsensusContract(FEE_ORACLE.getConsensusContract());
    }

    function executeUpdate(uint256 updateIndex) external {
        if (updateIndex >= _getFrameConfigUpdateQueueLength()) {
            revert InvalidUpdateIndex();
        }

        if (updateIndex > 0) {
            FrameConfigUpdate storage prevUpdate = frameConfigUpdateQueue[
                updateIndex - 1
            ];
            if (!prevUpdate.executed) {
                revert PreviousNotExecuted();
            }
        }

        FrameConfigUpdate storage update = frameConfigUpdateQueue[updateIndex];

        if (update.executed) {
            revert AlreadyExecuted();
        }

        uint256 lastProcessingRefSlot = FEE_ORACLE.getLastProcessingRefSlot();

        if (lastProcessingRefSlot != update.pivotRefSlot) {
            revert UnexpectedRefSlot(
                update.pivotRefSlot,
                lastProcessingRefSlot
            );
        }

        HASH_CONSENSUS.setFrameConfig(
            update.newEpochsPerFrame,
            update.newFastLaneLengthSlots
        );

        update.executed = true;
        emit FrameConfigUpdateExecuted(updateIndex);
    }

    function getFrameConfigUpdate(
        uint256 index
    ) external view returns (FrameConfigUpdate memory) {
        if (index >= _getFrameConfigUpdateQueueLength()) {
            revert InvalidUpdateIndex();
        }
        return frameConfigUpdateQueue[index];
    }

    function getFrameConfigUpdateQueueLength() external view returns (uint256) {
        return _getFrameConfigUpdateQueueLength();
    }

    function _getFrameConfigUpdateQueueLength()
        internal
        view
        returns (uint256)
    {
        return frameConfigUpdateQueue.length;
    }
}
