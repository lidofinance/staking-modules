// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "../interfaces/IBaseModule.sol";
import { IAccounting } from "../interfaces/IAccounting.sol";
import { IParametersRegistry } from "../interfaces/IParametersRegistry.sol";

import { DepositQueueLib } from "./DepositQueueLib.sol";

/// @dev The library is used to reduce CSModule bytecode size.
interface IOperatorDepositableChangeLib {
    event BatchEnqueued(
        uint256 indexed queuePriority,
        uint256 indexed nodeOperatorId,
        uint256 count
    );
}

library OperatorDepositableChangeLib {
    using DepositQueueLib for DepositQueueLib.Queue;

    function onOperatorDepositableChange(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        mapping(uint256 => DepositQueueLib.Queue) storage depositQueues,
        IParametersRegistry parametersRegistry,
        IAccounting accounting,
        uint256 queueLowestPriority,
        uint256 nodeOperatorId
    ) external {
        NodeOperator storage no = nodeOperators[nodeOperatorId];
        uint32 depositable = no.depositableValidatorsCount;
        uint32 enqueued = no.enqueuedCount;
        if (depositable <= enqueued) {
            return;
        }

        uint32 toEnqueue;
        unchecked {
            toEnqueue = depositable - enqueued;
        }

        (uint32 priority, uint32 maxDeposits) = parametersRegistry
            .getQueueConfig(accounting.getBondCurveId(nodeOperatorId));
        if (priority < queueLowestPriority) {
            unchecked {
                uint32 depositedAndQueued = no.totalDepositedKeys + enqueued;
                if (maxDeposits > depositedAndQueued) {
                    uint32 priorityDepositsLeft = maxDeposits -
                        depositedAndQueued;
                    uint32 count = toEnqueue;
                    if (count > priorityDepositsLeft) {
                        count = priorityDepositsLeft;
                    }

                    // solhint-disable-next-line func-named-parameters
                    _enqueueNodeOperatorKeys(
                        no,
                        depositQueues[priority],
                        nodeOperatorId,
                        priority,
                        count
                    );
                    toEnqueue -= count;
                }
            }
        }

        if (toEnqueue > 0) {
            // solhint-disable-next-line func-named-parameters
            _enqueueNodeOperatorKeys(
                no,
                depositQueues[queueLowestPriority],
                nodeOperatorId,
                queueLowestPriority,
                toEnqueue
            );
        }
    }

    // NOTE: If `count` is 0 an empty batch will be created.
    function _enqueueNodeOperatorKeys(
        NodeOperator storage no,
        DepositQueueLib.Queue storage queue,
        uint256 nodeOperatorId,
        uint256 queuePriority,
        uint32 count
    ) private {
        unchecked {
            no.enqueuedCount += count;
        }
        queue.enqueue(nodeOperatorId, count);
        emit IOperatorDepositableChangeLib.BatchEnqueued(
            queuePriority,
            nodeOperatorId,
            count
        );
    }
}
