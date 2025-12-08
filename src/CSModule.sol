// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { IStakingModule } from "./interfaces/IStakingModule.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";
import { QueueLib, Batch } from "./lib/QueueLib.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";

contract CSModule is ICSModule, BaseModule {
    using QueueLib for QueueLib.Queue;

    /// @dev QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].
    uint256 public immutable QUEUE_LOWEST_PRIORITY;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    )
        BaseModule(
            moduleType,
            lidoLocator,
            parametersRegistry,
            accounting,
            exitPenalties
        )
    {
        QUEUE_LOWEST_PRIORITY = PARAMETERS_REGISTRY.QUEUE_LOWEST_PRIORITY();
        _disableInitializers();
    }

    /// @inheritdoc IStakingModule
    /// @notice Get the next `depositsCount` of depositable keys with signatures from the queue
    /// @dev The method does not update depositable keys count for the Node Operators before the queue processing start.
    ///      Hence, in the rare cases of negative stETH rebase the method might return unbonded keys. This is a trade-off
    ///      between the gas cost and the correctness of the data. Due to module design, any unbonded keys will be requested
    ///      to exit by VEBO.
    /// @dev Second param `depositCalldata` is not used
    function obtainDepositData(
        uint256 depositsCount,
        bytes calldata /* depositCalldata */
    )
        external
        virtual
        onlyRole(STAKING_ROUTER_ROLE)
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(depositsCount);
        if (depositsCount == 0) {
            return (publicKeys, signatures);
        }

        uint256 depositsLeft = depositsCount;
        uint256 loadedKeysCount = 0;

        QueueLib.Queue storage queue;
        // Note: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY || depositsLeft == 0) {
                break;
            }

            queue = _queueByPriority[priority];
            unchecked {
                // Note: unused below
                ++priority;
            }

            for (
                Batch item = queue.peek();
                !item.isNil();
                item = queue.peek()
            ) {
                // NOTE: see the `enqueuedCount` note below.
                unchecked {
                    uint256 noId = item.noId();
                    uint256 keysInBatch = item.keys();
                    NodeOperator storage no = _nodeOperators[noId];

                    // Keys are bounded by queue/depositable counts (uint32 slots), so this fits the storage types.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32 keysCount = uint32(
                        Math.min(
                            Math.min(
                                no.depositableValidatorsCount,
                                keysInBatch
                            ),
                            depositsLeft
                        )
                    );
                    // `depositsLeft` is non-zero at this point all the time, so the check `depositsLeft > keysCount`
                    // covers the case when no depositable keys on the Node Operator have been left.
                    if (depositsLeft > keysCount || keysCount == keysInBatch) {
                        // NOTE: `enqueuedCount` >= keysInBatch invariant should be checked.
                        // Enqueued counters are uint32 values; `keysInBatch` is sourced
                        // from the same field and thus cannot exceed the range.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        no.enqueuedCount -= uint32(keysInBatch);
                        // We've consumed all the keys in the batch, so we dequeue it.
                        queue.dequeue();
                    } else {
                        // This branch covers the case when we stop in the middle of the batch.
                        // We release the amount of keys consumed only, the rest will be kept.
                        no.enqueuedCount -= keysCount;
                        // NOTE: `keysInBatch` can't be less than `keysCount` at this point.
                        // We update the batch with the remaining keys.
                        item = item.setKeys(keysInBatch - keysCount);
                        // Store the updated batch back to the queue.
                        queue.queue[queue.head] = item;
                    }

                    // Note: This condition is located here to allow for the correct removal of the batch for the Node Operators with no depositable keys
                    if (keysCount == 0) {
                        continue;
                    }

                    // solhint-disable-next-line func-named-parameters
                    SigningKeys.loadKeysSigs(
                        noId,
                        no.totalDepositedKeys,
                        keysCount,
                        publicKeys,
                        signatures,
                        loadedKeysCount
                    );

                    // It's impossible in practice to reach the limit of these variables.
                    loadedKeysCount += keysCount;
                    uint32 totalDepositedKeys = no.totalDepositedKeys +
                        keysCount;
                    no.totalDepositedKeys = totalDepositedKeys;

                    emit DepositedSigningKeysCountChanged(
                        noId,
                        totalDepositedKeys
                    );

                    // No need for `_updateDepositableValidatorsCount` call since we update the number directly.
                    uint32 newCount = no.depositableValidatorsCount - keysCount;
                    no.depositableValidatorsCount = newCount;
                    emit DepositableSigningKeysCountChanged(noId, newCount);

                    depositsLeft -= keysCount;
                    if (depositsLeft == 0) {
                        break;
                    }
                }
            }
        }

        if (loadedKeysCount != depositsCount) {
            revert NotEnoughKeys();
        }

        unchecked {
            // Deposits counts are capped by queue length (< 2^32) and the storage slots are uint64.
            // forge-lint: disable-next-line(unsafe-typecast)
            _depositableValidatorsCount -= uint64(depositsCount);
            // forge-lint: disable-next-line(unsafe-typecast)
            _totalDepositedValidators += uint64(depositsCount);
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc IStakingModule
    /// @dev Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
    ///      If there are depositable validators in the queue, the method should revert to prevent deposits with invalid
    ///      withdrawal credentials.
    function onWithdrawalCredentialsChanged()
        external
        onlyRole(STAKING_ROUTER_ROLE)
    {
        if (_depositableValidatorsCount > 0) {
            revert DepositQueueHasUnsupportedWithdrawalCredentials();
        }
    }

    /// @inheritdoc ICSModule
    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail) {
        QueueLib.Queue storage q = _queueByPriority[queuePriority];
        return (q.head, q.tail);
    }

    /// @inheritdoc ICSModule
    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch) {
        return _queueByPriority[queuePriority].at(index);
    }

    /// @inheritdoc ICSModule
    function cleanDepositQueue(
        uint256 maxItems
    ) external returns (uint256 removed, uint256 lastRemovedAtDepth) {
        removed = 0;
        lastRemovedAtDepth = 0;

        if (maxItems == 0) {
            return (0, 0);
        }

        // NOTE: We need one unique hash map per function invocation to be able to track batches of
        // the same operator across multiple queues.
        TransientUintUintMap queueLookup = TransientUintUintMapLib.create();

        QueueLib.Queue storage queue;

        uint256 totalVisited = 0;
        // Note: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY) {
                break;
            }

            queue = _queueByPriority[priority];
            unchecked {
                ++priority;
            }

            (
                uint256 removedPerQueue,
                uint256 lastRemovedAtDepthPerQueue,
                uint256 visitedPerQueue,
                bool reachedOutOfQueue
            ) = queue.clean(_nodeOperators, maxItems, queueLookup);

            if (removedPerQueue > 0) {
                unchecked {
                    // 1234 56 789A     <- cumulative depth (A=10)
                    // 1234 12 1234     <- depth per queue
                    // **R*|**|**R*     <- queue with [R]emoved elements
                    //
                    // Given that we observed all 3 queues:
                    // totalVisited: 4+2=6
                    // lastRemovedAtDepthPerQueue: 3
                    // lastRemovedAtDepth: 6+3=9

                    lastRemovedAtDepth =
                        totalVisited +
                        lastRemovedAtDepthPerQueue;
                    removed += removedPerQueue;
                }
            }

            // NOTE: If `maxItems` is set to the total length of the queue(s), `reachedOutOfQueue` is equal
            // to `false`, effectively breaking the cycle, because in `QueueLib.clean` we don't reach
            // an empty batch after the end of a queue.
            if (!reachedOutOfQueue) {
                break;
            }

            unchecked {
                totalVisited += visitedPerQueue;
                maxItems -= visitedPerQueue;
            }
        }
    }

    function _onOperatorDepositableChange(
        uint256 nodeOperatorId
    ) internal override {
        uint256 curveId = _getBondCurveId(nodeOperatorId);
        (uint32 priority, uint32 maxDeposits) = PARAMETERS_REGISTRY
            .getQueueConfig(curveId);

        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        uint32 depositable = no.depositableValidatorsCount;
        uint32 enqueued = no.enqueuedCount;
        if (depositable <= enqueued) {
            return;
        }

        uint32 toEnqueue;
        unchecked {
            toEnqueue = depositable - enqueued;
        }

        if (priority < QUEUE_LOWEST_PRIORITY) {
            unchecked {
                uint32 depositedAndQueued = no.totalDepositedKeys + enqueued;
                if (maxDeposits > depositedAndQueued) {
                    uint32 priorityDepositsLeft = maxDeposits -
                        depositedAndQueued;
                    uint32 count = uint32(
                        Math.min(toEnqueue, priorityDepositsLeft)
                    );

                    _enqueueNodeOperatorKeys(nodeOperatorId, priority, count);
                    toEnqueue -= count;
                }
            }
        }

        if (toEnqueue > 0) {
            _enqueueNodeOperatorKeys(
                nodeOperatorId,
                QUEUE_LOWEST_PRIORITY,
                toEnqueue
            );
        }
    }

    // NOTE: If `count` is 0 an empty batch will be created.
    function _enqueueNodeOperatorKeys(
        uint256 nodeOperatorId,
        uint256 queuePriority,
        uint32 count
    ) internal {
        NodeOperator storage no = _nodeOperators[nodeOperatorId];
        no.enqueuedCount += count;
        QueueLib.Queue storage q = _queueByPriority[queuePriority];
        q.enqueue(nodeOperatorId, count);
        emit BatchEnqueued(queuePriority, nodeOperatorId, count);
    }
}
