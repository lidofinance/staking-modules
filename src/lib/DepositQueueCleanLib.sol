// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "../interfaces/IBaseModule.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";
import { Batch, DepositQueueLib, IDepositQueueLib } from "./DepositQueueLib.sol";

library DepositQueueCleanLib {
    using DepositQueueLib for DepositQueueLib.Queue;
    using TransientUintUintMapLib for TransientUintUintMap;

    function cleanDepositQueue(
        mapping(uint256 => DepositQueueLib.Queue)
            storage depositQueueByPriority,
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 queueLowestPriority,
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth) {
        removed = 0;
        lastRemovedAtDepth = 0;

        if (maxItems == 0) {
            return (0, 0);
        }

        // NOTE: We need one unique hash map per function invocation to be able to track batches of
        // the same operator across multiple queues.
        TransientUintUintMap queueLookup = TransientUintUintMapLib.create();

        DepositQueueLib.Queue storage queue;

        uint256 totalVisited = 0;
        // NOTE: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > queueLowestPriority) {
                break;
            }

            queue = depositQueueByPriority[priority];
            unchecked {
                ++priority;
            }

            (
                uint256 removedPerQueue,
                uint256 lastRemovedAtDepthPerQueue,
                uint256 visitedPerQueue,
                bool reachedOutOfQueue
            ) = _clean(queue, nodeOperators, maxItems, queueLookup);

            if (removedPerQueue > 0) {
                unchecked {
                    // 1234 56 789A     <- cumulative depth (A=10)
                    // 1234 12 1234     <- depth per queue
                    // **R*|**|**R*     <- queue with [R]emoved elements
                    //
                    // Given that we observed all 3 queues:
                    // totalVisited: 4+2=6
                    // lastRemovedAtDepthPerQueue: 3
                    // lastRemovedAtDepth: 6+3=9

                    lastRemovedAtDepth =
                        totalVisited +
                        lastRemovedAtDepthPerQueue;
                    removed += removedPerQueue;
                }
            }

            // NOTE: If `maxItems` is set to the total length of the queue(s), `reachedOutOfQueue` is equal
            // to `false`, effectively breaking the cycle, because in `QueueLib.clean` we don't reach
            // an empty batch after the end of a queue.
            if (!reachedOutOfQueue) {
                break;
            }

            unchecked {
                totalVisited += visitedPerQueue;
                maxItems -= visitedPerQueue;
            }
        }
    }

    function _clean(
        DepositQueueLib.Queue storage self,
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 maxItems,
        TransientUintUintMap queueLookup
    )
        private
        returns (
            uint256 removed,
            uint256 lastRemovedAtDepth,
            uint256 visited,
            bool reachedOutOfQueue
        )
    {
        removed = 0;
        lastRemovedAtDepth = 0;
        visited = 0;
        reachedOutOfQueue = false;

        if (maxItems == 0) {
            revert IDepositQueueLib.DepositQueueLookupNoLimit();
        }

        Batch prevItem;
        uint128 indexOfPrev;

        uint128 head = self.head;
        uint128 curr = head;

        while (visited < maxItems) {
            Batch item = self.queue[curr];
            if (item.isNil()) {
                reachedOutOfQueue = true;
                break;
            }

            visited++;

            NodeOperator storage no = nodeOperators[item.noId()];
            if (queueLookup.get(item.noId()) >= no.depositableValidatorsCount) {
                // NOTE: Since we reached that point there's no way for a Node Operator to have a depositable batch
                // later in the queue, and hence we don't update _queueLookup for the Node Operator.
                if (curr == head) {
                    self.dequeue();
                    head = self.head;
                } else {
                    // There's no `prev` item while we call `dequeue`, and removing an item will keep the `prev` intact
                    // other than changing its `next` field.
                    prevItem = prevItem.setNext(item.next());
                    self.queue[indexOfPrev] = prevItem;
                }

                // We assume that the invariant `enqueuedCount` >= `keys` is kept.
                // NOTE: No need to safe cast due to internal logic.
                no.enqueuedCount -= uint32(item.keys());

                unchecked {
                    lastRemovedAtDepth = visited;
                    ++removed;
                }
            } else {
                queueLookup.add(item.noId(), item.keys());
                indexOfPrev = curr;
                prevItem = item;
            }

            curr = item.next();
        }
    }
}
