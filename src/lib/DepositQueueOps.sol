// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAccounting } from "../interfaces/IAccounting.sol";
import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ICSModule } from "../interfaces/ICSModule.sol";
import { IParametersRegistry } from "../interfaces/IParametersRegistry.sol";
import { NodeOperator } from "../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";
import { Batch, DepositQueueLib } from "./DepositQueueLib.sol";
import { TopUpQueueLib, newTopUpQueueItem } from "./TopUpQueueLib.sol";
import { SigningKeys } from "./SigningKeys.sol";

library DepositQueueOps {
    using DepositQueueLib for DepositQueueLib.Queue;
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using TransientUintUintMapLib for TransientUintUintMap;

    struct ObtainDepositDataContext {
        uint256 loadedKeysCount;
        bytes publicKeys;
        bytes signatures;
    }

    function obtainDepositData(
        ModuleLinearStorage.BaseModuleStorage storage $,
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 depositsCount,
        uint256 queueLowestPriority
    ) external returns (bytes memory publicKeys, bytes memory signatures) {
        // Caller guarantees depositsCount > 0.
        ObtainDepositDataContext memory ctx;
        (ctx.publicKeys, ctx.signatures) = SigningKeys.initKeysSigsBuf(depositsCount);

        uint256 depositsLeft = depositsCount;

        // NOTE: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        for (uint256 priority; depositsLeft > 0 && priority <= queueLowestPriority; ++priority) {
            DepositQueueLib.Queue storage depositQueue = $.depositQueueByPriority[priority];
            for (Batch item = depositQueue.peek(); !item.isNil() && depositsLeft > 0; item = depositQueue.peek()) {
                // NOTE: see the `enqueuedCount` note below.
                unchecked {
                    uint32 noId = uint32(item.noId());
                    NodeOperator storage no = $.nodeOperators[noId];

                    uint256 keysInBatch = item.keys();

                    // Keys are bounded by keys in batch and depositable counts (they are uint32 values), so this fits the storage types.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32 keysCount = uint32(
                        Math.min(Math.min(no.depositableValidatorsCount, keysInBatch), depositsLeft)
                    );
                    // `depositsLeft` is non-zero at this point all the time, so the check `depositsLeft > keysCount`
                    // covers the case when no depositable keys on the Node Operator have been left.
                    if (depositsLeft > keysCount || keysCount == keysInBatch) {
                        // NOTE: `enqueuedCount` >= keysInBatch invariant should be checked.
                        // Enqueued counters are uint32 values; `keysInBatch` is sourced
                        // from the same field and thus cannot exceed the range.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        no.enqueuedCount -= uint32(keysInBatch);
                        // We've consumed all the keys in the batch, so we dequeue it.
                        depositQueue.dequeue();
                    } else {
                        // This branch covers the case when we stop in the middle of the batch.
                        // We release the amount of keys consumed only, the rest will be kept.
                        no.enqueuedCount -= keysCount;
                        // NOTE: `keysInBatch` can't be less than `keysCount` at this point.
                        // We update the batch with the remaining keys and store the updated batch back to the queue.
                        depositQueue.queue[depositQueue.head] = item.setKeys(keysInBatch - keysCount);
                    }

                    // NOTE: This condition is located here to allow for the correct removal of the batch for the Node Operators with no depositable keys
                    if (keysCount == 0) continue;
                    _loadAndAccountDeposits({
                        topUpQueue: topUpQueue,
                        no: no,
                        noId: noId,
                        keysCount: keysCount,
                        ctx: ctx
                    });
                    depositsLeft -= keysCount;
                }
            }
        }

        if (ctx.loadedKeysCount != depositsCount) revert IBaseModule.NotEnoughKeys();

        unchecked {
            // Deposits counts are capped by queue length (< 2^32) and the storage slots are uint64.
            // forge-lint: disable-next-line(unsafe-typecast)
            $.depositableValidatorsCount -= uint64(depositsCount);
            // forge-lint: disable-next-line(unsafe-typecast)
            $.totalDepositedValidators += uint64(depositsCount);
        }

        publicKeys = ctx.publicKeys;
        signatures = ctx.signatures;
    }

    function cleanDepositQueue(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 queueLowestPriority,
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth) {
        removed = 0;
        lastRemovedAtDepth = 0;

        if (maxItems == 0) return (0, 0);

        // NOTE: We need one unique hash map per function invocation to be able to track batches of
        // the same operator across multiple queues.
        TransientUintUintMap queueLookup = TransientUintUintMapLib.create();

        DepositQueueLib.Queue storage queue;

        uint256 totalVisited = 0;
        // NOTE: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (priority <= queueLowestPriority) {
            queue = $.depositQueueByPriority[priority];

            (
                uint256 removedPerQueue,
                uint256 lastRemovedAtDepthPerQueue,
                uint256 visitedPerQueue,
                bool reachedOutOfQueue
            ) = _clean(queue, $.nodeOperators, maxItems, queueLookup);

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

                    lastRemovedAtDepth = totalVisited + lastRemovedAtDepthPerQueue;
                    removed += removedPerQueue;
                }
            }

            // NOTE: If we stopped in the middle of a queue, we also stop processing further queues.
            if (!reachedOutOfQueue) break;

            unchecked {
                totalVisited += visitedPerQueue;
                maxItems -= visitedPerQueue;
            }

            unchecked {
                ++priority;
            }
        }
    }

    function enqueueNodeOperatorKeys(
        ModuleLinearStorage.BaseModuleStorage storage $,
        IParametersRegistry parametersRegistry,
        IAccounting accounting,
        uint256 queueLowestPriority,
        uint256 nodeOperatorId
    ) external {
        NodeOperator storage no = $.nodeOperators[nodeOperatorId];
        uint32 depositable = no.depositableValidatorsCount;
        uint32 enqueued = no.enqueuedCount;
        if (depositable <= enqueued) return;

        uint32 toEnqueue;
        unchecked {
            toEnqueue = depositable - enqueued;
        }

        (uint32 priority, uint32 maxDeposits) = parametersRegistry.getQueueConfig(
            accounting.getBondCurveId(nodeOperatorId)
        );
        // If Node Operator is eligible for priority queue, try to enqueue there first.
        if (priority < queueLowestPriority) {
            unchecked {
                uint32 depositedAndQueued = no.totalDepositedKeys + enqueued;
                if (maxDeposits > depositedAndQueued) {
                    uint32 priorityDepositsLeft = maxDeposits - depositedAndQueued;
                    uint32 count = toEnqueue;
                    if (count > priorityDepositsLeft) count = priorityDepositsLeft;

                    _enqueueNodeOperatorKeys({
                        queue: $.depositQueueByPriority[priority],
                        no: no,
                        nodeOperatorId: nodeOperatorId,
                        queuePriority: priority,
                        count: count
                    });
                    toEnqueue -= count;
                }
            }
        }
        if (toEnqueue > 0) {
            _enqueueNodeOperatorKeys({
                queue: $.depositQueueByPriority[queueLowestPriority],
                no: no,
                nodeOperatorId: nodeOperatorId,
                queuePriority: queueLowestPriority,
                count: toEnqueue
            });
        }
    }

    function _clean(
        DepositQueueLib.Queue storage queue,
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 maxItems,
        TransientUintUintMap queueLookup
    ) private returns (uint256 removed, uint256 lastRemovedAtDepth, uint256 visited, bool reachedOutOfQueue) {
        removed = 0;
        lastRemovedAtDepth = 0;
        visited = 0;
        reachedOutOfQueue = false;

        Batch prevItem;
        uint128 indexOfPrev;

        uint128 head = queue.head;
        uint128 curr = head;

        while (visited < maxItems) {
            Batch item = queue.queue[curr];
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
                    queue.dequeue();
                    head = queue.head;
                } else {
                    // There's no `prev` item while we call `dequeue`, and removing an item will keep the `prev` intact
                    // other than changing its `next` field.
                    prevItem = prevItem.setNext(item.next());
                    queue.queue[indexOfPrev] = prevItem;
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

    function _enqueueTopUpKeys(
        TopUpQueueLib.Queue storage topUpQueue,
        uint32 noId,
        uint32 keyIndexBase,
        uint32 keysCount
    ) private {
        for (uint32 i; i < keysCount; i++) {
            topUpQueue.enqueue(
                newTopUpQueueItem(
                    // The ids are assigned sequentially, so noId can't exceed uint32 in practice.
                    noId,
                    keyIndexBase + i
                )
            );
        }
    }

    function _loadAndAccountDeposits(
        TopUpQueueLib.Queue storage topUpQueue,
        NodeOperator storage no,
        uint32 noId,
        uint32 keysCount,
        ObtainDepositDataContext memory ctx
    ) private {
        if (topUpQueue.enabled) {
            _enqueueTopUpKeys(topUpQueue, noId, no.totalDepositedKeys, keysCount);
        }

        SigningKeys.loadKeysSigs({
            nodeOperatorId: noId,
            startIndex: no.totalDepositedKeys,
            keysCount: keysCount,
            pubkeys: ctx.publicKeys,
            signatures: ctx.signatures,
            bufOffset: ctx.loadedKeysCount
        });

        // It's impossible in practice to reach the limit of these variables.
        ctx.loadedKeysCount += keysCount;
        uint32 totalDepositedKeys = no.totalDepositedKeys + keysCount;
        no.totalDepositedKeys = totalDepositedKeys;

        emit IBaseModule.DepositedSigningKeysCountChanged(noId, totalDepositedKeys);

        // No need for `_updateDepositableValidatorsCount` call since we update the number directly.
        uint32 newCount = no.depositableValidatorsCount - keysCount;
        no.depositableValidatorsCount = newCount;
        emit IBaseModule.DepositableSigningKeysCountChanged(noId, newCount);
    }

    // NOTE: If `count` is 0 an empty batch will be created.
    function _enqueueNodeOperatorKeys(
        DepositQueueLib.Queue storage queue,
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 queuePriority,
        uint32 count
    ) private {
        unchecked {
            no.enqueuedCount += count;
        }
        queue.enqueue(nodeOperatorId, count);
        emit ICSModule.BatchEnqueued(queuePriority, nodeOperatorId, count);
    }
}
