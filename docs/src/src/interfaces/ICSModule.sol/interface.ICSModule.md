# ICSModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/ICSModule.sol)

**Inherits:**
[IBaseModule](/src/interfaces/IBaseModule.sol/interface.IBaseModule.md), [IStakingModuleV2](/src/interfaces/IStakingModule.sol/interface.IStakingModuleV2.md), [IDepositQueueLib](/src/lib/DepositQueueLib.sol/interface.IDepositQueueLib.md), [ITopUpQueueLib](/src/lib/TopUpQueueLib.sol/interface.ITopUpQueueLib.md)

**Title:**
Lido's Community Staking Module interface


## Functions
### initialize

Initializes the contract.


```solidity
function initialize(address admin, uint8 topUpQueueLimit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|An address to grant the DEFAULT_ADMIN_ROLE to.|
|`topUpQueueLimit`|`uint8`|The limit of the top-up queue.|


### cleanDepositQueue

Clean the deposit queue from batches with no depositable keys

Use **eth_call** to check how many items will be removed


```solidity
function cleanDepositQueue(uint256 maxItems) external returns (uint256 removed, uint256 lastRemovedAtDepth);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxItems`|`uint256`|How many queue items to review|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`removed`|`uint256`|Count of batches to be removed by visiting `maxItems` batches|
|`lastRemovedAtDepth`|`uint256`|The value to use as `maxItems` to remove `removed` batches if the static call of the method was used|


### setTopUpQueueLimit

Set the top-up queue capacity limit.


```solidity
function setTopUpQueueLimit(uint256 limit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|How many items may sit in the top-up queue at most.|


### rewindTopUpQueue

Rewind the top-up queue to be able to deposit to mistakenly skipped items.


```solidity
function rewindTopUpQueue(uint256 to) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`uint256`|Pointer to move the queue `head` to.|


### getTopUpQueue

Returns the top-up queue stats.


```solidity
function getTopUpQueue() external view returns (bool enabled, uint256 limit, uint256 length, uint256 head);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`enabled`|`bool`|Whether the queue was enabled upon initialization of the module.|
|`limit`|`uint256`|How many items may sit in the top-up queue at most.|
|`length`|`uint256`|How many items are in the queue.|
|`head`|`uint256`|Pointer to the head of the queue.|


### getTopUpQueueItem

Returns the top-up queue item by the given index.


```solidity
function getTopUpQueueItem(uint256 index) external view returns (uint256 nodeOperatorId, uint256 keyIndex);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|An offset from the current head (not a global index) of the item to retrieve.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Node operator ID.|
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|


### depositQueuePointers

Get the pointers to the head and tail of queue with the given priority.


```solidity
function depositQueuePointers(uint256 queuePriority) external view returns (uint128 head, uint128 tail);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`queuePriority`|`uint256`|Priority of the queue to get the pointers.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`head`|`uint128`|Pointer to the head of the queue.|
|`tail`|`uint128`|Pointer to the tail of the queue.|


### depositQueueItem

Get the deposit queue item by an index


```solidity
function depositQueueItem(uint256 queuePriority, uint128 index) external view returns (Batch);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`queuePriority`|`uint256`|Priority of the queue to get an item from|
|`index`|`uint128`|Index of a queue item|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Batch`|Deposit queue item from the priority queue|


### getKeysForTopUp

Fetches up to `maxKeyCount` validator public keys from the top-up queue.

If the queue contains fewer than `maxKeyCount` entries, all available keys are returned.

The keys are returned in the same order as they appear in the queue.


```solidity
function getKeysForTopUp(uint256 maxKeyCount) external view returns (bytes[] memory pubkeys);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxKeyCount`|`uint256`|The maximum number of keys to retrieve.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`pubkeys`|`bytes[]`|The list of validator public keys returned from the queue.|


## Events
### BatchEnqueued

```solidity
event BatchEnqueued(uint256 indexed queuePriority, uint256 indexed nodeOperatorId, uint256 count);
```

### TopUpQueueItemProcessed

```solidity
event TopUpQueueItemProcessed(uint256 indexed nodeOperatorId, uint256 keyIndex);
```

### TopUpQueueLimitSet

```solidity
event TopUpQueueLimitSet(uint256 limit);
```

### TopUpQueueRewound

```solidity
event TopUpQueueRewound(uint256 to);
```

## Errors
### NotEligibleForPriorityQueue

```solidity
error NotEligibleForPriorityQueue();
```

### PriorityQueueAlreadyUsed

```solidity
error PriorityQueueAlreadyUsed();
```

### PriorityQueueMaxDepositsUsed

```solidity
error PriorityQueueMaxDepositsUsed();
```

### NoQueuedKeysToMigrate

```solidity
error NoQueuedKeysToMigrate();
```

### TopUpQueueDisabled

```solidity
error TopUpQueueDisabled();
```

### ZeroTopUpQueueLimit

```solidity
error ZeroTopUpQueueLimit();
```

### SameTopUpQueueLimit

```solidity
error SameTopUpQueueLimit();
```

### InvalidSigningKey

```solidity
error InvalidSigningKey();
```

### InvalidTopUpOrder

```solidity
error InvalidTopUpOrder();
```

### UnexpectedExtraKey

```solidity
error UnexpectedExtraKey();
```

