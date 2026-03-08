// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ITopUpQueueLib } from "../lib/TopUpQueueLib.sol";
import { IDepositQueueLib, Batch } from "../lib/DepositQueueLib.sol";

import { IBaseModule } from "./IBaseModule.sol";
import { IStakingModuleV2 } from "./IStakingModule.sol";

/// @title Lido's Community Staking Module interface
interface ICSModule is IBaseModule, IStakingModuleV2, IDepositQueueLib, ITopUpQueueLib {
    event BatchEnqueued(uint256 indexed queuePriority, uint256 indexed nodeOperatorId, uint256 count);
    event TopUpQueueItemProcessed(uint256 indexed nodeOperatorId, uint256 keyIndex);
    event TopUpQueueLimitSet(uint256 limit);
    event TopUpQueueRewound(uint256 to);

    error NotEligibleForPriorityQueue();
    error PriorityQueueAlreadyUsed();
    error PriorityQueueMaxDepositsUsed();
    error NoQueuedKeysToMigrate();
    error TopUpQueueDisabled();
    error ZeroTopUpQueueLimit();
    error SameTopUpQueueLimit();
    error InvalidSigningKey();
    error InvalidTopUpOrder();
    error UnexpectedExtraKey();

    /// @notice Initializes the contract.
    /// @param admin An address to grant the DEFAULT_ADMIN_ROLE to.
    /// @param topUpQueueLimit The limit of the top-up queue.
    function initialize(address admin, uint8 topUpQueueLimit) external;

    /// @notice Clean the deposit queue from batches with no depositable keys
    /// @dev Use **eth_call** to check how many items will be removed
    /// @param maxItems How many queue items to review
    /// @return removed Count of batches to be removed by visiting `maxItems` batches
    /// @return lastRemovedAtDepth The value to use as `maxItems` to remove `removed` batches if the static call of the method was used
    function cleanDepositQueue(uint256 maxItems) external returns (uint256 removed, uint256 lastRemovedAtDepth);

    /// @notice Set the top-up queue capacity limit.
    /// @param limit How many items may sit in the top-up queue at most.
    function setTopUpQueueLimit(uint256 limit) external;

    /// @notice Rewind the top-up queue to be able to deposit to mistakenly skipped items.
    /// @param to Pointer to move the queue `head` to.
    function rewindTopUpQueue(uint256 to) external;

    /// @notice Returns the top-up queue stats.
    /// @return enabled Whether the queue was enabled upon initialization of the module.
    /// @return limit How many items may sit in the top-up queue at most.
    /// @return length How many items are in the queue.
    /// @return head Pointer to the head of the queue.
    function getTopUpQueue() external view returns (bool enabled, uint256 limit, uint256 length, uint256 head);

    /// @notice Returns the top-up queue item by the given index.
    /// @param index An offset from the current head (not a global index) of the item to retrieve.
    /// @return nodeOperatorId Node operator ID.
    /// @return keyIndex Index of the key in the Node Operator's keys storage
    function getTopUpQueueItem(uint256 index) external view returns (uint256 nodeOperatorId, uint256 keyIndex);

    /// @notice Get the pointers to the head and tail of queue with the given priority.
    /// @param queuePriority Priority of the queue to get the pointers.
    /// @return head Pointer to the head of the queue.
    /// @return tail Pointer to the tail of the queue.
    function depositQueuePointers(uint256 queuePriority) external view returns (uint128 head, uint128 tail);

    /// @notice Get the deposit queue item by an index
    /// @param queuePriority Priority of the queue to get an item from
    /// @param index Index of a queue item
    /// @return Deposit queue item from the priority queue
    function depositQueueItem(uint256 queuePriority, uint128 index) external view returns (Batch);

    /// @notice Fetches up to `maxKeyCount` validator public keys from the top-up queue.
    /// @dev If the queue contains fewer than `maxKeyCount` entries, all available keys are returned.
    /// @dev The keys are returned in the same order as they appear in the queue.
    /// @param maxKeyCount The maximum number of keys to retrieve.
    /// @return pubkeys The list of validator public keys returned from the queue.
    function getKeysForTopUp(uint256 maxKeyCount) external view returns (bytes[] memory pubkeys);
}
