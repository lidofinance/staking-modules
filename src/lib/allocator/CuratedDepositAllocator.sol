// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ICuratedModule } from "../../interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "../../interfaces/IMetaRegistry.sol";
import { NodeOperator } from "../../interfaces/IBaseModule.sol";
import { ModuleLinearStorage } from "../../abstract/ModuleLinearStorage.sol";
import { AllocationState, DepositAllocatorGreedy } from "./DepositAllocatorGreedy.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "../TransientUintUintMapLib.sol";
import { ValidatorBalanceLimits } from "../ValidatorBalanceLimits.sol";
import { StakeTracker } from "../StakeTracker.sol";

/// @notice Curated deposit allocation helpers (external library for bytecode savings).
/// @dev Invariants assumed by this library:
///      - totalWithdrawnKeys <= totalDepositedKeys per operator.
///      - each operatorId < operatorsCount.
library CuratedDepositAllocator {
    struct DepositableOperatorsData {
        // Shared allocation arrays + totalCurrent — passed directly to the allocator.
        // During collection, alloc.sharesX96 temporarily stores raw weights
        // and is normalized in-place right before allocation.
        AllocationState alloc;
        uint256[] operatorIds; // Operator ids aligned with arrays above (compacted to operators included in allocation).
        uint256 count; // Number of operators included in allocation (filled entries in the arrays above).
        uint256 weightSum; // Sum of weights across eligible operators (for share calculation).
    }

    uint256 internal constant DEPOSIT_STEP = 1;
    uint256 internal constant TOP_UP_STEP = 2 ether;

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
        if (depositsCount == 0) return (allocated, operatorIds, allocations);

        DepositableOperatorsData memory data = _collectDepositableOperatorsData(nodeOperators, operatorsCount);

        (allocated, allocations) = _computeAllocations({
            operatorsData: data,
            step: DEPOSIT_STEP,
            allocationAmount: depositsCount
        });

        (operatorIds, allocations) = _compactAllocations(data.operatorIds, allocations, data.count);
    }

    /// @dev Returns operator-level top-up allocations for the provided operators.
    ///      - Duplicated operator ids are not expected (caller guarantees uniqueness).
    ///      - Only operators with non-zero allocation weight are included.
    ///      - Shares are computed across all eligible operators in the module
    ///        (non-zero weight, non-zero top-up capacity),
    ///        so a subset cannot bias its share by omitting other eligible operators.
    ///      - Per-operator capacity is computed as:
    ///        `(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
    ///      - `current_operator_balance` here is the module's tracked stake view, not a live decrementing oracle value:
    ///        active balance decreases are intentionally reflected later via withdrawal reporting.
    /// @param $ Base module storage pointer.
    /// @param allocationAmount Total top-up amount in wei to allocate.
    /// @param operatorIds Unique operator ids to include in allocation.
    /// @return allocated Total allocated amount in wei.
    /// @return allocatedOperatorIds Operator ids for allocated operators.
    /// @return allocations Per-operator allocations aligned to allocatedOperatorIds.
    function allocateTopUps(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 allocationAmount,
        uint256[] calldata operatorIds
    ) external view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations) {
        uint256[] memory operatorIdsCopy = operatorIds;
        return _allocateTopUps($, allocationAmount, operatorIdsCopy);
    }

    /// @dev Allocate top-ups across unique operators and immediately distribute them to keys.
    ///      - Raw operator ids may contain duplicates; they are deduplicated before operator-level allocation
    ///        to avoid overweighting operators that appear on multiple requested keys.
    ///      - Shares are computed across all eligible operators in the module
    ///        (non-zero weight, non-zero top-up capacity),
    ///        so a subset cannot bias its share by omitting other eligible operators.
    ///      - Per-operator capacity is computed as:
    ///        `(active_validators * 2048 ETH) - current_operator_balance`, floored at zero.
    ///      - `current_operator_balance` is intentionally based on tracked stake that preserves prior observed highs
    ///        until withdrawal settlement, so active slashing/leakage is accounted when penalties are finalized.
    ///      - Per-key top-up limits are not used as caps for operator-level allocation; they are
    ///        applied during key-level distribution and may leave unallocated remainder.
    function allocateAndDistributeTopUps(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 allocationAmount,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory allocations) {
        uint256[] memory allocatedOperatorIds;
        uint256[] memory uniqueOperatorIds = _uniqueOperatorIds(operatorIds);
        uint256[] memory remainingOperatorAllocations;
        (, allocatedOperatorIds, remainingOperatorAllocations) = _allocateTopUps(
            $,
            allocationAmount,
            uniqueOperatorIds
        );
        if (allocatedOperatorIds.length == 0) return new uint256[](operatorIds.length);
        return
            _distributeAllocationsWithinLimits({
                operatorIds: operatorIds,
                topUpLimits: topUpLimits,
                allocatedOperatorIds: allocatedOperatorIds,
                remainingOperatorAllocations: remainingOperatorAllocations
            });
    }

    function _uniqueOperatorIds(uint256[] calldata operatorIds) private returns (uint256[] memory uniqueOperatorIds) {
        uniqueOperatorIds = new uint256[](operatorIds.length);
        TransientUintUintMap seen = TransientUintUintMapLib.create();
        uint256 count;
        for (uint256 i; i < operatorIds.length; ++i) {
            uint256 operatorId = operatorIds[i];
            if (seen.get(operatorId) != 0) continue;
            seen.set(operatorId, 1);
            uniqueOperatorIds[count] = operatorId;
            ++count;
        }

        if (count != operatorIds.length) {
            assembly {
                mstore(uniqueOperatorIds, count)
            }
        }
    }

    function _allocateTopUps(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 allocationAmount,
        uint256[] memory operatorIds
    ) private view returns (uint256 allocated, uint256[] memory allocatedOperatorIds, uint256[] memory allocations) {
        DepositableOperatorsData memory data = _collectTopUpEligibleOperatorsData($, operatorIds);
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
    ) private view returns (DepositableOperatorsData memory data) {
        data.alloc.sharesX96 = new uint256[](operatorsCount);
        data.alloc.currents = new uint256[](operatorsCount);
        data.alloc.capacities = new uint256[](operatorsCount);
        data.operatorIds = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        uint256 eligibleCount;
        for (uint256 i; i < operatorsCount; ++i) {
            NodeOperator storage no = nodeOperators[i];
            uint256 capacity = no.depositableValidatorsCount;
            if (capacity == 0) continue;

            (uint256 weight, uint256 externalStake) = metaRegistry.getNodeOperatorWeightAndExternalStake(i);
            if (weight == 0) continue;

            // NOTE: To determine the count of validators a node operator would have in the module we calculate
            // allocation for, we divide the external stake by the maximum stake a validator might have in this
            // module. Since the CuratedModule supports 0x02 validators, the maximum value is MAX_EFFECTIVE_BALANCE.
            unchecked {
                uint256 current = no.totalDepositedKeys - no.totalWithdrawnKeys;
                if (externalStake > 0) current += externalStake / ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE;

                data.alloc.sharesX96[eligibleCount] = weight;
                data.alloc.currents[eligibleCount] = current;
                data.alloc.capacities[eligibleCount] = capacity;
                data.operatorIds[eligibleCount] = i;
                data.weightSum += weight;
                data.alloc.totalCurrent += current;
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
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256[] memory operatorIds
    ) private view returns (DepositableOperatorsData memory data) {
        data.alloc.sharesX96 = new uint256[](operatorIds.length);
        data.alloc.currents = new uint256[](operatorIds.length);
        data.alloc.capacities = new uint256[](operatorIds.length);
        data.operatorIds = new uint256[](operatorIds.length);

        uint256[] memory weightsByOperatorId;
        uint256[] memory capacitiesByOperatorId;
        uint256[] memory currentStakeByOperatorId;
        (
            data.weightSum,
            data.alloc.totalCurrent,
            weightsByOperatorId,
            capacitiesByOperatorId,
            currentStakeByOperatorId
        ) = _collectTopUpGlobalBaseline($);

        uint256 eligibleCount;
        for (uint256 i; i < operatorIds.length; ++i) {
            uint256 operatorId = operatorIds[i];

            // Collect only requested operators; allocation still uses the global share baseline.
            uint256 capacity = capacitiesByOperatorId[operatorId];
            if (capacity == 0) continue;

            uint256 weight = weightsByOperatorId[operatorId];
            if (weight == 0) continue;

            data.alloc.sharesX96[eligibleCount] = weight;
            data.alloc.currents[eligibleCount] = currentStakeByOperatorId[operatorId];
            data.alloc.capacities[eligibleCount] = capacity;
            data.operatorIds[eligibleCount] = operatorId;
            ++eligibleCount;
        }

        data.count = eligibleCount;
        // Truncate arrays to the number of eligible operators collected.
        _truncateDepositable(data);
    }

    function _collectTopUpGlobalBaseline(
        ModuleLinearStorage.BaseModuleStorage storage $
    )
        private
        view
        returns (
            uint256 weightSum,
            uint256 totalCurrent,
            uint256[] memory weightsByOperatorId,
            uint256[] memory capacitiesByOperatorId,
            uint256[] memory currentStakeByOperatorId
        )
    {
        uint256 operatorsCount = $.nodeOperatorsCount;
        weightsByOperatorId = new uint256[](operatorsCount);
        capacitiesByOperatorId = new uint256[](operatorsCount);
        currentStakeByOperatorId = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        // Build global share baseline across all eligible operators (non-zero weight + capacity).
        for (uint256 i; i < operatorsCount; ++i) {
            uint256 balance = StakeTracker.getOperatorBalance($, i);
            uint256 capacity = _topUpCapacity($.nodeOperators[i], balance);
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
            uint256 maxTotal = (no.totalDepositedKeys - no.totalWithdrawnKeys) *
                ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE;
            if (maxTotal > balanceWei) capacity = maxTotal - balanceWei;
        }
    }

    /// @notice Returns current deposit allocation targets for all operators.
    /// @dev Target = totalCurrent * operatorWeight / totalWeight (in validator count).
    ///      Includes operators regardless of depositable capacity for informational purposes.
    ///      Actual allocation recalculates shares only across operators with available capacity,
    ///      so real per-operator amounts may differ from the targets shown here.
    ///      Arrays are indexed by operator id; zero-weight operators have zero values.
    /// @param nodeOperators Node operator storage mapping from the module.
    /// @param operatorsCount Total operators count in the module.
    /// @return currentValidators Current active validator count per operator.
    /// @return targetValidators Target validator count per operator.
    function getDepositAllocationTargets(
        mapping(uint256 => NodeOperator) storage nodeOperators,
        uint256 operatorsCount
    ) external view returns (uint256[] memory currentValidators, uint256[] memory targetValidators) {
        if (operatorsCount == 0) return (currentValidators, targetValidators);

        currentValidators = new uint256[](operatorsCount);
        targetValidators = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        uint256 weightSum;
        uint256 totalCurrent;
        for (uint256 i; i < operatorsCount; ++i) {
            NodeOperator storage no = nodeOperators[i];
            (uint256 weight, uint256 externalStake) = metaRegistry.getNodeOperatorWeightAndExternalStake(i);
            if (weight == 0) continue;

            unchecked {
                uint256 current = no.totalDepositedKeys - no.totalWithdrawnKeys;
                if (externalStake > 0) current += externalStake / ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE;

                currentValidators[i] = current;
                // Temporarily store raw weight in targetValidators; will be converted below.
                targetValidators[i] = weight;
                weightSum += weight;
                totalCurrent += current;
            }
        }

        if (weightSum == 0) return (currentValidators, targetValidators);

        for (uint256 i; i < operatorsCount; ++i) {
            if (targetValidators[i] == 0) continue;
            targetValidators[i] = Math.mulDiv(totalCurrent, targetValidators[i], weightSum);
        }
    }

    /// @notice Returns current top-up allocation targets for all operators.
    /// @dev Target = totalCurrent * operatorWeight / totalWeight (in wei).
    ///      Includes operators regardless of top-up capacity for informational purposes.
    ///      Actual allocation recalculates shares only across operators with available capacity,
    ///      so real per-operator amounts may differ from the targets shown here.
    ///      Arrays are indexed by operator id; zero-weight operators have zero values.
    /// @param $ Base module storage pointer.
    /// @return currentAllocations Current operator stake in wei.
    /// @return targetAllocations Target operator stake in wei.
    function getTopUpAllocationTargets(
        ModuleLinearStorage.BaseModuleStorage storage $
    ) external view returns (uint256[] memory currentAllocations, uint256[] memory targetAllocations) {
        uint256 operatorsCount = $.nodeOperatorsCount;
        if (operatorsCount == 0) return (currentAllocations, targetAllocations);

        currentAllocations = new uint256[](operatorsCount);
        targetAllocations = new uint256[](operatorsCount);

        IMetaRegistry metaRegistry = ICuratedModule(address(this)).META_REGISTRY();

        uint256 weightSum;
        uint256 totalCurrent;
        for (uint256 i; i < operatorsCount; ++i) {
            (uint256 weight, uint256 externalStake) = metaRegistry.getNodeOperatorWeightAndExternalStake(i);
            if (weight == 0) continue;

            uint256 currentStake = StakeTracker.getOperatorBalance($, i) + externalStake;
            currentAllocations[i] = currentStake;
            // Temporarily store raw weight in targetAllocations; will be converted below.
            targetAllocations[i] = weight;
            weightSum += weight;
            totalCurrent += currentStake;
        }

        if (weightSum == 0) return (currentAllocations, targetAllocations);

        for (uint256 i; i < operatorsCount; ++i) {
            if (targetAllocations[i] == 0) continue;
            targetAllocations[i] = Math.mulDiv(totalCurrent, targetAllocations[i], weightSum);
        }
    }

    /// @dev Quantizes a value down to the nearest multiple of TOP_UP_STEP.
    function quantizeForTopUp(uint256 value) internal pure returns (uint256) {
        return DepositAllocatorGreedy._quantize(value, TOP_UP_STEP);
    }

    function _distributeAllocationsWithinLimits(
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits,
        uint256[] memory allocatedOperatorIds,
        uint256[] memory remainingOperatorAllocations
    ) private returns (uint256[] memory allocations) {
        allocations = new uint256[](operatorIds.length);
        TransientUintUintMap operatorIndexes = TransientUintUintMapLib.create();

        for (uint256 i; i < allocatedOperatorIds.length; ++i) {
            operatorIndexes.set(allocatedOperatorIds[i], i + 1);
        }

        unchecked {
            for (uint256 i; i < operatorIds.length; ++i) {
                uint256 allocationIndex = operatorIndexes.get(operatorIds[i]);
                if (allocationIndex == 0) continue;
                --allocationIndex;

                uint256 remaining = remainingOperatorAllocations[allocationIndex];
                if (remaining == 0) continue;

                uint256 limit = quantizeForTopUp(topUpLimits[i]);
                if (limit == 0) continue;

                uint256 amount = Math.min(remaining, limit);
                allocations[i] = amount;
                remainingOperatorAllocations[allocationIndex] = remaining - amount;
            }
        }
    }

    /// @dev Normalizes raw weights into X96 shares and runs the allocator in-memory.
    ///      Expects operatorsData arrays already filtered/truncated to eligible operators.
    function _computeAllocations(
        DepositableOperatorsData memory operatorsData,
        uint256 step,
        uint256 allocationAmount
    ) internal pure returns (uint256 allocated, uint256[] memory allocations) {
        // allocationAmount > 0, n > 0, and step > 0 are guaranteed by the callers.

        _normalizeWeightsToShares(operatorsData);

        (allocated, allocations) = DepositAllocatorGreedy._allocate(operatorsData.alloc, allocationAmount, step);
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

    /// @dev Converts raw weights in alloc.sharesX96 to X96-scaled shares in-place.
    function _normalizeWeightsToShares(DepositableOperatorsData memory data) internal pure {
        uint256[] memory sharesX96 = data.alloc.sharesX96;
        for (uint256 i; i < sharesX96.length; ++i) {
            // NOTE: no zero-check here. Collectors filter out zero weights and truncate
            //       arrays to eligible node operators count, so sharesX96 entries are non-zero.
            sharesX96[i] = Math.mulDiv(
                sharesX96[i],
                DepositAllocatorGreedy.S_SCALE,
                // weightSum > 0 is guaranteed by the collectors for any non-empty input.
                data.weightSum
            );
        }
    }

    /// @dev Shrinks eligible arrays to the collected eligible count.
    function _truncateDepositable(DepositableOperatorsData memory data) internal pure {
        uint256 count = data.count;
        if (count == data.alloc.sharesX96.length) return;
        uint256[] memory sharesX96 = data.alloc.sharesX96;
        uint256[] memory currents = data.alloc.currents;
        uint256[] memory capacities = data.alloc.capacities;
        uint256[] memory operatorIds = data.operatorIds;
        assembly {
            mstore(sharesX96, count)
            mstore(currents, count)
            mstore(capacities, count)
            mstore(operatorIds, count)
        }
    }
}
