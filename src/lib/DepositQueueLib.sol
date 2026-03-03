// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

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
            and(self, 0xffffffffffffffff0000000000000000ffffffffffffffffffffffffffffffff),
            shl(128, and(keysCount, 0xffffffffffffffff))
        ) // self.keys = keysCount
    }

    return self;
}

/// @dev can be unsafe if the From batch is previous to the self
function setNext(Batch self, uint128 nextIndex) pure returns (Batch) {
    assembly {
        self := or(and(self, 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000), nextIndex) // self.next = next
    }
    return self;
}

/// @dev Instantiate a new Batch to be added to the queue. The `next` field will be determined upon the enqueue.
/// @dev Parameters are uint256 to make usage easier.
function createBatch(uint256 nodeOperatorId, uint256 keysCount) pure returns (Batch item) {
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
using DepositQueueLib for DepositQueueLib.Queue;

/// @dev Helps expose the errors to the ICSModule interface.
interface IDepositQueueLib {
    error DepositQueueIsEmpty();
}

/// @author madlabman
library DepositQueueLib {
    struct Queue {
        // Pointer to the item to be dequeued.
        uint128 head;
        // Tracks the index to enqueue an item to.
        uint128 tail;
        // Mapping saves a little in costs and allows easily fallback to a zeroed batch on out-of-bounds access.
        mapping(uint128 => Batch) queue;
    }

    //////
    /// External methods
    //////

    /////
    /// Internal methods
    /////
    function enqueue(Queue storage self, uint256 nodeOperatorId, uint256 keysCount) internal returns (Batch item) {
        uint128 tail = self.tail;
        item = createBatch(nodeOperatorId, keysCount);

        assembly {
            item := or(and(item, 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000), add(tail, 1)) // item.next = self.tail + 1;
        }

        self.queue[tail] = item;
        unchecked {
            ++self.tail;
        }
    }

    function dequeue(Queue storage self) internal returns (Batch item) {
        item = peek(self);

        if (item.isNil()) revert IDepositQueueLib.DepositQueueIsEmpty();

        self.head = item.next();
    }

    function peek(Queue storage self) internal view returns (Batch) {
        return self.queue[self.head];
    }

    function at(Queue storage self, uint128 index) internal view returns (Batch) {
        return self.queue[index];
    }
}
