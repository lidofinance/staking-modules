// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IQueueLib, Batch } from "../lib/QueueLib.sol";

import { IBaseModule } from "./IBaseModule.sol";

/// @title Lido's Community Staking Module interface
interface ICSModule is
    IBaseModule,
    /* IStakingModuleV2 */
    IQueueLib
{
    event BatchEnqueued(
        uint256 indexed queuePriority,
        uint256 indexed nodeOperatorId,
        uint256 count
    );

    error NotEligibleForPriorityQueue();
    error PriorityQueueAlreadyUsed();
    error PriorityQueueMaxDepositsUsed();
    error NoQueuedKeysToMigrate();
    error DepositQueueHasUnsupportedWithdrawalCredentials();

    /// @notice Clean the deposit queue from batches with no depositable keys
    /// @dev Use **eth_call** to check how many items will be removed
    /// @param maxItems How many queue items to review
    /// @return removed Count of batches to be removed by visiting `maxItems` batches
    /// @return lastRemovedAtDepth The value to use as `maxItems` to remove `removed` batches if the static call of the method was used
    function cleanDepositQueue(
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth);

    // /// @notice Fetches up to `keysCount` validator public keys from the front of the top-up queue.
    // /// @dev If the queue contains fewer than `keysCount` entries, all available keys are returned.
    // /// @dev The keys are returned in the same order as they appear in the queue.
    // /// @param keysCount The maximum number of keys to retrieve.
    // /// @return pubkeys The list of validator public keys returned from the queue.
    // function getKeysForTopUp(
    //     uint256 keysCount
    // ) external view returns (bytes[] memory pubkeys);

    function QUEUE_LOWEST_PRIORITY() external view returns (uint256);

    /// @notice Get the pointers to the head and tail of queue with the given priority.
    /// @param queuePriority Priority of the queue to get the pointers.
    /// @return head Pointer to the head of the queue.
    /// @return tail Pointer to the tail of the queue.
    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail);

    /// @notice Get the deposit queue item by an index
    /// @param queuePriority Priority of the queue to get an item from
    /// @param index Index of a queue item
    /// @return Deposit queue item from the priority queue
    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch);
}
