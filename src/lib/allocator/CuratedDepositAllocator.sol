// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ICuratedModule } from "../../interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "../../interfaces/IMetaRegistry.sol";
import { NodeOperator } from "../../interfaces/IBaseModule.sol";
import { AllocationState, DepositAllocatorGreedy } from "./DepositAllocatorGreedy.sol";
import { WithdrawnValidatorLib } from "../WithdrawnValidatorLib.sol";

/// @notice Curated deposit allocation helpers (external library for bytecode savings).
/// @dev Invariants assumed by this library:
///      - totalWithdrawnKeys <= totalDepositedKeys per operator.
///      - each operatorId < operatorsCount.
library CuratedDepositAllocator {
    struct DepositableOperatorsData {
        // Per-operator allocation shares scaled by DepositAllocatorGreedy.S_SCALE (2^96).
        // During collection this temporarily stores raw weights and is normalized in-place
        // right before allocation.
        uint256[] sharesX96;
        uint256[] currents; // Current amounts per operator (units depend on caller: validator count for deposits, wei for top-ups).
        uint256[] capacities; // Remaining capacity per operator (units match `currents`).
        uint256[] operatorIds; // Operator ids aligned with arrays above (compacted to operators included in allocation).
        uint256 count; // Number of operators included in allocation (filled entries in the arrays above).
        uint256 weightSum; // Sum of weights across eligible operators (for share calculation).
        uint256 totalCurrent; // Sum of current amounts across eligible operators (units match `currents`).
    }

    uint256 public constant MAX_EFFECTIVE_BALANCE = 2048 ether;
    uint256 public constant MIN_ACTIVATION_BALANCE = 32 ether;

    uint256 internal constant DEPOSIT_STEP = 1;
    // 1 ETH: consensus EFFECTIVE_BALANCE_INCREMENT (and MIN_DEPOSIT_AMOUNT) are 1e9 gwei,
    // so this is the smallest effective-balance step; EIP‑7251 keeps that increment.
    uint256 internal constant TOP_UP_STEP = 1 ether;

    /// @notice Allocate new validator deposits across curated operators.
    /// @dev Input preparation and iteration behavior:
    ///      - Only operators with capacity > 0 and non-zero allocation weight are included.
    ///      - Current amounts are derived from deposited minus withdrawn keys (active keys).
    ///      - Operators that hit their capacity here will have capacity == 0 next call and
    ///        will be excluded; remaining operators’ shares increase.
    /// @dev Returns compact arrays containing only operators with non-zero allocations.
    /// @param nodeOperators Node operator storage mapping from the module.
    /// @param operatorsCount Total operators count in the module.
    /// @param depositsCount Number of validator deposits to allocate.
    /// @return allocated Number of deposits actually allocated.
    /// @return operatorIds Operator ids for allocated operators.
    /// @return allocations Per-operator allocations aligned to operatorIds.
    function allocateInitialDeposits(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 operatorsCount,
        uint256 depositsCount
    ) external view returns (uint256 allocated, uint256[] memory operatorIds, uint256[] memory allocations) {
        if (depositsCount == 0) return (0, new uint256[](0), new uint256[](0));

        DepositableOperatorsData memory data = _collectDepositableOperatorsData(nodeOperators, operatorsCount);

        uint256[] memory eligibleAllocations;
        (allocated, eligibleAllocations) = _computeAllocations({
            operatorsData: data,
            step: DEPOSIT_STEP,
            allocationAmount: depositsCount
        });

        (operatorIds, allocations) = _compactAllocations(data.operatorIds, eligibleAllocations, data.count);
    }

    /// @notice Allocate top-up deposit amount across curated operators.
    /// @dev Input preparation and iteration behavior:
    ///      - Duplicated operator ids are not expected (caller guarantees uniqueness).
    ///      - Only operators with non-zero allocation weight are included.
    ///      - Shares are computed across all eligible operators in the module
    ///        (non-zero weight, non-zero top-up capacity),
    ///        so a subset cannot bias its share by omitting other eligible operators.
    ///      - Per-operator capacity is computed as:
    ///        `(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
    ///      - Per-key top-up limits are *not* used as caps for allocation; they are
    ///        applied later per-key and may leave unallocated remainder.
    ///      - Operators that have zero remaining balance after allocation are excluded
    ///        on later iterations by capacity == 0 at the module level.
    /// @param nodeOperators Node operator storage mapping from the module.
    /// @param nodeOperatorBalances Per-operator balance (in wei) storage mapping from the module.
    /// @param operatorsCount Total operators count in the module.
    /// @param allocationAmount Total top-up amount in wei to allocate.
    /// @param operatorIds Key owner operator ids for this top-up request.
    /// @return allocated Total allocated amount in wei.
    /// @return allocatedOperatorIds Operator ids for allocated operators.
    /// @return allocations Per-operator allocations aligned to allocatedOperatorIds.
    function allocateTopUps(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        mapping(uint256 => uint256) storage nodeOperatorBalances,
        uint256 operatorsCount,
        uint256 allocationAmount,
        uint256[] calldata operatorIds
    ) external view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations) {
        if (allocationAmount == 0 || operatorIds.length == 0) return (0, new uint256[](0), new uint256[](0));

        // operatorsCount > 0 is guaranteed by the caller.

        DepositableOperatorsData memory data = _collectTopUpEligibleOperatorsData(
            nodeOperators,
            nodeOperatorBalances,
            operatorsCount,
            operatorIds
        );
        if (data.count == 0) return (0, new uint256[](0), new uint256[](0));

        uint256[] memory eligibleAllocations;
        (allocated, eligibleAllocations) = _computeAllocations({
            operatorsData: data,
            step: TOP_UP_STEP,
            allocationAmount: allocationAmount
        });

        (allocatedOperatorIds, allocations) = _compactAllocations(data.operatorIds, eligibleAllocations, data.count);
    }

    /// @dev Collect eligible operators for deposit allocation.
    ///      Filters out zero capacity and zero-weight operators.
    function _collectDepositableOperatorsData(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 operatorsCount
    ) internal view returns (DepositableOperatorsData memory data) {
        data.sharesX96 = new uint256[](operatorsCount);
        data.currents = new uint256[](operatorsCount);
        data.capacities = new uint256[](operatorsCount);
        data.operatorIds = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        uint256 eligibleCount;
        unchecked {
            for (uint256 i; i < operatorsCount; ++i) {
                NodeOperator storage no = nodeOperators[i];
                uint256 capacity = no.depositableValidatorsCount;
                if (capacity == 0) continue;

                (uint256 weight, uint256 externalStake) = metaRegistry.getNodeOperatorWeightAndExternalStake(i);
                if (weight == 0) continue;

                // NOTE: To determine the count of validators a node operator would have in the module we calculate
                // allocation for, we divide the external stake by the maximum stake a validator might have in this
                // module. Since the CuratedModule supports 0x02 validators, the maximum value is MAX_EFFECTIVE_BALANCE.
                uint256 current = no.totalDepositedKeys - no.totalWithdrawnKeys;
                if (externalStake > 0) current += externalStake / WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE;

                data.sharesX96[eligibleCount] = weight;
                data.currents[eligibleCount] = current;
                data.capacities[eligibleCount] = capacity;
                data.operatorIds[eligibleCount] = i;
                data.weightSum += weight;
                data.totalCurrent += current;
                ++eligibleCount;
            }
        }

        data.count = eligibleCount;
        // Truncate arrays to the number of eligible operators collected.
        _truncateDepositable(data);
    }

    /// @dev Collect eligible operators for top-up allocation.
    ///      Duplicates in operatorIds are disallowed and must be filtered by the caller.
    function _collectTopUpEligibleOperatorsData(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        mapping(uint256 => uint256) storage nodeOperatorBalances,
        uint256 operatorsCount,
        uint256[] calldata operatorIds
    ) internal view returns (DepositableOperatorsData memory data) {
        data.sharesX96 = new uint256[](operatorIds.length);
        data.currents = new uint256[](operatorIds.length);
        data.capacities = new uint256[](operatorIds.length);
        data.operatorIds = new uint256[](operatorIds.length);

        uint256[] memory weightsByOperatorId;
        uint256[] memory capacitiesByOperatorId;
        uint256[] memory currentStakeByOperatorId;
        (
            data.weightSum,
            data.totalCurrent,
            weightsByOperatorId,
            capacitiesByOperatorId,
            currentStakeByOperatorId
        ) = _collectTopUpGlobalBaseline({
            nodeOperators: nodeOperators,
            nodeOperatorBalances: nodeOperatorBalances,
            operatorsCount: operatorsCount
        });

        uint256 eligibleCount;
        for (uint256 i; i < operatorIds.length; ++i) {
            uint256 operatorId = operatorIds[i];

            // Collect only requested operators; allocation still uses the global share baseline.
            uint256 capacity = capacitiesByOperatorId[operatorId];
            if (capacity == 0) continue;

            uint256 weight = weightsByOperatorId[operatorId];
            if (weight == 0) continue;

            data.sharesX96[eligibleCount] = weight;
            data.currents[eligibleCount] = currentStakeByOperatorId[operatorId];
            data.capacities[eligibleCount] = capacity;
            data.operatorIds[eligibleCount] = operatorId;
            ++eligibleCount;
        }

        data.count = eligibleCount;
        // Truncate arrays to the number of eligible operators collected.
        _truncateDepositable(data);
    }

    function _collectTopUpGlobalBaseline(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        mapping(uint256 => uint256) storage nodeOperatorBalances,
        uint256 operatorsCount
    )
        internal
        view
        returns (
            uint256 weightSum,
            uint256 totalCurrent,
            uint256[] memory weightsByOperatorId,
            uint256[] memory capacitiesByOperatorId,
            uint256[] memory currentStakeByOperatorId
        )
    {
        weightsByOperatorId = new uint256[](operatorsCount);
        capacitiesByOperatorId = new uint256[](operatorsCount);
        currentStakeByOperatorId = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        // Build global share baseline across all eligible operators (non-zero weight + capacity).
        for (uint256 i; i < operatorsCount; ++i) {
            uint256 balance = nodeOperatorBalances[i];
            uint256 capacity = _topUpCapacity(nodeOperators[i], balance);
            if (capacity == 0) continue;
            capacitiesByOperatorId[i] = capacity;

            (uint256 weight, uint256 externalStake) = metaRegistry.getNodeOperatorWeightAndExternalStake(i);
            if (weight == 0) continue;
            weightsByOperatorId[i] = weight;
            weightSum += weight;

            uint256 currentStake = balance + externalStake;
            currentStakeByOperatorId[i] = currentStake;
            totalCurrent += currentStake;
        }
    }

    /// @dev Maximum top-up capacity for an operator:
    ///      (active validators * 2048 ETH) - current balance, floored at zero.
    function _topUpCapacity(NodeOperator storage no, uint256 balanceWei) internal view returns (uint256 capacity) {
        unchecked {
            uint256 maxTotal = (no.totalDepositedKeys - no.totalWithdrawnKeys) * MAX_EFFECTIVE_BALANCE;
            if (maxTotal > balanceWei) capacity = maxTotal - balanceWei;
        }
    }

    /// @dev Quantizes a value down to the nearest multiple of TOP_UP_STEP.
    function quantizeForTopUp(uint256 value) internal pure returns (uint256) {
        return DepositAllocatorGreedy._quantize(value, TOP_UP_STEP);
    }

    /// @dev Builds AllocationState and runs the configured allocator in-memory.
    ///      Expects operatorsData arrays already filtered/truncated to eligible operators.
    function _computeAllocations(
        DepositableOperatorsData memory operatorsData,
        uint256 step,
        uint256 allocationAmount
    ) internal pure returns (uint256 allocated, uint256[] memory allocations) {
        uint256 n = operatorsData.sharesX96.length;
        // allocationAmount > 0, n > 0, and step > 0 are guaranteed by the callers.

        AllocationState memory state;
        state.sharesX96 = operatorsData.sharesX96;
        state.currents = operatorsData.currents;
        state.capacities = operatorsData.capacities;
        state.totalCurrent = operatorsData.totalCurrent;

        // weightSum > 0 is guaranteed by the collectors for any non-empty input.
        for (uint256 i; i < n; ++i) {
            // Note: no zero-check here. Collectors filter out zero weights and truncate
            // arrays to eligibleCount, so sharesX96 entries are non-zero for i < n.

            // Convert raw weights to X96 shares in-place (reuses the same array).
            state.sharesX96[i] = Math.mulDiv(
                state.sharesX96[i],
                DepositAllocatorGreedy.S_SCALE,
                operatorsData.weightSum
            );
        }

        (uint256[] memory allocUnits, uint256 remainder) = DepositAllocatorGreedy._allocate(
            state,
            allocationAmount,
            step
        );

        allocated = allocationAmount - remainder;
        allocations = allocUnits;
    }

    function _compactAllocations(
        uint256[] memory operatorIds,
        uint256[] memory eligibleAllocations,
        uint256 count
    ) internal pure returns (uint256[] memory compactIds, uint256[] memory allocations) {
        compactIds = new uint256[](count);
        allocations = new uint256[](count);
        uint256 compactIndex;
        for (uint256 i; i < count; ++i) {
            uint256 allocation = eligibleAllocations[i];
            if (allocation == 0) continue;
            compactIds[compactIndex] = operatorIds[i];
            allocations[compactIndex] = allocation;
            ++compactIndex;
        }
        if (compactIndex != count) {
            assembly {
                mstore(compactIds, compactIndex)
                mstore(allocations, compactIndex)
            }
        }
    }

    /// @dev Shrinks eligible arrays to the collected eligible count.
    function _truncateDepositable(DepositableOperatorsData memory data) internal pure {
        uint256 count = data.count;
        if (count == data.sharesX96.length) return;
        uint256[] memory sharesX96 = data.sharesX96;
        uint256[] memory currents = data.currents;
        uint256[] memory capacities = data.capacities;
        uint256[] memory operatorIds = data.operatorIds;
        assembly {
            mstore(sharesX96, count)
            mstore(currents, count)
            mstore(capacities, count)
            mstore(operatorIds, count)
        }
    }
}
