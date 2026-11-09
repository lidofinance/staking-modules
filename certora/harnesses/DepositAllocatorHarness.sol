// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { AllocationState, DepositAllocatorGreedy } from "../../src/lib/allocator/DepositAllocatorGreedy.sol";
import { PackedSortKey, PackedSortKeyLib } from "../../src/lib/allocator/PackedSortKeyLib.sol";
import { PackedSortKeyMaxHeapLib } from "../../src/lib/allocator/PackedSortKeyMaxHeapLib.sol";

/// @notice Verification-only entrypoints into the production allocation and heap libraries.
/// @dev The allocation entrypoint has exactly two operators, normalized positive X96
///      shares, positive capacities/step, and uint128 monetary inputs. The largest
///      possible target is below 2^130, within the packed imbalance's 224-bit field.
///      These are proof-domain restrictions, not new production input validation.
contract DepositAllocatorHarness {
    using PackedSortKeyLib for PackedSortKey;
    using PackedSortKeyMaxHeapLib for PackedSortKey[];

    uint256 private constant S_SCALE = uint256(1) << 96;

    /// @notice Calls the production allocator for a bounded, two-operator scene.
    function allocateTwo(
        uint128 current0,
        uint128 current1,
        uint128 capacity0,
        uint128 capacity1,
        uint96 share0,
        uint128 amount,
        uint128 step
    ) external pure returns (uint256 allocated, uint256 allocation0, uint256 allocation1) {
        require(capacity0 > 0 && capacity1 > 0 && share0 > 0 && step > 0);

        uint256[] memory allocations;
        (allocated, allocations) = DepositAllocatorGreedy._allocate(
            _stateTwo(current0, current1, capacity0, capacity1, share0),
            amount,
            step
        );
        allocation0 = allocations[0];
        allocation1 = allocations[1];
    }

    function _stateTwo(
        uint128 current0,
        uint128 current1,
        uint128 capacity0,
        uint128 capacity1,
        uint96 share0
    ) private pure returns (AllocationState memory state) {
        state.sharesX96 = new uint256[](2);
        state.currents = new uint256[](2);
        state.capacities = new uint256[](2);
        state.sharesX96[0] = share0;
        state.sharesX96[1] = S_SCALE - share0;
        state.currents[0] = current0;
        state.currents[1] = current1;
        state.capacities[0] = capacity0;
        state.capacities[1] = capacity1;
        state.totalCurrent = uint256(current0) + current1;
    }

    /// @notice Exposes production quantization over its complete uint256 domain.
    function quantize(uint256 value, uint256 step) external pure returns (uint256) {
        return DepositAllocatorGreedy._quantize(value, step);
    }

    /// @notice Exposes lossless packing over the documented representable domain.
    function roundTrip(uint224 imbalance, uint32 index) external pure returns (uint256, uint256) {
        PackedSortKey key = PackedSortKeyLib.pack(imbalance, index);
        return (key.unpackImbalance(), key.unpackIndex());
    }

    /// @notice Calls production heap construction and both pops for two keys.
    function popTwo(
        uint224 imbalance0,
        uint224 imbalance1
    ) external pure returns (uint256 firstIndex, uint256 secondIndex, uint256 firstImbalance, uint256 secondImbalance) {
        PackedSortKey[] memory heap = new PackedSortKey[](2);
        heap[0] = PackedSortKeyLib.pack(imbalance0, 0);
        heap[1] = PackedSortKeyLib.pack(imbalance1, 1);
        heap.heapify();
        PackedSortKey first = heap.popMax(2);
        PackedSortKey second = heap.popMax(1);
        return (first.unpackIndex(), second.unpackIndex(), first.unpackImbalance(), second.unpackImbalance());
    }

    /// @notice Exercises both left and right child selection in the production heap.
    function popThree(
        uint224 imbalance0,
        uint224 imbalance1,
        uint224 imbalance2
    )
        external
        pure
        returns (
            uint256 firstIndex,
            uint256 secondIndex,
            uint256 thirdIndex,
            uint256 firstImbalance,
            uint256 secondImbalance,
            uint256 thirdImbalance
        )
    {
        PackedSortKey[] memory heap = new PackedSortKey[](3);
        heap[0] = PackedSortKeyLib.pack(imbalance0, 0);
        heap[1] = PackedSortKeyLib.pack(imbalance1, 1);
        heap[2] = PackedSortKeyLib.pack(imbalance2, 2);
        heap.heapify();
        PackedSortKey first = heap.popMax(3);
        PackedSortKey second = heap.popMax(2);
        PackedSortKey third = heap.popMax(1);
        return (
            first.unpackIndex(),
            second.unpackIndex(),
            third.unpackIndex(),
            first.unpackImbalance(),
            second.unpackImbalance(),
            third.unpackImbalance()
        );
    }
}
