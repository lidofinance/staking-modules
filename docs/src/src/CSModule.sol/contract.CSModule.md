# CSModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/CSModule.sol)

**Inherits:**
[ICSModule](/src/interfaces/ICSModule.sol/interface.ICSModule.md), [BaseModule](/src/abstract/BaseModule.sol/abstract.BaseModule.md)


## State Variables
### MANAGE_TOP_UP_QUEUE_ROLE

```solidity
bytes32 public constant MANAGE_TOP_UP_QUEUE_ROLE = keccak256("MANAGE_TOP_UP_QUEUE_ROLE")
```


### REWIND_TOP_UP_QUEUE_ROLE

```solidity
bytes32 public constant REWIND_TOP_UP_QUEUE_ROLE = keccak256("REWIND_TOP_UP_QUEUE_ROLE")
```


### CSMODULE_STORAGE_LOCATION

```solidity
bytes32 private constant CSMODULE_STORAGE_LOCATION =
    0x48912ff6aecfe3259bdc07bbe67306543da3ba7172b1471bf49b659c3f4c6d00
```


### INITIALIZED_VERSION

```solidity
uint64 internal constant INITIALIZED_VERSION = 3
```


## Functions
### constructor


```solidity
constructor(
    bytes32 moduleType,
    address lidoLocator,
    address parametersRegistry,
    address accounting,
    address exitPenalties
) BaseModule(moduleType, lidoLocator, parametersRegistry, accounting, exitPenalties);
```

### initialize

Initialize contract from scratch. In case of a method call frontrun, the contract instance should be discarded.
It is recommended to call this method in the same transaction as the deployment transaction
and perform extensive deployment verification before using the contract instance.


```solidity
function initialize(address admin, uint8 topUpQueueLimit) external reinitializer(INITIALIZED_VERSION);
```

### finalizeUpgradeV3

This method is expected to be called only when the contract is upgraded from version 2 to version 3 for the existing version 2 deployment.
If the version 3 contract is deployed from scratch, the `initialize` method should be used instead.
To prevent possible frontrun this method should strictly be called in the same TX as the upgrade transaction and should not be called separately.


```solidity
function finalizeUpgradeV3() external reinitializer(INITIALIZED_VERSION);
```

### createNodeOperator

Permissioned method to add a new Node Operator
Should be called by `*Gate.sol` contracts. See `PermissionlessGate.sol` and `VettedGate.sol` for examples


```solidity
function createNodeOperator(
    address from,
    NodeOperatorManagementProperties calldata managementProperties,
    address referrer
) public override(BaseModule, IBaseModule) returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Sender address. Initial sender address to be used as a default manager and reward addresses. Gates must pass the correct address in order to specify which address should be the owner of the Node Operator.|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional. Management properties to be used for the Node Operator. managerAddress: Used as `managerAddress` for the Node Operator. If not passed `from` will be used. rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `from` will be used. extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`. If set to true `resetNodeOperatorManagerAddress` method will be disabled|
|`referrer`|`address`|Optional. Referrer address. Should be passed when Node Operator is created using partners integration|


### obtainDepositData

Get the next `depositsCount` of depositable keys with signatures from the queue

The method does not update depositable keys count for the Node Operators before the queue processing start.
Hence, in the rare cases of negative stETH rebase the method might return unbonded keys. This is a trade-off
between the gas cost and the correctness of the data. Due to module design, any unbonded keys will be requested
to exit by VEBO.

Second param `depositCalldata` is not used


```solidity
function obtainDepositData(
    uint256 depositsCount,
    bytes calldata /* depositCalldata */
)
    external
    returns (bytes memory publicKeys, bytes memory signatures);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositsCount`|`uint256`|Number of deposits to be done|
|`<none>`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`publicKeys`|`bytes`|Batch of the concatenated public validators keys|
|`signatures`|`bytes`|Batch of the concatenated deposit signatures for returned public keys|


### allocateDeposits

Validates that provided keys belong to the corresponding operators in the module and calculates deposit allocations for top-up

The function strictly follows the top-up queue.
If the provided deposit amount can be distributed only on 4 keys, but 5 keys were provided, then the function reverts.


```solidity
function allocateDeposits(
    uint256 maxDepositAmount,
    bytes[] calldata pubkeys,
    uint256[] calldata keyIndices,
    uint256[] calldata operatorIds,
    uint256[] calldata topUpLimits
) external returns (uint256[] memory allocations);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxDepositAmount`|`uint256`|Total ether amount available for top-up (must be multiple of 1 gwei)|
|`pubkeys`|`bytes[]`|List of validator public keys to top up|
|`keyIndices`|`uint256[]`|Indices of keys within their respective operators|
|`operatorIds`|`uint256[]`|Node operator IDs that own the keys|
|`topUpLimits`|`uint256[]`|Maximum amount that can be deposited per key based on CL data and SR internal logic.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allocations`|`uint256[]`|Amount to deposit to each key|


### reportValidatorBalance

Sync tracked added balance for a key based on proven validator balance.

The function only increases the key added value at the moment.


```solidity
function reportValidatorBalance(uint256 nodeOperatorId, uint256 keyIndex, uint256 currentBalanceWei)
    public
    override(BaseModule, IBaseModule);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|
|`currentBalanceWei`|`uint256`|Proven current validator balance in wei|


### setTopUpQueueLimit

Set the top-up queue capacity limit.


```solidity
function setTopUpQueueLimit(uint256 limit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`limit`|`uint256`|How many items may sit in the top-up queue at most.|


### removeKeys

Remove keys for the Node Operator. Charging is module-specific (e.g., CSM applies a per-key fee).
This method is a part of the Optimistic Vetting scheme. After key deletion `totalVettedKeys`
is set equal to `totalAddedKeys`. If invalid keys are not removed, the unvetting process will be repeated
and `decreaseVettedSigningKeysCount` will be called by StakingRouter.


```solidity
function removeKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount)
    external
    override(BaseModule, IBaseModule);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`startIndex`|`uint256`|Index of the first key|
|`keysCount`|`uint256`|Keys count to delete|


### rewindTopUpQueue

Rewind the top-up queue to be able to deposit to mistakenly skipped items.


```solidity
function rewindTopUpQueue(uint256 to) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`uint256`|Pointer to move the queue `head` to.|


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


### updateOperatorBalances

Called by StakingRouter to update node operator total balances.

The function does nothing in CSM, since the information about the operator balances is not used in the
module. If it becomes needed in the future, the method should be implemented and the oracle should deliver
the actual balances.


```solidity
function updateOperatorBalances(bytes calldata, bytes calldata) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`||
|`<none>`|`bytes`||


### getStakingModuleSummary

Returns all-validators summary in the staking module


```solidity
function getStakingModuleSummary()
    external
    view
    override(BaseModule, IStakingModule)
    returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalExitedValidators`|`uint256`|total number of validators in the EXITED state on the Consensus Layer. This value can't decrease in normal conditions|
|`totalDepositedValidators`|`uint256`|total number of validators deposited via the official Deposit Contract. This value is a cumulative counter: even when the validator goes into EXITED state this counter is not decreasing|
|`depositableValidatorsCount`|`uint256`|number of validators in the set available for deposit|


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


### _applyDepositableValidatorsCount


```solidity
function _applyDepositableValidatorsCount(
    NodeOperator storage no,
    uint256 nodeOperatorId,
    uint256 newCount,
    bool incrementNonceIfUpdated
) internal override returns (bool changed);
```

### _addKeysAndUpdateDepositableValidatorsCount


```solidity
function _addKeysAndUpdateDepositableValidatorsCount(
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures
) internal override;
```

### _initTopUpQueue

Setting `topUpQueueLimit` to 0 effectively disables the top-up queue permanently.


```solidity
function _initTopUpQueue(uint8 topUpQueueLimit) internal;
```

### _onlyEnabledTopUpQueue


```solidity
function _onlyEnabledTopUpQueue() internal view;
```

### _topUpQueue


```solidity
function _topUpQueue() internal view returns (TopUpQueueLib.Queue storage);
```

### _topUpQueueEnabled


```solidity
function _topUpQueueEnabled() internal view returns (bool enabled);
```

### _queueLowestPriority


```solidity
function _queueLowestPriority() internal view returns (uint256);
```

### _checkCanAddKeys


```solidity
function _checkCanAddKeys(uint256 nodeOperatorId, address who) internal view override;
```

### _csmStorage


```solidity
function _csmStorage() internal pure returns (CSModuleStorage storage $);
```

## Structs
### CSModuleStorage
**Note:**
storage-location: erc7201:CSModule


```solidity
struct CSModuleStorage {
    TopUpQueueLib.Queue topUpQueue;
}
```

