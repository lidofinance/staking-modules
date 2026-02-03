// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IBaseModule } from "../interfaces/IBaseModule.sol";
import { ICSModule } from "../interfaces/ICSModule.sol";

import { TopUpQueueLib, TopUpQueueItem } from "./TopUpQueueLib.sol";
import { SigningKeys } from "./SigningKeys.sol";

/// @dev The library is used to reduce CSModule bytecode size.
library TopUpQueueOps {
    using TopUpQueueLib for TopUpQueueLib.Queue;
    struct TopUpKeyParams {
        uint256[] keyIndices;
        uint256[] operatorIds;
        uint256[] topUpLimits;
    }

    function allocateDeposits(
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
        // NOTE: Wrapping the function inputs with a struct to save space on the stack.
        TopUpKeyParams memory data = TopUpKeyParams({
            keyIndices: keyIndices,
            operatorIds: operatorIds,
            topUpLimits: topUpLimits
        });

        return _allocateDeposits(topUpQueue, maxDepositAmount, pubkeys, data);
    }

    function _allocateDeposits(
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        TopUpKeyParams memory data
    ) private returns (uint256[] memory allocations) {
        uint256 keyCount = data.keyIndices.length;
        allocations = new uint256[](keyCount);

        for (uint256 i; i < keyCount; i++) {
            TopUpQueueItem item = topUpQueue.at(0);
            if (
                data.operatorIds[i] != item.noId() ||
                data.keyIndices[i] != item.keyIndex()
            ) {
                revert ICSModule.InvalidTopUpOrder();
            }

            _verifyModuleKey(item.noId(), item.keyIndex(), pubkeys[i]);

            if (maxDepositAmount > 0) {
                allocations[i] = Math.min(
                    data.topUpLimits[i],
                    maxDepositAmount
                );
                maxDepositAmount -= allocations[i];
            }

            if (allocations[i] == data.topUpLimits[i]) {
                topUpQueue.dequeue();
            } else if (i < keyCount - 1) {
                revert ICSModule.UnexpectedExtraKey();
            }
        }
    }

    function _verifyModuleKey(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        bytes memory key
    ) private view {
        if (key.length != SigningKeys.PUBKEY_LENGTH) {
            revert IBaseModule.InvalidInput();
        }
        bytes memory keyFromStorage = SigningKeys.loadKeys(
            nodeOperatorId,
            keyIndex,
            1
        );

        if (keccak256(key) != keccak256(keyFromStorage)) {
            revert ICSModule.InvalidSigningKey();
        }
    }
}
