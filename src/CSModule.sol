// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { NodeOperator } from "./interfaces/IBaseModule.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";

import { TransientUintUintMap, TransientUintUintMapLib } from "./lib/TransientUintUintMapLib.sol";
import { TopUpQueueLib, TopUpQueueItem, newTopUpQueueItem } from "./lib/TopUpQueueLib.sol";
import { PackedPubkeys } from "./lib/PackedPubkeys.sol";
import { DepositQueueLib, Batch } from "./lib/DepositQueueLib.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";

contract CSModule is ICSModule, BaseModule {
    using DepositQueueLib for DepositQueueLib.Queue;
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using PackedPubkeys for bytes;
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:CSModule
    struct CSModuleStorage {
        TopUpQueueLib.Queue topUpQueue;
    }

    uint256 public immutable QUEUE_LOWEST_PRIORITY;

    bytes32 public constant MANAGE_TOP_UP_QUEUE_ROLE =
        keccak256("MANAGE_TOP_UP_QUEUE_ROLE");

    // keccak256(abi.encode(uint256(keccak256("CSModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CSMODULE_STORAGE_LOCATION =
        0x48912ff6aecfe3259bdc07bbe67306543da3ba7172b1471bf49b659c3f4c6d00;

    modifier onlyActiveTopUpQueue() {
        _onlyActiveTopUpQueue();
        _;
    }

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

    function initialize(
        address admin,
        uint32 topUpQueueLimit
    ) external reinitializer(3) {
        BaseModule._initialize(admin);

        _initTopUpQueue(topUpQueueLimit);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
    ///      If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
    function finalizeUpgradeV3() external reinitializer(3) {
        // NOTE: Disable the top-up queue for existing modules, because only modules deployed starting from version 3
        // might use the top-up queue.
        _initTopUpQueue(0);
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
        returns (bytes memory publicKeys, bytes memory signatures)
    {
        // NOTE: Function call doesn't leave an unreachable item on the stack.
        _checkRole(STAKING_ROUTER_ROLE);

        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(depositsCount);
        if (depositsCount == 0) {
            return (publicKeys, signatures);
        }

        uint256 depositsLeft = depositsCount;
        uint256 loadedKeysCount = 0;

        bool topUpQueueActive = _topUpQueue().active;
        DepositQueueLib.Queue storage depositQueue;
        // NOTE: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY || depositsLeft == 0) {
                break;
            }

            depositQueue = _depositQueueByPriority[priority];
            unchecked {
                // NOTE: unused below
                ++priority;
            }

            for (
                Batch item = depositQueue.peek();
                !item.isNil();
                item = depositQueue.peek()
            ) {
                // NOTE: see the `enqueuedCount` note below.
                unchecked {
                    NodeOperator storage no = _nodeOperators[item.noId()];
                    uint256 keysInBatch = item.keys();

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
                        depositQueue.dequeue();
                    } else {
                        // This branch covers the case when we stop in the middle of the batch.
                        // We release the amount of keys consumed only, the rest will be kept.
                        no.enqueuedCount -= keysCount;
                        // NOTE: `keysInBatch` can't be less than `keysCount` at this point.
                        // We update the batch with the remaining keys.
                        item = item.setKeys(keysInBatch - keysCount);
                        // Store the updated batch back to the queue.
                        depositQueue.queue[depositQueue.head] = item;
                    }

                    // Note: This condition is located here to allow for the correct removal of the batch for the Node Operators with no depositable keys
                    if (keysCount == 0) {
                        continue;
                    }

                    uint32 noId = uint32(item.noId());

                    if (topUpQueueActive) {
                        uint32 keyIndexBase = no.totalDepositedKeys;
                        for (uint32 i; i < keysCount; i++) {
                            _topUpQueue().enqueue(
                                newTopUpQueueItem(
                                    // The ids are assigned sequentially, so noId can't exceed uint32 in practice.
                                    noId,
                                    keyIndexBase + i
                                )
                            );
                        }
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

    /// @inheritdoc IStakingModuleV2
    function obtainDepositData(
        uint256 depositAmount,
        bytes calldata packedPubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    )
        external
        onlyActiveTopUpQueue
        returns (bytes[] memory publicKeys, uint256[] memory allocations)
    {
        // NOTE: Function call doesn't leave an unreachable item on the stack.
        _checkRole(STAKING_ROUTER_ROLE);

        if (keyIndices.length == 0) {
            return (publicKeys, allocations);
        }

        publicKeys = new bytes[](keyIndices.length);
        allocations = new uint256[](keyIndices.length);

        bool lastItemPartialDeposit;
        for (uint256 i; i < keyIndices.length; i++) {
            if (lastItemPartialDeposit) {
                revert InvalidTopUpOrder();
            }

            TopUpQueueItem item = _topUpQueue().at(0);

            if (operatorIds[i] != item.noId()) {
                revert InvalidTopUpOrder();
            }

            if (keyIndices[i] != item.keyIndex()) {
                revert InvalidTopUpOrder();
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
                _topUpQueue().dequeue();
            } else {
                lastItemPartialDeposit = true;
            }
        }

        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function setTopUpQueueLimit(
        uint256 limit
    ) external onlyActiveTopUpQueue onlyRole(MANAGE_TOP_UP_QUEUE_ROLE) {
        _topUpQueue().limit = limit.toUint32();
        emit TopUpQueueLimitSet(limit);
        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function getTopUpQueue()
        external
        view
        returns (bool active, uint256 limit, uint256 length)
    {
        TopUpQueueLib.Queue storage q = _topUpQueue();
        active = q.active;
        limit = q.limit;
        length = q.length();
    }

    /// @inheritdoc ICSModule
    function getTopUpQueueItem(
        uint256 index
    ) external view returns (uint256 nodeOperatorId, uint256 keyIndex) {
        TopUpQueueLib.Queue storage q = _topUpQueue();
        TopUpQueueItem item = q.at(index);
        nodeOperatorId = item.noId();
        keyIndex = item.keyIndex();
    }

    /// @inheritdoc IStakingModuleV2
    function updateOperatorBalances(
        uint256[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external {
        // NOTE: The function does nothing in CSM, since the information about the operator balances is not used in the
        // module. If it becomes needed in the future, the method should be implemented and the oracle should deliver
        // the actual balances.
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

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        returns (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {
        totalExitedValidators = _totalExitedValidators;
        totalDepositedValidators = _totalDepositedValidators;
        depositableValidatorsCount = _depositableValidatorsCount;
        if (_topUpQueue().active) {
            depositableValidatorsCount = Math.min(
                depositableValidatorsCount,
                _topUpQueue().capacity()
            );
        }
    }

    /// @inheritdoc ICSModule
    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail) {
        DepositQueueLib.Queue storage q = _depositQueueByPriority[
            queuePriority
        ];
        return (q.head, q.tail);
    }

    /// @inheritdoc ICSModule
    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch) {
        return _depositQueueByPriority[queuePriority].at(index);
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

        DepositQueueLib.Queue storage queue;

        uint256 totalVisited = 0;
        // Note: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (true) {
            if (priority > QUEUE_LOWEST_PRIORITY) {
                break;
            }

            queue = _depositQueueByPriority[priority];
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

    /// @inheritdoc ICSModule
    function getKeysForTopUp(
        uint256 keyCount
    ) external view onlyActiveTopUpQueue returns (bytes[] memory pubkeys) {
        keyCount = Math.min(keyCount, _topUpQueue().length());
        pubkeys = new bytes[](keyCount);

        for (uint256 i; i < keyCount; i++) {
            TopUpQueueItem item = _topUpQueue().at(i);
            pubkeys[i] = SigningKeys.loadKeys(item.noId(), item.keyIndex(), 1);
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
        DepositQueueLib.Queue storage q = _depositQueueByPriority[
            queuePriority
        ];
        q.enqueue(nodeOperatorId, count);
        emit BatchEnqueued(queuePriority, nodeOperatorId, count);
    }

    function _verifyModuleKey(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        bytes memory key
    ) internal view {
        bytes memory keyFromStorage = SigningKeys.loadKeys(
            nodeOperatorId,
            keyIndex,
            1
        );

        if (keccak256(key) != keccak256(keyFromStorage)) {
            revert InvalidSigningKey();
        }
    }

    /// @dev Setting `topUpQueueLimit` to 0 effectively disables the top-up queue permanently.
    function _initTopUpQueue(uint32 topUpQueueLimit) internal {
        if (topUpQueueLimit > 0) {
            _topUpQueue().limit = topUpQueueLimit;
            _topUpQueue().active = true;
        }
    }

    function _onlyActiveTopUpQueue() internal view {
        if (!_topUpQueue().active) {
            revert TopUpQueueDisabled();
        }
    }

    function _topUpQueue() internal view returns (TopUpQueueLib.Queue storage) {
        CSModuleStorage storage $ = _storage();
        return $.topUpQueue;
    }

    function _storage() internal pure returns (CSModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CSMODULE_STORAGE_LOCATION
        }
    }
}
