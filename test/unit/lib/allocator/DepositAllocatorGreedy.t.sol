// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { AllocationState, DepositAllocatorGreedy } from "src/lib/allocator/DepositAllocatorGreedy.sol";

contract DepositAllocatorGreedyTest is Test {
    uint256 internal constant S_SCALE = uint256(1) << 96;
    DepositAllocatorGreedyHarness internal harness;

    function setUp() public {
        harness = new DepositAllocatorGreedyHarness();
    }

    function test_allocate_singleDemand() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(10, 0);
        uint256[] memory caps = _arr2(10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 2, 1);

        assertEq(allocated, 2);
        assertEq(fills[0], 0);
        assertEq(fills[1], 2);
    }

    function test_allocate_capStopsTopImbalance() public {
        uint256[] memory weights = _arr3(5, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(1, 10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 7, 1);

        assertEq(fills[0], 1);
        assertEq(fills[1], 1);
        assertEq(fills[2], 1);
        assertEq(allocated, 3);
    }

    function test_allocate_greedyTopImbalance() public {
        uint256[] memory weights = _arr4(1, 1, 1, 1);
        uint256[] memory amounts = _arr4(19, 21, 23, 32);
        uint256[] memory caps = _arr4(100, 100, 100, 100);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 5, 1);

        assertEq(allocated, 5);
        // Greedy allocator gives all inflow to the most underfilled bucket.
        assertEq(fills[0], 5);
        assertEq(fills[1], 0);
        assertEq(fills[2], 0);
        assertEq(fills[3], 0);
    }

    function test_invariants_negativeImbalanceNoFill() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(100, 0);
        uint256[] memory caps = _arr2(100, 100);

        (, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 10, 1);

        assertEq(fills[0], 0);
    }

    function testFuzz_invariants_sumAndCaps(
        uint256 w0,
        uint256 w1,
        uint256 w2,
        uint256 a0,
        uint256 a1,
        uint256 a2,
        uint256 c0,
        uint256 c1,
        uint256 c2,
        uint256 inflow,
        uint256 step
    ) public {
        w0 = bound(w0, 0, type(uint128).max);
        w1 = bound(w1, 0, type(uint128).max);
        w2 = bound(w2, 0, type(uint128).max);
        a0 = bound(a0, 0, type(uint128).max);
        a1 = bound(a1, 0, type(uint128).max);
        a2 = bound(a2, 0, type(uint128).max);
        c0 = bound(c0, 0, type(uint128).max);
        c1 = bound(c1, 0, type(uint128).max);
        c2 = bound(c2, 0, type(uint128).max);
        inflow = bound(inflow, 0, type(uint128).max);
        step = bound(step, 1, type(uint64).max);

        uint256[] memory weights = _arr3(w0, w1, w2);
        uint256[] memory amounts = _arr3(a0, a1, a2);
        uint256[] memory caps = _arr3(c0, c1, c2);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, inflow, step);

        assertEq(_sum(fills), allocated);
        assertLe(allocated, inflow);
        for (uint256 i; i < fills.length; ++i) {
            assertLe(fills[i], caps[i]);
        }
    }

    function test_edge_noOperators() public {
        uint256[] memory empty = new uint256[](0);
        (uint256 allocated, uint256[] memory fills) = _runAllocate(empty, empty, empty, 7, 1);

        assertEq(allocated, 0);
        assertEq(fills.length, 0);
    }

    function test_edge_zeroWeightSum() public {
        uint256[] memory weights = _arr2(0, 0);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 5, 1);

        assertEq(allocated, 0);
        assertEq(_sum(fills), 0);
    }

    function test_edge_zeroCapacities() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(0, 0);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 5, 1);

        assertEq(allocated, 0);
        assertEq(_sum(fills), 0);
    }

    function test_edge_zeroInflow() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 0, 1);

        assertEq(allocated, 0);
        assertEq(_sum(fills), 0);
    }

    function test_edge_shareZeroSkipsAllocation() public {
        uint256[] memory weights = _arr3(0, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(10, 10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 6, 1);

        assertEq(allocated, 6);
        assertEq(fills[0], 0);
        assertEq(fills[1], 3);
        assertEq(fills[2], 3);
    }

    function test_stepLargeLeavesRemainderForSmallImbalances() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 5, 10);

        assertEq(allocated, 0);
        assertEq(_sum(fills), 0);
    }

    function test_stepQuantizationTruncatesImbalance() public {
        uint256[] memory weights = _arr2(1, 3);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 9, 5);

        assertEq(allocated, 5);
        assertEq(fills[0], 0);
        assertEq(fills[1], 5);
    }

    function test_stepOneNoQuantizationLoss() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(10, 10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 7, 1);

        assertEq(allocated, 7);
        assertEq(_sum(fills), 7);
    }

    function test_order_equalImbalanceStableByIndex() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(100, 100, 100);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 1, 1);

        assertEq(allocated, 1);
        assertEq(fills[0], 1);
        assertEq(fills[1], 0);
        assertEq(fills[2], 0);
    }

    function test_allocate_skipsZeroCapacityMaxImbalance() public {
        uint256[] memory weights = _arr3(2, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(0, 10, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 6, 1);

        assertEq(allocated, 4);
        assertEq(fills[0], 0);
        assertEq(fills[1], 2);
        assertEq(fills[2], 2);
    }

    function test_allocate_restWhenInflowExceedsTotalPossible() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(2, 3);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 10, 1);

        assertEq(allocated, 5);
        assertEq(fills[0], 2);
        assertEq(fills[1], 3);
    }

    function test_edge_capacityLessThanStep() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(3, 5, 10);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 30, 4);

        assertEq(allocated, 12);
        assertEq(fills[0], 0);
        assertEq(fills[1], 4);
        assertEq(fills[2], 8);
    }

    function test_edge_lastAllocationLessThanStep() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 9);
        uint256[] memory caps = _arr2(20, 20);

        (uint256 allocated, uint256[] memory fills) = _runAllocate(weights, amounts, caps, 11, 2);

        assertEq(allocated, 10);
        assertEq(fills[0], 10);
        assertEq(fills[1], 0);
    }

    function _runAllocate(
        uint256[] memory weights,
        uint256[] memory amounts,
        uint256[] memory caps,
        uint256 inflow,
        uint256 step
    ) internal returns (uint256 allocated, uint256[] memory fills) {
        AllocationState memory state = _buildState(_copy(weights), _copy(amounts), _copy(caps));

        (allocated, fills) = harness.allocate(state, inflow, step);
    }

    function _buildState(
        uint256[] memory weights,
        uint256[] memory amounts,
        uint256[] memory caps
    ) internal pure returns (AllocationState memory state) {
        uint256 n = weights.length;
        state.sharesX96 = new uint256[](n);
        state.currents = amounts;
        state.capacities = caps;

        uint256 weightSum;
        uint256 totalAmount;
        unchecked {
            for (uint256 i; i < n; ++i) {
                weightSum += weights[i];
                totalAmount += amounts[i];
            }
        }
        state.totalCurrent = totalAmount;
        if (weightSum == 0) return state;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 weight = weights[i];
                if (weight == 0) continue;
                state.sharesX96[i] = Math.mulDiv(weight, S_SCALE, weightSum);
            }
        }
    }

    function _copy(uint256[] memory values) internal pure returns (uint256[] memory out) {
        uint256 n = values.length;
        out = new uint256[](n);
        unchecked {
            for (uint256 i; i < n; ++i) {
                out[i] = values[i];
            }
        }
    }

    function _sum(uint256[] memory values) internal pure returns (uint256 total) {
        uint256 n = values.length;
        unchecked {
            for (uint256 i; i < n; ++i) {
                total += values[i];
            }
        }
    }

    function _arr2(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _arr3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _arr4(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
    }
}

contract DepositAllocatorGreedyHarness {
    function allocate(
        AllocationState memory state,
        uint256 inflow,
        uint256 step
    ) external pure returns (uint256 allocated, uint256[] memory fills) {
        return DepositAllocatorGreedy._allocate(state, inflow, step);
    }
}
