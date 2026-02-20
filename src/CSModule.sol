// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { IBaseModule, NodeOperator } from "./interfaces/IBaseModule.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";

import { TopUpQueueLib, TopUpQueueItem, newTopUpQueueItem } from "./lib/TopUpQueueLib.sol";
import { DepositQueueLib, Batch } from "./lib/DepositQueueLib.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";
import { DepositQueueOps } from "./lib/DepositQueueOps.sol";
import { TopUpQueueOps } from "./lib/TopUpQueueOps.sol";
import { NodeOperatorOps } from "./lib/NodeOperatorOps.sol";

contract CSModule is ICSModule, BaseModule {
    using DepositQueueLib for DepositQueueLib.Queue;
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:CSModule
    struct CSModuleStorage {
        TopUpQueueLib.Queue topUpQueue;
    }

    uint256 public immutable QUEUE_LOWEST_PRIORITY;

    bytes32 public constant MANAGE_TOP_UP_QUEUE_ROLE = keccak256("MANAGE_TOP_UP_QUEUE_ROLE");
    bytes32 public constant REWIND_TOP_UP_QUEUE_ROLE = keccak256("REWIND_TOP_UP_QUEUE_ROLE");

    // keccak256(abi.encode(uint256(keccak256("CSModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CSMODULE_STORAGE_LOCATION =
        0x48912ff6aecfe3259bdc07bbe67306543da3ba7172b1471bf49b659c3f4c6d00;

    uint64 internal constant INITIALIZED_VERSION = 3;

    constructor(
        bytes32 moduleType,
        address lidoLocator,
        address parametersRegistry,
        address accounting,
        address exitPenalties
    ) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties) {
        QUEUE_LOWEST_PRIORITY = PARAMETERS_REGISTRY.QUEUE_LOWEST_PRIORITY();
    }

    /// @dev Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
    ///      It is recommended to call this method in the same transaction as the deployment transaction
    ///      and perform extensive deployment verification before using the contract instance.
    function initialize(address admin, uint8 topUpQueueLimit) external reinitializer(INITIALIZED_VERSION) {
        __BaseModule_init(admin);

        // Top-up queue limit = 0 is for 0x01 validators mode.
        // Top-up queue limit > 0 is for 0x02 (EIP-7251) validators mode.
        _initTopUpQueue(topUpQueueLimit);
    }

    /// @dev This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
    ///      If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
    ///      To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.
    function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION) {
        // Clean `__freeSlot1` since the storage slot is no longer needed in version 3.
        assembly ("memory-safe") {
            sstore(__freeSlot1.slot, 0x00)
        }
        // NOTE: Don't call `_initTopUpQueue` because it is disabled by default and existing CSM deployment can only support 0x01 validators mode.

        // NOTE: Rebuild the global withdrawn counter for the future.
        uint256 totalWithdrawnValidators;
        unchecked {
            for (uint256 i; i < _nodeOperatorsCount; ++i) {
                totalWithdrawnValidators += _nodeOperators[i].totalWithdrawnKeys;
            }
        }
        _totalWithdrawnValidators = totalWithdrawnValidators;
        _upToDateOperatorDepositInfoCount = _nodeOperatorsCount;
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
    ) external returns (bytes memory publicKeys, bytes memory signatures) {
        _checkStakingRouterRole();
        _requireDepositInfoUpToDate();

        (publicKeys, signatures) = SigningKeys.initKeysSigsBuf(depositsCount);
        if (depositsCount == 0) return (publicKeys, signatures);

        uint256 depositsLeft = depositsCount;
        uint256 loadedKeysCount = 0;

        bool topUpQueueEnabled = _topUpQueueEnabled();
        DepositQueueLib.Queue storage depositQueue;
        // NOTE: The highest priority to start iterations with. Priorities are ordered like 0, 1, 2, ...
        uint256 priority = 0;

        while (depositsLeft > 0 && priority <= _queueLowestPriority()) {
            depositQueue = _depositQueueByPriority[priority];
            for (Batch item = depositQueue.peek(); !item.isNil(); item = depositQueue.peek()) {
                // NOTE: see the `enqueuedCount` note below.
                unchecked {
                    uint32 noId = uint32(item.noId());
                    NodeOperator storage no = _nodeOperators[noId];

                    uint256 keysInBatch = item.keys();

                    // Keys are bounded by keys in batch and depositable counts (they are uint32 values), so this fits the storage types.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32 keysCount = uint32(
                        Math.min(Math.min(no.depositableValidatorsCount, keysInBatch), depositsLeft)
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

                    // NOTE: This condition is located here to allow for the correct removal of the batch for the Node Operators with no depositable keys
                    if (keysCount == 0) continue;
                    if (topUpQueueEnabled) {
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

                    SigningKeys.loadKeysSigs({
                        nodeOperatorId: noId,
                        startIndex: no.totalDepositedKeys,
                        keysCount: keysCount,
                        pubkeys: publicKeys,
                        signatures: signatures,
                        bufOffset: loadedKeysCount
                    });

                    // It's impossible in practice to reach the limit of these variables.
                    loadedKeysCount += keysCount;
                    uint32 totalDepositedKeys = no.totalDepositedKeys + keysCount;
                    no.totalDepositedKeys = totalDepositedKeys;

                    emit DepositedSigningKeysCountChanged(noId, totalDepositedKeys);

                    // No need for `_updateDepositableValidatorsCount` call since we update the number directly.
                    uint32 newCount = no.depositableValidatorsCount - keysCount;
                    no.depositableValidatorsCount = newCount;
                    emit DepositableSigningKeysCountChanged(noId, newCount);

                    depositsLeft -= keysCount;
                    if (depositsLeft == 0) break;
                }
            }
            unchecked {
                ++priority;
            }
        }

        if (loadedKeysCount != depositsCount) revert NotEnoughKeys();

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
    /// @dev The function strictly follows the top-up queue.
    ///      If the provided deposit amount can be distributed only on 4 keys, but 5 keys were provided, then the function reverts.
    function allocateDeposits(
        uint256 maxDepositAmount,
        bytes[] calldata pubkeys,
        uint256[] calldata keyIndices,
        uint256[] calldata operatorIds,
        uint256[] calldata topUpLimits
    ) external returns (uint256[] memory allocations) {
        _onlyEnabledTopUpQueue();
        _checkStakingRouterRole();

        // We do not call `_requireDepositInfoUpToDate()` here since top-ups in CSM strictly follow the order of the deposit queue
        // and the depositable keys count update is not required for the correct top-up queue processing.

        // Cap top-ups so we don't over-allocate to keys that lost balance due to CL penalties.
        uint256[] memory cappedTopUpLimits = NodeOperatorOps.capTopUpLimitsByKeyBalance(
            _keyAddedBalances,
            operatorIds,
            keyIndices,
            topUpLimits
        );

        allocations = TopUpQueueOps.allocateDeposits({
            topUpQueue: _topUpQueue(),
            maxDepositAmount: maxDepositAmount,
            pubkeys: pubkeys,
            keyIndices: keyIndices,
            operatorIds: operatorIds,
            topUpLimits: cappedTopUpLimits
        });

        if (allocations.length == 0) return allocations;

        NodeOperatorOps.increaseKeyAddedBalancesByAllocations(_keyAddedBalances, operatorIds, keyIndices, allocations);

        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function setTopUpQueueLimit(uint256 limit) external {
        _checkRole(MANAGE_TOP_UP_QUEUE_ROLE);
        _onlyEnabledTopUpQueue();
        if (limit == 0) revert ZeroTopUpQueueLimit();
        if (limit == _topUpQueue().limit) revert SameTopUpQueueLimit();
        _topUpQueue().limit = limit.toUint8();
        emit TopUpQueueLimitSet(limit);
        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function removeKeys(
        uint256 nodeOperatorId,
        uint256 startIndex,
        uint256 keysCount
    ) external override(BaseModule, IBaseModule) {
        _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        NodeOperatorOps.removeKeysCSM(_nodeOperators, nodeOperatorId, startIndex, keysCount);
        // Nonce is updated below due to keys state change
        _updateDepositableValidatorsCount({ nodeOperatorId: nodeOperatorId, incrementNonceIfUpdated: false });
        _incrementModuleNonce();
    }

    // TODO: Ensure that after deep rewind we will be able to iterate over the queue without allocating anything and SR will not revert in this case. Add integration test for it
    /// @inheritdoc ICSModule
    function rewindTopUpQueue(uint256 to) external {
        _checkRole(REWIND_TOP_UP_QUEUE_ROLE);
        _onlyEnabledTopUpQueue();
        _topUpQueue().rewind(to.toUint32());
        emit TopUpQueueRewound(to);
        _incrementModuleNonce();
    }

    /// @inheritdoc ICSModule
    function cleanDepositQueue(uint256 maxItems) external returns (uint256 removed, uint256 lastRemovedAtDepth) {
        return
            DepositQueueOps.cleanDepositQueue({
                depositQueues: _depositQueueByPriority,
                nodeOperators: _nodeOperators,
                queueLowestPriority: _queueLowestPriority(),
                maxItems: maxItems
            });
    }

    /// @inheritdoc ICSModule
    function getTopUpQueue() external view returns (bool enabled, uint256 limit, uint256 length, uint256 head) {
        TopUpQueueLib.Queue storage q = _topUpQueue();
        enabled = q.enabled;
        limit = q.limit;
        length = q.length();
        head = q.head;
    }

    /// @inheritdoc ICSModule
    function getTopUpQueueItem(uint256 index) external view returns (uint256 nodeOperatorId, uint256 keyIndex) {
        TopUpQueueItem item = _topUpQueue().at(index);
        nodeOperatorId = item.noId();
        keyIndex = item.keyIndex();
    }

    /// @inheritdoc IStakingModuleV2
    /// @dev The function does nothing in CSM, since the information about the operator balances is not used in the
    ///      module. If it becomes needed in the future, the method should be implemented and the oracle should deliver
    ///      the actual balances.
    // solhint-disable-next-line no-empty-blocks
    function updateOperatorBalances(bytes calldata, bytes calldata) external view {
        // NOTE: The function does nothing in CSM, see the docstring.
    }

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        override(BaseModule, IStakingModule)
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        totalExitedValidators = _totalExitedValidators;
        totalDepositedValidators = _totalDepositedValidators;
        depositableValidatorsCount = _depositableValidatorsCount;
        if (_topUpQueueEnabled()) {
            depositableValidatorsCount = Math.min(depositableValidatorsCount, _topUpQueue().capacity());
        }
    }

    /// @inheritdoc ICSModule
    function depositQueuePointers(uint256 queuePriority) external view returns (uint128 head, uint128 tail) {
        DepositQueueLib.Queue storage q = _depositQueueByPriority[queuePriority];
        return (q.head, q.tail);
    }

    /// @inheritdoc ICSModule
    function depositQueueItem(uint256 queuePriority, uint128 index) external view returns (Batch) {
        return _depositQueueByPriority[queuePriority].at(index);
    }

    /// @inheritdoc ICSModule
    function getKeysForTopUp(uint256 maxKeyCount) external view returns (bytes[] memory pubkeys) {
        _onlyEnabledTopUpQueue();
        uint256 keyCount = Math.min(maxKeyCount, _topUpQueue().length());
        pubkeys = new bytes[](keyCount);

        for (uint256 i; i < keyCount; i++) {
            TopUpQueueItem item = _topUpQueue().at(i);
            pubkeys[i] = SigningKeys.loadKeys(item.noId(), item.keyIndex(), 1);
        }
    }

    function _applyDepositableValidatorsCount(
        NodeOperator storage no,
        uint256 nodeOperatorId,
        uint256 newCount,
        bool incrementNonceIfUpdated
    ) internal override returns (bool changed) {
        changed = super._applyDepositableValidatorsCount(no, nodeOperatorId, newCount, incrementNonceIfUpdated);
        DepositQueueOps.enqueueNodeOperatorKeys({
            nodeOperators: _nodeOperators,
            depositQueues: _depositQueueByPriority,
            parametersRegistry: _parametersRegistry(),
            accounting: _accounting(),
            queueLowestPriority: _queueLowestPriority(),
            nodeOperatorId: nodeOperatorId
        });
    }

    /// @dev Setting `topUpQueueLimit` to 0 effectively disables the top-up queue permanently.
    function _initTopUpQueue(uint8 topUpQueueLimit) internal {
        if (topUpQueueLimit == 0) return;
        _topUpQueue().enabled = true;
        _topUpQueue().limit = topUpQueueLimit;
        emit TopUpQueueLimitSet(topUpQueueLimit);
    }

    function _onlyEnabledTopUpQueue() internal view {
        if (!_topUpQueueEnabled()) revert TopUpQueueDisabled();
    }

    function _topUpQueue() internal view returns (TopUpQueueLib.Queue storage) {
        CSModuleStorage storage $ = _storage();
        return $.topUpQueue;
    }

    function _topUpQueueEnabled() internal view returns (bool enabled) {
        enabled = _topUpQueue().enabled;
    }

    /// @dev This function is used to get the queue lowest priority from immutables to save bytecode.
    function _queueLowestPriority() internal view returns (uint256) {
        return QUEUE_LOWEST_PRIORITY;
    }

    function _storage() internal pure returns (CSModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CSMODULE_STORAGE_LOCATION
        }
    }
}
