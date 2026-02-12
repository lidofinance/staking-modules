// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test, stdError } from "forge-std/Test.sol";

import { TopUpQueueLib, TopUpQueueItem, newTopUpQueueItem, ITopUpQueueLib } from "src/lib/TopUpQueueLib.sol";

import { Utilities } from "../../helpers/Utilities.sol";

contract Library {
    using TopUpQueueLib for TopUpQueueLib.Queue;

    TopUpQueueLib.Queue internal q;

    function setLimit(uint8 limit) external {
        q.limit = limit;
    }

    function enqueue(TopUpQueueItem item) external {
        q.enqueue(item);
    }

    function dequeue() external {
        q.dequeue();
    }

    function rewind(uint32 to) external {
        q.rewind(to);
    }

    function at(uint256 index) external view returns (TopUpQueueItem) {
        return q.at(index);
    }

    function length() external view returns (uint256) {
        return q.length();
    }

    function capacity() external view returns (uint256) {
        return q.capacity();
    }
}

contract TopUpQueueLibTest is Test, Utilities {
    using { eq } for TopUpQueueItem;

    Library internal q;
    TopUpQueueItem internal buf;

    function setUp() public {
        q = new Library();
    }

    function test_newTopUpQueueItem() public {
        assertEq(newTopUpQueueItem(0xbfd25afa, 0xb99a6659).unwrap(), 0xbfd25afab99a6659);
    }

    function testFuzz_packAndUnpack(uint32 noId, uint32 keyIndex) public {
        buf = newTopUpQueueItem(noId, keyIndex);
        assertEq(buf.noId(), noId);
        assertEq(buf.keyIndex(), keyIndex);
    }

    function testFuzz_enqueue(TopUpQueueItem a, TopUpQueueItem b, TopUpQueueItem c) public {
        vm.assume(!a.eq(b));
        vm.assume(!b.eq(c));
        vm.assume(!a.eq(c));

        q.setLimit(3);

        q.enqueue(a);
        q.enqueue(b);
        q.enqueue(c);

        assertTrue(q.at(0).eq(a));
        q.dequeue();

        assertTrue(q.at(0).eq(b));
        q.dequeue();

        assertTrue(q.at(0).eq(c));
        q.dequeue();
    }

    function test_enqueue_RevertWhenQueueIsFull() public {
        q.setLimit(1);
        q.enqueue(buf);

        vm.expectRevert(ITopUpQueueLib.TopUpQueueIsFull.selector);
        q.enqueue(buf);
    }

    function test_dequeue_RevertWhenQueueEmpty() public {
        vm.expectRevert(ITopUpQueueLib.TopUpQueueIsEmpty.selector);
        q.dequeue();
    }

    function test_rewind() public {
        TopUpQueueItem i0 = TopUpQueueItem.wrap(0x11);
        TopUpQueueItem i1 = TopUpQueueItem.wrap(0x13);
        TopUpQueueItem i2 = TopUpQueueItem.wrap(0x17);

        q.setLimit(3);

        q.enqueue(i0);
        q.enqueue(i1);
        q.enqueue(i2);

        q.dequeue();
        assertEq(q.length(), 2);

        q.rewind(0);
        assertEq(q.length(), 3);
        assertTrue(q.at(0).eq(i0));

        q.dequeue();
        q.dequeue();
        q.dequeue();
        assertEq(q.length(), 0);

        q.rewind(1);
        assertEq(q.length(), 2);
        assertTrue(q.at(0).eq(i1));
    }

    function test_rewind_RevertWhenRewindForward() public {
        q.setLimit(3);

        vm.expectRevert(ITopUpQueueLib.RewindForward.selector);
        q.rewind(0);

        q.enqueue(buf); // 0
        q.enqueue(buf); // 1
        q.enqueue(buf); // 2
        q.dequeue();

        for (uint32 to = 1; to < 3; ++to) {
            vm.expectRevert(ITopUpQueueLib.RewindForward.selector);
            q.rewind(to);
        }
    }

    function test_length() public {
        q.setLimit(3);

        assertEq(q.length(), 0);

        q.enqueue(buf);
        assertEq(q.length(), 1);

        q.enqueue(buf);
        assertEq(q.length(), 2);

        q.dequeue();
        assertEq(q.length(), 1);

        q.dequeue();
        assertEq(q.length(), 0);
    }

    function testFuzz_at(TopUpQueueItem a, TopUpQueueItem b, TopUpQueueItem c) public {
        q.setLimit(3);
        q.enqueue(a);
        q.enqueue(b);
        q.enqueue(c);

        assertTrue(a.eq(q.at(0)));
        assertTrue(b.eq(q.at(1)));
        assertTrue(c.eq(q.at(2)));
    }

    function test_at_RevertWhenOutOfBoundary() public {
        q.setLimit(3);
        q.enqueue(buf);

        vm.expectRevert(stdError.indexOOBError);
        q.at(1);

        q.dequeue();

        vm.expectRevert(stdError.indexOOBError);
        q.at(0);
    }

    function test_capacity() public {
        assertEq(q.capacity(), 0);

        q.setLimit(2);
        assertEq(q.capacity(), 2);

        q.enqueue(buf);
        assertEq(q.capacity(), 1);

        q.enqueue(buf);
        assertEq(q.capacity(), 0);

        q.setLimit(5);
        assertEq(q.capacity(), 3);

        q.setLimit(1);
        assertEq(q.capacity(), 0);
    }
}

function eq(TopUpQueueItem a, TopUpQueueItem b) pure returns (bool) {
    return a.unwrap() == b.unwrap();
}
