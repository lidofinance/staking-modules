// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";
import { Batch, createBatch, QueueLib, IQueueLib } from "src/lib/QueueLib.sol";
import { NodeOperator } from "src/interfaces/IBaseModule.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "src/lib/TransientUintUintMapLib.sol";

// Wrap the library internal methods to make an actual call to them.
// Supposed to be used with `expectRevert` cheatcode and to pass
// calldata arguments.
contract Library {
    using QueueLib for QueueLib.Queue;

    QueueLib.Queue internal q;
    mapping(uint256 => NodeOperator) internal nodeOperators;

    function tail() public view returns (uint128) {
        return q.tail;
    }

    function head() public view returns (uint128) {
        return q.head;
    }

    function enqueue(
        uint256 nodeOperatorId,
        uint256 keysCount
    ) public returns (Batch) {
        return q.enqueue(nodeOperatorId, keysCount);
    }

    function dequeue() public returns (Batch) {
        return q.dequeue();
    }

    function peek() public view returns (Batch) {
        return q.peek();
    }

    function at(uint128 index) public view returns (Batch) {
        return q.at(index);
    }

    function clean(
        uint256 maxItems
    ) external returns (uint256, uint256, uint256, bool) {
        TransientUintUintMap queueLookup = TransientUintUintMapLib.create();
        return q.clean(nodeOperators, maxItems, queueLookup);
    }

    function setNodeOperator(
        uint256 id,
        NodeOperator calldata operatorData
    ) external {
        nodeOperators[id] = operatorData;
    }
}

contract QueueLibTest is Test {
    using { eq } for Batch;

    Library q;
    Batch buf;

    function setUp() public {
        q = new Library();
    }

    function test_createBatch() public pure {
        assertEq(
            createBatch(0x27489e20a0060b72, 0x3a1748bdff5e4457).unwrap(),
            0x27489e20a0060b723a1748bdff5e445700000000000000000000000000000000
        );
    }

    function testFuzz_setKeys(uint64 a, uint64 b, uint64 c) public pure {
        Batch p = createBatch(a, b);
        p = p.setKeys(c);
        assertEq(p.keys(), c);
    }

    function testFuzz_setNext(
        uint64 a,
        uint64 b,
        uint64 c,
        uint64 d
    ) public pure {
        Batch p0 = createBatch(a, b);
        Batch p1 = createBatch(c, d);
        p0 = p0.setNext(p1.next());
        assertEq(p0.next(), p1.next());
    }

    function testFuzz_enqueue(uint64 a, uint64 b, uint64 c, uint64 d) public {
        assertTrue(q.peek().isNil());

        Batch p0 = q.enqueue(a, b);
        Batch p1 = q.enqueue(c, d);

        assertTrue(q.peek().eq(p0));
        assertTrue(q.at(1).eq(p1));

        assertEq(p0.noId(), a);
        assertEq(p0.keys(), b);
        assertEq(p1.noId(), c);
        assertEq(p1.keys(), d);

        assertEq(q.tail(), 2);
    }

    function testFuzz_dequeue(
        uint64 a,
        uint64 b,
        uint64 c,
        uint64 d,
        uint64 e,
        uint64 f
    ) public {
        assertTrue(q.peek().isNil());

        Batch p0 = q.enqueue(a, b);
        Batch p1 = q.enqueue(c, d);
        Batch p2 = q.enqueue(e, f);

        uint128 tail = q.tail();

        assertFalse(q.peek().isNil());

        buf = q.dequeue();
        assertTrue(buf.eq(p0));
        assertTrue(q.peek().eq(p1));
        assertEq(q.tail(), tail);

        buf = q.dequeue();
        assertTrue(buf.eq(p1));
        assertTrue(q.peek().eq(p2));
        assertEq(q.tail(), tail);

        q.dequeue();
        assertTrue(q.peek().isNil());
        assertEq(q.tail(), tail);
    }

    function test_dequeue_revertWhen_QueueIsEmpty() public {
        assertTrue(q.peek().isNil());
        vm.expectRevert(IQueueLib.QueueIsEmpty.selector);
        q.dequeue();
    }

    function test_clean_revertWhen_MaxItemsIsZero() public {
        NodeOperator memory operatorData;
        operatorData.depositableValidatorsCount = 1;
        operatorData.enqueuedCount = 1;
        q.setNodeOperator(1, operatorData);

        vm.expectRevert(IQueueLib.QueueLookupNoLimit.selector);
        q.clean(0);
    }
}

function eq(Batch lhs, Batch rhs) pure returns (bool) {
    return lhs.unwrap() == rhs.unwrap();
}
