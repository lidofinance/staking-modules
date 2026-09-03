// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ICSModule } from "../interfaces/ICSModule.sol";
import { ModuleLinearStorage } from "../abstract/ModuleLinearStorage.sol";

import { StakeTracker } from "./StakeTracker.sol";
import { TopUpQueueLib, TopUpQueueItem } from "./TopUpQueueLib.sol";
import { SigningKeys } from "./SigningKeys.sol";
import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";

/// @dev External deployment-linked library used by CSModule to reduce bytecode size.
library TopUpQueueOps {
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using TransientUintUintMapLib for TransientUintUintMap;

    struct TopUpKeyParams {
        uint256[] keyIndices;
        uint256[] operatorIds;
        uint256[] topUpLimits;
    }

    struct AppliedTopUps {
        uint256[] operatorIds;
        uint256[] increments;
        TransientUintUintMap operatorIndexes;
        uint256 operatorsCount;
    }

    // StakingRouter expects non-zero top-up allocations to be at least 1 ether.
    uint256 internal constant TOP_UP_STEP = 2 ether;

    function allocateDeposits(
        ModuleLinearStorage.BaseModuleStorage storage $,
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory) {
        if (
            pubkeys.length != keyIndices.length ||
            pubkeys.length != operatorIds.length ||
            pubkeys.length != topUpLimits.length
        ) {
            revert IBaseModule.InvalidInput();
        }

        if (pubkeys.length > topUpQueue.length()) {
            revert IBaseModule.InvalidInput();
        }
        // NOTE: Wrapping the function inputs with a struct to save space on the stack.
        TopUpKeyParams memory data = TopUpKeyParams({
            keyIndices: keyIndices,
            operatorIds: operatorIds,
            topUpLimits: topUpLimits
        });

        return
            _allocateDeposits({
                $: $,
                topUpQueue: topUpQueue,
                maxDepositAmount: maxDepositAmount,
                pubkeys: pubkeys,
                data: data
            });
    }

    function _allocateDeposits(
        ModuleLinearStorage.BaseModuleStorage storage $,
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        TopUpKeyParams memory data
    ) private returns (uint256[] memory allocations) {
        // Keep batch allocations on the same top-up step as per-key limits.
        maxDepositAmount = _quantizeAmount(maxDepositAmount);

        uint256 keyCount = pubkeys.length;
        allocations = new uint256[](keyCount);
        AppliedTopUps memory applied = AppliedTopUps({
            operatorIds: new uint256[](keyCount),
            increments: new uint256[](keyCount),
            operatorIndexes: TransientUintUintMapLib.create(),
            operatorsCount: 0
        });

        for (uint256 i; i < keyCount; i++) {
            TopUpQueueItem item = topUpQueue.at(0);
            if (data.operatorIds[i] != item.noId() || data.keyIndices[i] != item.keyIndex()) {
                revert ICSModule.InvalidTopUpOrder();
            }

            SigningKeys.verifySigningKey(item.noId(), item.keyIndex(), pubkeys[i]);

            uint256 limit = _quantizeAmount(data.topUpLimits[i]);

            if (maxDepositAmount > 0 && limit > 0) {
                allocations[i] = Math.min(limit, maxDepositAmount);
                maxDepositAmount -= allocations[i];

                // TODO: Decide whether to preserve the previous event ordering where TopUpQueueItemProcessed
                // events preceded KeyAllocatedBalanceChanged events.
                _applyKeyAllocation({
                    $: $,
                    operatorId: data.operatorIds[i],
                    keyIndex: data.keyIndices[i],
                    allocation: allocations[i],
                    applied: applied
                });
            }

            if (allocations[i] == limit) {
                topUpQueue.dequeue();
                emit ICSModule.TopUpQueueItemProcessed(item.noId(), item.keyIndex());
            } else if (i < keyCount - 1) revert ICSModule.UnexpectedExtraKey();
        }

        for (uint256 i; i < applied.operatorsCount; ++i) {
            StakeTracker.increaseOperatorBalance($, applied.operatorIds[i], applied.increments[i]);
        }
    }

    function _applyKeyAllocation(
        ModuleLinearStorage.BaseModuleStorage storage $,
        uint256 operatorId,
        uint256 keyIndex,
        uint256 allocation,
        AppliedTopUps memory applied
    ) private {
        uint256 increment = StakeTracker.applyKeyTopUp($.keyAllocatedBalance, operatorId, keyIndex, allocation);
        if (increment == 0) return;

        uint256 operatorIndex = applied.operatorIndexes.get(operatorId);
        if (operatorIndex == 0) {
            applied.operatorIds[applied.operatorsCount] = operatorId;
            applied.increments[applied.operatorsCount] = increment;
            unchecked {
                ++applied.operatorsCount;
            }
            applied.operatorIndexes.set(operatorId, applied.operatorsCount);
        } else {
            unchecked {
                applied.increments[operatorIndex - 1] += increment;
            }
        }
    }

    function _quantizeAmount(uint256 value) private pure returns (uint256 quantized) {
        unchecked {
            quantized = value - (value % TOP_UP_STEP);
        }
    }
}
