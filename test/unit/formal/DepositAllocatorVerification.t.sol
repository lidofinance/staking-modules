// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { DepositAllocatorHarness } from "../../../certora/harnesses/DepositAllocatorHarness.sol";

/// @dev Executable counterparts of the bounded CVL properties, plus reachability examples.
contract DepositAllocatorVerificationTest is Test {
    DepositAllocatorHarness private allocator;

    function setUp() public {
        allocator = new DepositAllocatorHarness();
    }

    function test_equalSharesDistributeEntireRequest() public view {
        (uint256 allocated, uint256 a0, uint256 a1) = allocator.allocateTwo(0, 0, 100, 100, uint96(1) << 95, 100, 1);
        assertEq(allocated, 100);
        assertEq(a0, 50);
        assertEq(a1, 50);
    }

    function test_capacityMayLeaveRequestUnallocated() public view {
        (uint256 allocated, uint256 a0, uint256 a1) = allocator.allocateTwo(0, 0, 1, 1, uint96(1) << 95, 100, 1);
        assertEq(allocated, 2);
        assertEq(a0, 1);
        assertEq(a1, 1);
    }

    function test_capacityBelowStepReceivesNothing() public view {
        (uint256 allocated, uint256 a0, uint256 a1) = allocator.allocateTwo(0, 0, 9, 9, uint96(1) << 95, 100, 10);
        assertEq(allocated, 0);
        assertEq(a0, 0);
        assertEq(a1, 0);
    }

    function test_maximumDomainInputsDoNotOverflowPacking() public view {
        (uint256 allocated, uint256 a0, uint256 a1) = allocator.allocateTwo(
            type(uint128).max,
            type(uint128).max,
            type(uint128).max,
            type(uint128).max,
            type(uint96).max,
            type(uint128).max,
            1
        );
        assertEq(allocated, a0 + a1);
        assertLe(allocated, type(uint128).max);
        assertLe(a0, type(uint128).max);
        assertLe(a1, type(uint128).max);
    }

    function testFuzz_twoOperatorAccounting(
        uint128 c0,
        uint128 c1,
        uint128 cap0,
        uint128 cap1,
        uint96 share0,
        uint128 amount,
        uint128 step
    ) public view {
        vm.assume(cap0 > 0 && cap1 > 0 && share0 > 0 && step > 0);
        (uint256 allocated, uint256 a0, uint256 a1) = allocator.allocateTwo(c0, c1, cap0, cap1, share0, amount, step);
        assertEq(allocated, a0 + a1);
        assertLe(allocated, allocator.quantize(amount, step));
        assertLe(a0, cap0);
        assertLe(a1, cap1);
        assertEq(a0 % step, 0);
        assertEq(a1 % step, 0);
        assertEq(allocated % step, 0);
    }

    function testFuzz_quantization(uint256 value, uint256 step) public view {
        uint256 result = allocator.quantize(value, step);
        assertLe(result, value);
        assertEq(allocator.quantize(result, step), result);
        if (step < 2) {
            assertEq(result, value);
        } else {
            assertEq(result % step, 0);
            assertLt(value - result, step);
        }
    }

    function testFuzz_packingAndHeap(uint224 imbalance0, uint224 imbalance1, uint32 index) public view {
        (uint256 actualImbalance, uint256 actualIndex) = allocator.roundTrip(imbalance0, index);
        assertEq(actualImbalance, imbalance0);
        assertEq(actualIndex, index);

        (uint256 first, uint256 second, uint256 firstImbalance, uint256 secondImbalance) = allocator.popTwo(
            imbalance0,
            imbalance1
        );
        assertEq(first, imbalance0 >= imbalance1 ? 0 : 1);
        assertEq(second, first == 0 ? 1 : 0);
        assertEq(firstImbalance, imbalance0 >= imbalance1 ? imbalance0 : imbalance1);
        assertEq(secondImbalance, imbalance0 >= imbalance1 ? imbalance1 : imbalance0);
    }

    function testFuzz_threeKeyHeap(uint224 imbalance0, uint224 imbalance1, uint224 imbalance2) public view {
        (
            uint256 first,
            uint256 second,
            uint256 third,
            uint256 firstImbalance,
            uint256 secondImbalance,
            uint256 thirdImbalance
        ) = allocator.popThree(imbalance0, imbalance1, imbalance2);
        assertGe(firstImbalance, secondImbalance);
        assertGe(secondImbalance, thirdImbalance);
        assertLe(first, 2);
        assertLe(second, 2);
        assertLe(third, 2);
        assertTrue(first != second && first != third && second != third);
        uint224[3] memory inputs = [imbalance0, imbalance1, imbalance2];
        assertEq(firstImbalance, inputs[first]);
        assertEq(secondImbalance, inputs[second]);
        assertEq(thirdImbalance, inputs[third]);
        if (firstImbalance == secondImbalance) assertLt(first, second);
        if (secondImbalance == thirdImbalance) assertLt(second, third);
    }

    function test_threeEqualKeysPreferLowerIndex() public view {
        (uint256 first, uint256 second, uint256 third, , , ) = allocator.popThree(123, 123, 123);
        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(third, 2);
    }
}
