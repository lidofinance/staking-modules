// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseModule } from "./abstract/BaseModule.sol";

import { IStakingModule, IStakingModuleV2 } from "./interfaces/IStakingModule.sol";
import { IBaseModule, NodeOperatorManagementProperties, NodeOperator } from "./interfaces/IBaseModule.sol";
import { ICSModule } from "./interfaces/ICSModule.sol";

import { TopUpQueueLib, TopUpQueueItem } from "./lib/TopUpQueueLib.sol";
import { DepositQueueLib, Batch } from "./lib/DepositQueueLib.sol";
import { SigningKeys } from "./lib/SigningKeys.sol";
import { DepositQueueOps } from "./lib/DepositQueueOps.sol";
import { TopUpQueueOps } from "./lib/TopUpQueueOps.sol";
import { NodeOperatorOps } from "./lib/NodeOperatorOps.sol";
import { StakeTracker } from "./lib/StakeTracker.sol";
import { OperatorTracker } from "./lib/OperatorTracker.sol";

contract CSModule is ICSModule, BaseModule {
    using DepositQueueLib for DepositQueueLib.Queue;
    using TopUpQueueLib for TopUpQueueLib.Queue;
    using SafeCast for uint256;

    /// @custom:storage-location erc7201:CSModule
    struct CSModuleStorage {
        TopUpQueueLib.Queue topUpQueue;
    }

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
    ) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties) {}

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
        BaseModuleStorage storage $ = _baseStorage();
        // NOTE: Don't call `_initTopUpQueue` because it is disabled by default and existing CSM deployment can only support 0x01 validators mode.

        assembly {
            // clean slot `1` since it has old QueueLib.Queue struct data from _legacyQueue variable
            sstore(1, 0x00)
        }

        // NOTE: Rebuild the global withdrawn counter for the future.
        uint256 totalWithdrawnValidators;
        unchecked {
            for (uint256 i; i < $.nodeOperatorsCount; ++i) {
                totalWithdrawnValidators += $.nodeOperators[i].totalWithdrawnKeys;
            }
        }
        $.totalWithdrawnValidators = totalWithdrawnValidators;
        $.upToDateOperatorDepositInfoCount = $.nodeOperatorsCount;
    }

    /// @inheritdoc IBaseModule
    function createNodeOperator(
        address from,
        NodeOperatorManagementProperties calldata managementProperties,
        address referrer
    ) public override(BaseModule, IBaseModule) returns (uint256 nodeOperatorId) {
        nodeOperatorId = super.createNodeOperator(from, managementProperties, referrer);
        OperatorTracker.recordCreator(nodeOperatorId);
        if (referrer != address(0)) emit ReferrerSet(nodeOperatorId, referrer);
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

        if (depositsCount == 0) return (publicKeys, signatures);
        (publicKeys, signatures) = DepositQueueOps.obtainDepositData(
            _baseStorage(),
            _topUpQueue(),
            depositsCount,
            _queueLowestPriority()
        );

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
            _baseStorage(),
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

        StakeTracker.increaseKeyBalances(_baseStorage(), operatorIds, keyIndices, allocations);

        _incrementModuleNonce();
    }

    /// @inheritdoc IBaseModule
    function reportValidatorBalance(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        uint256 currentBalanceWei
    ) public override(BaseModule, IBaseModule) {
        _onlyEnabledTopUpQueue();
        super.reportValidatorBalance(nodeOperatorId, keyIndex, currentBalanceWei);
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
        _removeKeys(nodeOperatorId, startIndex, keysCount, true);
    }

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
        _requireDepositInfoUpToDate();
        return
            DepositQueueOps.cleanDepositQueue({
                $: _baseStorage(),
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

    /// @inheritdoc IStakingModule
    function getStakingModuleSummary()
        external
        view
        override(BaseModule, IStakingModule)
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        BaseModuleStorage storage $ = _baseStorage();
        totalExitedValidators = $.totalExitedValidators;
        totalDepositedValidators = $.totalDepositedValidators;
        depositableValidatorsCount = $.depositableValidatorsCount;
        if (_topUpQueueEnabled()) {
            depositableValidatorsCount = Math.min(depositableValidatorsCount, _topUpQueue().capacity());
        }
    }

    /// @inheritdoc ICSModule
    function depositQueuePointers(uint256 queuePriority) external view returns (uint128 head, uint128 tail) {
        DepositQueueLib.Queue storage q = _baseStorage().depositQueueByPriority[queuePriority];
        return (q.head, q.tail);
    }

    /// @inheritdoc ICSModule
    function depositQueueItem(uint256 queuePriority, uint128 index) external view returns (Batch) {
        return _baseStorage().depositQueueByPriority[queuePriority].at(index);
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
            $: _baseStorage(),
            parametersRegistry: _parametersRegistry(),
            accounting: _accounting(),
            queueLowestPriority: _queueLowestPriority(),
            nodeOperatorId: nodeOperatorId
        });
    }

    function _addKeysAndUpdateDepositableValidatorsCount(
        uint256 nodeOperatorId,
        uint256 keysCount,
        bytes calldata publicKeys,
        bytes calldata signatures
    ) internal override {
        // Do not allow of multiple calls of addValidatorKeys* methods for the creator contract.
        OperatorTracker.forgetCreator(nodeOperatorId);
        super._addKeysAndUpdateDepositableValidatorsCount(nodeOperatorId, keysCount, publicKeys, signatures);
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
        CSModuleStorage storage $ = _csmStorage();
        return $.topUpQueue;
    }

    function _topUpQueueEnabled() internal view returns (bool enabled) {
        enabled = _topUpQueue().enabled;
    }

    function _queueLowestPriority() internal view returns (uint256) {
        return _parametersRegistry().QUEUE_LOWEST_PRIORITY();
    }

    function _checkCanAddKeys(uint256 nodeOperatorId, address who) internal view override {
        // Most likely a direct call, so check the sender is a manager first.
        if (who == msg.sender) {
            _onlyNodeOperatorManager(nodeOperatorId, msg.sender);
        } else {
            // We're trying to add keys via gate, check if we can do it.
            _checkCreateNodeOperatorRole();
            if (OperatorTracker.getCreator(nodeOperatorId) != msg.sender) revert IBaseModule.CannotAddKeys();
        }
    }

    function _csmStorage() internal pure returns (CSModuleStorage storage $) {
        assembly ("memory-safe") {
            $.slot := CSMODULE_STORAGE_LOCATION
        }
    }
}
