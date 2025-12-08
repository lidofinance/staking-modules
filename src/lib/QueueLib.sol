// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { TransientUintUintMap } from "./TransientUintUintMapLib.sol";
import { NodeOperator } from "../interfaces/IBaseModule.sol";

// Batch is an uint256 as it's the internal data type used by solidity.
// Batch is a packed value, consisting of the following fields:
//    - uint64  nodeOperatorId
//    - uint64  keysCount -- count of keys enqueued by the batch
//    - uint128 next -- index of the next batch in the queue
type Batch is uint256;

/// @notice Batch of the operator with index 0, with no keys in it and the next Batch' index 0 is meaningless.
function isNil(Batch self) pure returns (bool) {
    return Batch.unwrap(self) == 0;
}

/// @dev Syntactic sugar for the type.
function unwrap(Batch self) pure returns (uint256) {
    return Batch.unwrap(self);
}

function noId(Batch self) pure returns (uint64 n) {
    assembly {
        n := shr(192, self)
    }
}

function keys(Batch self) pure returns (uint64 n) {
    assembly {
        n := shl(64, self)
        n := shr(192, n)
    }
}

function next(Batch self) pure returns (uint128 n) {
    assembly {
        n := shl(128, self)
        n := shr(128, n)
    }
}

/// @dev keys count cast is unsafe
function setKeys(Batch self, uint256 keysCount) pure returns (Batch) {
    assembly {
        self := or(
            and(
                self,
                0xffffffffffffffff0000000000000000ffffffffffffffffffffffffffffffff
            ),
            shl(128, and(keysCount, 0xffffffffffffffff))
        ) // self.keys = keysCount
    }

    return self;
}

/// @dev can be unsafe if the From batch is previous to the self
function setNext(Batch self, uint128 nextIndex) pure returns (Batch) {
    assembly {
        self := or(
            and(
                self,
                0xffffffffffffffffffffffffffffffff00000000000000000000000000000000
            ),
            nextIndex
        ) // self.next = next
    }
    return self;
}

/// @dev Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.
/// @dev Parameters are uint256 to make usage easier.
function createBatch(
    uint256 nodeOperatorId,
    uint256 keysCount
) pure returns (Batch item) {
    // Queue slots reserve 64 bits for node operator IDs; upstream module numbers are capped well
    // below that limit, so truncation cannot occur.
    // forge-lint: disable-next-line(unsafe-typecast)
    nodeOperatorId = uint64(nodeOperatorId);
    // Keys per batch are also capped by module key pointers (uint32), so they comfortably fit 64 bits.
    // forge-lint: disable-next-line(unsafe-typecast)
    keysCount = uint64(keysCount);

    assembly {
        item := shl(128, keysCount) // `keysCount` in [64:127]
        item := or(item, shl(192, nodeOperatorId)) // `nodeOperatorId` in [0:63]
    }
}

using { noId, keys, setKeys, setNext, next, isNil, unwrap } for Batch global;
using QueueLib for QueueLib.Queue;

/// @dev Helps expose the errors to the ICSModule interface.
interface IQueueLib {
    error QueueIsEmpty();
    error QueueLookupNoLimit();
}

/// @author madlabman
library QueueLib {
    struct Queue {
        // Pointer to the item to be dequeued.
        uint128 head;
        // Tracks the total number of batches ever enqueued.
        uint128 tail;
        // Mapping saves a little in costs and allows easily fallback to a zeroed batch on out-of-bounds access.
        mapping(uint128 => Batch) queue;
    }

    //////
    /// External methods
    //////

    function clean(
        Queue storage self,
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 maxItems,
        TransientUintUintMap queueLookup
    )
        external
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
            revert IQueueLib.QueueLookupNoLimit();
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

    /////
    /// Internal methods
    /////
    function enqueue(
        Queue storage self,
        uint256 nodeOperatorId,
        uint256 keysCount
    ) internal returns (Batch item) {
        uint128 tail = self.tail;
        item = createBatch(nodeOperatorId, keysCount);

        assembly {
            item := or(
                and(
                    item,
                    0xffffffffffffffffffffffffffffffff00000000000000000000000000000000
                ),
                add(tail, 1)
            ) // item.next = self.tail + 1;
        }

        self.queue[tail] = item;
        unchecked {
            ++self.tail;
        }
    }

    function dequeue(Queue storage self) internal returns (Batch item) {
        item = peek(self);

        if (item.isNil()) {
            revert IQueueLib.QueueIsEmpty();
        }

        self.head = item.next();
    }

    function peek(Queue storage self) internal view returns (Batch) {
        return self.queue[self.head];
    }

    function at(
        Queue storage self,
        uint128 index
    ) internal view returns (Batch) {
        return self.queue[index];
    }
}
