// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ICSModule } from "../interfaces/ICSModule.sol";

import { TopUpQueueLib, TopUpQueueItem } from "./TopUpQueueLib.sol";
import { PackedPubkeys } from "./PackedPubkeys.sol";
import { SigningKeys } from "./SigningKeys.sol";

/// @dev The library is used to reduce CSModule bytecode size.
library TopUpDepositDataLib {
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using PackedPubkeys for bytes;

    function obtainDepositData(
        TopUpQueueLib.Queue storage topUpQueue,
        uint256 depositAmount,
        bytes calldata packedPubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    )
        external
        returns (bytes[] memory publicKeys, uint256[] memory allocations)
    {
        publicKeys = new bytes[](keyIndices.length);
        allocations = new uint256[](keyIndices.length);

        for (uint256 i; i < keyIndices.length; i++) {
            // NOTE: Check whether the last processed key was partially filled.
            if (i > 0 && allocations[i - 1] < topUpLimits[i - 1]) {
                revert ICSModule.UnexpectedExtraKey();
            }

            TopUpQueueItem item = topUpQueue.at(0);

            if (
                operatorIds[i] != item.noId() ||
                keyIndices[i] != item.keyIndex()
            ) {
                revert ICSModule.InvalidTopUpOrder();
            }

            {
                bytes memory key = packedPubkeys.at(i);
                _verifyModuleKey(item.noId(), item.keyIndex(), key);
                publicKeys[i] = key;
            }

            if (depositAmount > 0) {
                allocations[i] = Math.min(topUpLimits[i], depositAmount);
                depositAmount -= allocations[i];
            }

            if (allocations[i] == topUpLimits[i]) {
                topUpQueue.dequeue();
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
