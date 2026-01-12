// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

type TopUpQueueItem is uint64;

function newTopUpQueueItem(
    uint32 noId_,
    uint32 keyIndex_
) pure returns (TopUpQueueItem item) {
    assembly ("memory-safe") {
        item := shl(32, noId_)
        item := or(item, keyIndex_)
    }
}

function noId(TopUpQueueItem self) pure returns (uint32 n) {
    assembly ("memory-safe") {
        // Take the first 32 bits.
        n := shr(32, self)
    }
}

function keyIndex(TopUpQueueItem self) pure returns (uint32 n) {
    assembly ("memory-safe") {
        // Downcast to uint32 leaves the last 32 bits only.
        n := self
    }
}

function unwrap(TopUpQueueItem self) pure returns (uint64) {
    return TopUpQueueItem.unwrap(self);
}

using { noId, keyIndex, unwrap } for TopUpQueueItem global;

interface ITopUpQueueLib {
    error TopUpQueueIsEmpty();
    error TopUpQueueIsFull();
}

library TopUpQueueLib {
    using TopUpQueueLib for Queue;

    struct Queue {
        TopUpQueueItem[] items;
        uint32 limit;
        uint32 head;
        bool active;
    }

    function enqueue(Queue storage self, TopUpQueueItem item) internal {
        if (self.capacity() == 0) {
            revert ITopUpQueueLib.TopUpQueueIsFull();
        }

        self.items.push(item);
    }

    function dequeue(Queue storage self) internal {
        if (self.length() == 0) {
            revert ITopUpQueueLib.TopUpQueueIsEmpty();
        }

        // NOTE: Zeroing out the storage slot, since it's unreachable after `dequeue`.
        self.items[self.head] = TopUpQueueItem.wrap(0x00);
        self.head++;
    }

    function capacity(Queue storage self) internal view returns (uint256) {
        uint256 len = self.length();
        if (self.limit > len) {
            unchecked {
                return self.limit - len;
            }
        }

        return 0;
    }

    function length(Queue storage self) internal view returns (uint256) {
        return self.items.length - self.head;
    }

    function at(
        Queue storage self,
        uint256 index
    ) internal view returns (TopUpQueueItem) {
        index = self.head + index;
        return self.items[index];
    }
}
