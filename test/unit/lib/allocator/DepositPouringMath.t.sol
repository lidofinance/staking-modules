// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { DepositPouringMath, AllocationState } from "src/lib/allocator/DepositPouringMath.sol";

contract DepositPouringMathTest is Test {
    uint256 internal constant S_SCALE = DepositPouringMath.S_SCALE;
    DepositPouringMathHarness internal harness;

    function setUp() public {
        harness = new DepositPouringMathHarness();
    }

    function test_allocate_singleDemand() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(10, 0);
        uint256[] memory caps = _arr2(10, 10);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            2,
            1
        );

        assertEq(rest, 0);
        assertEq(fills[0], 0);
        assertEq(fills[1], 2);
    }

    function test_allocate_capStopsTopImbalance() public {
        uint256[] memory weights = _arr3(5, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(1, 10, 10);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            7,
            1
        );

        assertEq(fills[0], 1);
        assertEq(fills[1], 1);
        assertEq(fills[2], 1);
        assertEq(rest, 4);
    }

    function test_allocate_spreadWithNegativeImbalance() public {
        uint256[] memory weights = _arr4(1, 1, 1, 1);
        uint256[] memory amounts = _arr4(19, 21, 23, 32);
        uint256[] memory caps = _arr4(100, 100, 100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            5,
            1
        );

        assertEq(rest, 0);
        assertEq(fills[0], 4);
        assertEq(fills[1], 1);
        assertEq(fills[2], 0);
        assertEq(fills[3], 0);
    }

    function test_invariants_sumFillsPlusRestEqualsInflow() public {
        uint256[] memory weights = _arr3(3, 1, 2);
        uint256[] memory amounts = _arr3(10, 0, 5);
        uint256[] memory caps = _arr3(5, 20, 7);

        uint256 inflow = 17;
        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            inflow,
            1
        );

        assertEq(_sum(fills) + rest, inflow);
    }

    function test_invariants_fillsNotExceedCapacities() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(3, 5, 7);

        (uint256[] memory fills, ) = _runAllocate(
            weights,
            amounts,
            caps,
            20,
            1
        );

        for (uint256 i; i < fills.length; ++i) {
            assertLe(fills[i], caps[i]);
        }
    }

    function test_invariants_negativeImbalanceNoFill() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(100, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256[] memory fills, ) = _runAllocate(
            weights,
            amounts,
            caps,
            10,
            1
        );

        assertEq(fills[0], 0);
    }

    function test_invariants_fillQuantizedToStep() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(100, 100);
        uint256 step = 10;

        (uint256[] memory fills, ) = _runAllocate(
            weights,
            amounts,
            caps,
            35,
            step
        );

        for (uint256 i; i < fills.length; ++i) {
            assertEq(fills[i] % step, 0);
        }
    }

    function test_stepOneNoQuantizationLoss() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(10, 10, 10);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            7,
            1
        );

        assertEq(rest, 0);
        assertEq(_sum(fills), 7);
    }

    function test_stepLargeLeavesRemainderForSmallImbalances() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            5,
            10
        );

        assertEq(rest, 5);
        assertEq(_sum(fills), 0);
    }

    function test_stepLargeExactMultipleNoRemainder() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            20,
            10
        );

        assertEq(rest, 0);
        assertEq(fills[0], 10);
        assertEq(fills[1], 10);
    }

    function test_order_equalImbalanceStableByIndex() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(0, 0, 0);
        uint256[] memory caps = _arr3(100, 100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            1,
            1
        );

        assertEq(rest, 0);
        assertEq(fills[0], 1);
        assertEq(fills[1], 0);
        assertEq(fills[2], 0);
    }

    function test_order_positiveOnly() public {
        uint256[] memory weights = _arr3(1, 1, 1);
        uint256[] memory amounts = _arr3(100, 0, 0);
        uint256[] memory caps = _arr3(100, 100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            10,
            1
        );

        assertEq(rest, 0);
        assertEq(fills[0], 0);
        assertEq(fills[1] + fills[2], 10);
    }

    function test_edge_noOperators() public {
        uint256[] memory empty = new uint256[](0);
        (uint256[] memory fills, uint256 rest) = _runAllocate(
            empty,
            empty,
            empty,
            7,
            1
        );

        assertEq(rest, 7);
        assertEq(fills.length, 0);
    }

    function test_edge_zeroWeightSum() public {
        uint256[] memory weights = _arr2(0, 0);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(10, 10);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            5,
            1
        );

        assertEq(rest, 5);
        assertEq(_sum(fills), 0);
    }

    function test_edge_zeroCapacities() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(0, 0);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            5,
            1
        );

        assertEq(rest, 5);
        assertEq(_sum(fills), 0);
    }

    function test_edge_amountAboveTargetNoFill() public {
        uint256[] memory weights = _arr2(1, 3);
        uint256[] memory amounts = _arr2(100, 0);
        uint256[] memory caps = _arr2(100, 100);

        (uint256[] memory fills, uint256 rest) = _runAllocate(
            weights,
            amounts,
            caps,
            10,
            1
        );

        assertEq(rest, 0);
        assertEq(fills[0], 0);
        assertEq(fills[1], 10);
    }

    function test_revert_lengthMismatch() public {
        AllocationState memory state;
        state.shares = new uint256[](2);
        state.amounts = new uint256[](1);
        state.capacities = new uint256[](2);
        state.totalAmount = 0;

        vm.expectRevert(DepositPouringMath.LengthMismatch.selector);
        harness.allocate(state, 1, 1);
    }

    function test_revert_zeroStep() public {
        uint256[] memory weights = _arr2(1, 1);
        uint256[] memory amounts = _arr2(0, 0);
        uint256[] memory caps = _arr2(10, 10);
        AllocationState memory state = _buildState(
            _copy(weights),
            _copy(amounts),
            _copy(caps)
        );

        vm.expectRevert(DepositPouringMath.ZeroStep.selector);
        harness.allocate(state, 1, 0);
    }

    function _runAllocate(
        uint256[] memory weights,
        uint256[] memory amounts,
        uint256[] memory caps,
        uint256 inflow,
        uint256 step
    ) internal returns (uint256[] memory fills, uint256 rest) {
        AllocationState memory a = _buildState(
            _copy(weights),
            _copy(amounts),
            _copy(caps)
        );

        (fills, rest) = harness.allocate(a, inflow, step);
    }

    function _buildState(
        uint256[] memory weights,
        uint256[] memory amounts,
        uint256[] memory caps
    ) internal pure returns (AllocationState memory state) {
        uint256 n = weights.length;
        state.shares = new uint256[](n);
        state.amounts = amounts;
        state.capacities = caps;

        uint256 weightSum;
        uint256 totalAmount;
        unchecked {
            for (uint256 i; i < n; ++i) {
                weightSum += weights[i];
                totalAmount += amounts[i];
            }
        }
        state.totalAmount = totalAmount;
        if (weightSum == 0) return state;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 weight = weights[i];
                if (weight == 0) continue;
                state.shares[i] = Math.mulDiv(weight, S_SCALE, weightSum);
            }
        }
    }

    function _copy(
        uint256[] memory values
    ) internal pure returns (uint256[] memory out) {
        uint256 n = values.length;
        out = new uint256[](n);
        unchecked {
            for (uint256 i; i < n; ++i) {
                out[i] = values[i];
            }
        }
    }

    function _sum(
        uint256[] memory values
    ) internal pure returns (uint256 total) {
        uint256 n = values.length;
        unchecked {
            for (uint256 i; i < n; ++i) {
                total += values[i];
            }
        }
    }

    function _arr2(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _arr3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _arr4(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
    }
}

contract DepositPouringMathHarness {
    function allocate(
        AllocationState memory state,
        uint256 inflow,
        uint256 step
    ) external pure returns (uint256[] memory fills, uint256 rest) {
        return DepositPouringMath._allocate(state, inflow, step);
    }
}
