// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ICSModule } from "../interfaces/ICSModule.sol";

import { TopUpQueueLib, TopUpQueueItem } from "./TopUpQueueLib.sol";
import { PackedPubkeys } from "./PackedPubkeys.sol";
import { SigningKeys } from "./SigningKeys.sol";

/// @dev The library is used to reduce CSModule bytecode size.
library TopUpQueueOps {
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using PackedPubkeys for bytes;

    struct TopUpKeyParams {
        uint256[] keyIndices;
        uint256[] operatorIds;
        uint256[] topUpLimits;
    }

    function obtainDepositData(
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 depositAmount,
        bytes calldata packedPubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (bytes[] memory, uint256[] memory) {
        // NOTE: Wrapping the function inputs with a struct to save space on the stack.
        TopUpKeyParams memory data = TopUpKeyParams({
            keyIndices: keyIndices,
            operatorIds: operatorIds,
            topUpLimits: topUpLimits
        });

        return
            _obtainDepositData(topUpQueue, depositAmount, packedPubkeys, data);
    }

    function _obtainDepositData(
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 depositAmount,
        bytes calldata packedPubkeys,
        TopUpKeyParams memory data
    )
        private
        returns (bytes[] memory publicKeys, uint256[] memory allocations)
    {
        uint256 keyCount = data.keyIndices.length;

        publicKeys = new bytes[](keyCount);
        allocations = new uint256[](keyCount);

        bool lastItemPartiallyDeposited;
        for (uint256 i; i < keyCount; i++) {
            if (lastItemPartiallyDeposited) {
                revert ICSModule.UnexpectedExtraKey();
            }

            TopUpQueueItem item = topUpQueue.at(0);

            if (
                data.operatorIds[i] != item.noId() ||
                data.keyIndices[i] != item.keyIndex()
            ) {
                revert ICSModule.InvalidTopUpOrder();
            }

            {
                bytes memory key = packedPubkeys.at(i);
                _verifyModuleKey(item.noId(), item.keyIndex(), key);
                publicKeys[i] = key;
            }

            if (depositAmount > 0) {
                allocations[i] = Math.min(data.topUpLimits[i], depositAmount);
                depositAmount -= allocations[i];
            }

            if (allocations[i] == data.topUpLimits[i]) {
                topUpQueue.dequeue();
            } else {
                lastItemPartiallyDeposited = true;
            }
        }
    }

    function _verifyModuleKey(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        bytes memory key
    ) private view {
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
