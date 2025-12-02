# ICSModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/ICSModule.sol)

**Inherits:**
[IQueueLib](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/QueueLib.sol/interface.IQueueLib.md), [INOAddresses](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/NOAddresses.sol/interface.INOAddresses.md), [IAssetRecovererLib](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/AssetRecovererLib.sol/interface.IAssetRecovererLib.md), [IStakingModule](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IStakingModule.sol/interface.IStakingModule.md), [INodeOperatorOwner](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/INodeOperatorOwner.sol/interface.INodeOperatorOwner.md)


## Functions
### PAUSE_ROLE


```solidity
function PAUSE_ROLE() external view returns (bytes32);
```

### RESUME_ROLE


```solidity
function RESUME_ROLE() external view returns (bytes32);
```

### STAKING_ROUTER_ROLE


```solidity
function STAKING_ROUTER_ROLE() external view returns (bytes32);
```

### REPORT_GENERAL_DELAYED_PENALTY_ROLE


```solidity
function REPORT_GENERAL_DELAYED_PENALTY_ROLE() external view returns (bytes32);
```

### SETTLE_GENERAL_DELAYED_PENALTY_ROLE


```solidity
function SETTLE_GENERAL_DELAYED_PENALTY_ROLE() external view returns (bytes32);
```

### VERIFIER_ROLE


```solidity
function VERIFIER_ROLE() external view returns (bytes32);
```

### SUBMIT_WITHDRAWALS_ROLE


```solidity
function SUBMIT_WITHDRAWALS_ROLE() external view returns (bytes32);
```

### RECOVERER_ROLE


```solidity
function RECOVERER_ROLE() external view returns (bytes32);
```

### CREATE_NODE_OPERATOR_ROLE


```solidity
function CREATE_NODE_OPERATOR_ROLE() external view returns (bytes32);
```

### LIDO_LOCATOR


```solidity
function LIDO_LOCATOR() external view returns (ILidoLocator);
```

### STETH


```solidity
function STETH() external view returns (IStETH);
```

### PARAMETERS_REGISTRY


```solidity
function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);
```

### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### EXIT_PENALTIES


```solidity
function EXIT_PENALTIES() external view returns (IExitPenalties);
```

### FEE_DISTRIBUTOR


```solidity
function FEE_DISTRIBUTOR() external view returns (address);
```

### QUEUE_LOWEST_PRIORITY


```solidity
function QUEUE_LOWEST_PRIORITY() external view returns (uint256);
```

### pauseFor

Pause creation of the Node Operators and keys upload for `duration` seconds.
Existing NO management and reward claims are still available.
To pause reward claims use pause method on Accounting


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### resume

Resume creation of the Node Operators and keys upload


```solidity
function resume() external;
```

### getInitializedVersion

Returns the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

### createNodeOperator

Permissioned method to add a new Node Operator
Should be called by `*Gate.sol` contracts. See `PermissionlessGate.sol` and `VettedGate.sol` for examples


```solidity
function createNodeOperator(
    address from,
    NodeOperatorManagementProperties memory managementProperties,
    address referrer
) external returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Sender address. Initial sender address to be used as a default manager and reward addresses. Gates must pass the correct address in order to specify which address should be the owner of the Node Operator.|
|`managementProperties`|`NodeOperatorManagementProperties`|Optional. Management properties to be used for the Node Operator. managerAddress: Used as `managerAddress` for the Node Operator. If not passed `from` will be used. rewardAddress: Used as `rewardAddress` for the Node Operator. If not passed `from` will be used. extendedManagerPermissions: Flag indicating that `managerAddress` will be able to change `rewardAddress`. If set to true `resetNodeOperatorManagerAddress` method will be disabled|
|`referrer`|`address`|Optional. Referrer address. Should be passed when Node Operator is created using partners integration|


### addValidatorKeysETH

Add new keys to the existing Node Operator using ETH as a bond


```solidity
function addValidatorKeysETH(
    address from,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|


### addValidatorKeysStETH

Add new keys to the existing Node Operator using stETH as a bond

Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert


```solidity
function addValidatorKeysStETH(
    address from,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures,
    IAccounting.PermitInput memory permit
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|
|`permit`|`IAccounting.PermitInput`|Optional. Permit to use stETH as bond|


### addValidatorKeysWstETH

Add new keys to the existing Node Operator using wstETH as a bond

Due to the stETH rounding issue make sure to make approval or sign permit with extra 10 wei to avoid revert


```solidity
function addValidatorKeysWstETH(
    address from,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes memory publicKeys,
    bytes memory signatures,
    IAccounting.PermitInput memory permit
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|Sender address. Commonly equals to `msg.sender` except for the case of Node Operator creation by `*Gate.sol` contracts|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keysCount`|`uint256`|Signing keys count|
|`publicKeys`|`bytes`|Public keys to submit|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|
|`permit`|`IAccounting.PermitInput`|Optional. Permit to use wstETH as bond|


### reportGeneralDelayedPenalty

Report general delayed penalty for the given Node Operator

The final locked amount will be equal to the penalty amount plus additional fine


```solidity
function reportGeneralDelayedPenalty(
    uint256 nodeOperatorId,
    bytes32 penaltyType,
    uint256 amount,
    string calldata details
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`penaltyType`|`bytes32`|Type of the penalty|
|`amount`|`uint256`|Penalty amount in ETH|
|`details`|`string`|Additional details about the penalty|


### compensateGeneralDelayedPenalty

Compensate general delayed penalty for the given Node Operator to prevent further validator exits

Can only be called by the Node Operator manager


```solidity
function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### cancelGeneralDelayedPenalty

Cancel previously reported and not settled general delayed penalty for the given Node Operator

The funds will be unlocked


```solidity
function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`amount`|`uint256`|Amount of penalty to cancel|


### settleGeneralDelayedPenalty

Settles locked bond and sets the target limit to 0 or the given Node Operators

SETTLE_GENERAL_DELAYED_PENALTY_ROLE role is expected to be assigned to Easy Track


```solidity
function settleGeneralDelayedPenalty(uint256[] memory nodeOperatorIds, uint256[] memory maxAmounts) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`uint256[]`|IDs of the Node Operators|
|`maxAmounts`|`uint256[]`|Maximum amounts to settle for each Node Operator|


### proposeNodeOperatorManagerAddressChange

Propose a new manager address for the Node Operator


```solidity
function proposeNodeOperatorManagerAddressChange(uint256 nodeOperatorId, address proposedAddress) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`proposedAddress`|`address`|Proposed manager address|


### confirmNodeOperatorManagerAddressChange

Confirm a new manager address for the Node Operator.
Should be called from the currently proposed address


```solidity
function confirmNodeOperatorManagerAddressChange(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### resetNodeOperatorManagerAddress

Reset the manager address to the reward address.
Should be called from the reward address


```solidity
function resetNodeOperatorManagerAddress(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### proposeNodeOperatorRewardAddressChange

Propose a new reward address for the Node Operator


```solidity
function proposeNodeOperatorRewardAddressChange(uint256 nodeOperatorId, address proposedAddress) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`proposedAddress`|`address`|Proposed reward address|


### confirmNodeOperatorRewardAddressChange

Confirm a new reward address for the Node Operator.
Should be called from the currently proposed address


```solidity
function confirmNodeOperatorRewardAddressChange(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### changeNodeOperatorRewardAddress

Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator


```solidity
function changeNodeOperatorRewardAddress(uint256 nodeOperatorId, address newAddress) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newAddress`|`address`|Proposed reward address|


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


### updateDepositableValidatorsCount

Update depositable validators data and enqueue all unqueued keys for the given Node Operator.
Unqueued stands for vetted but not enqueued keys.

The following rules are applied:
- Unbonded keys can not be depositable
- Unvetted keys can not be depositable
- Depositable keys count should respect targetLimit value


```solidity
function updateDepositableValidatorsCount(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### getNodeOperator

Get Node Operator info


```solidity
function getNodeOperator(uint256 nodeOperatorId) external view returns (NodeOperator memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`NodeOperator`|Node Operator info|


### getNodeOperatorManagementProperties

Get Node Operator management properties


```solidity
function getNodeOperatorManagementProperties(uint256 nodeOperatorId)
    external
    view
    returns (NodeOperatorManagementProperties memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`NodeOperatorManagementProperties`|Node Operator management properties|


### getNodeOperatorOwner

Get Node Operator owner. Owner is manager address if `extendedManagerPermissions` is enabled and reward address otherwise


```solidity
function getNodeOperatorOwner(uint256 nodeOperatorId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Node Operator owner|


### getNodeOperatorNonWithdrawnKeys

Get Node Operator non-withdrawn keys


```solidity
function getNodeOperatorNonWithdrawnKeys(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Non-withdrawn keys count|


### getNodeOperatorTotalDepositedKeys

Get Node Operator total deposited keys


```solidity
function getNodeOperatorTotalDepositedKeys(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total deposited keys count|


### getSigningKeys

Get Node Operator signing keys


```solidity
function getSigningKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount)
    external
    view
    returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`startIndex`|`uint256`|Index of the first key|
|`keysCount`|`uint256`|Count of keys to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|Signing keys|


### getSigningKeysWithSignatures

Get Node Operator signing keys with signatures


```solidity
function getSigningKeysWithSignatures(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount)
    external
    view
    returns (bytes memory keys, bytes memory signatures);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`startIndex`|`uint256`|Index of the first key|
|`keysCount`|`uint256`|Count of keys to get|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`keys`|`bytes`|Signing keys|
|`signatures`|`bytes`|Signatures of `(deposit_message_root, domain)` tuples https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#signingdata|


### onValidatorSlashed

Report Node Operator's key as slashed.

Called by `Verifier` contract. See `Verifier.processSlashedProof`.


```solidity
function onValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the Node Operator|
|`keyIndex`|`uint256`|The index of the validator key that was slashed|


### reportWithdrawnValidators

Report Node Operator's keys as withdrawn and charge penalties associated with exit if any.
A validator is considered withdrawn in the following cases:
- if it's an exit of a non-slashed validator, when a withdrawal of the validator is included in a beacon
block;
- if it's an exit of a slashed validator, when the committee reports such a validator as withdrawn; note
that it can happen earlier than the actual withdrawal is included on the beacon chain if the committee
decides it can account for all penalties in advance;
- if it's a consolidated validator, when the corresponding pending consolidation is processed and the
balance of the validator has been moved to another validator.

Called by `Verifier` contract.


```solidity
function reportWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`validatorInfos`|`WithdrawnValidatorInfo[]`|An array WithdrawnValidatorInfo structs|


### isValidatorSlashed

Checks if a validator was reported as slashed


```solidity
function isValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the node operator|
|`keyIndex`|`uint256`|The index of the validator key|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if a validator was reported as slashed|


### isValidatorWithdrawn

Check if the given Node Operator's key is reported as withdrawn


```solidity
function isValidatorWithdrawn(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndex`|`uint256`|index of the key to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Is validator reported as withdrawn or not|


### removeKeys

Remove keys for the Node Operator and confiscate removal charge for each deleted key
This method is a part of the Optimistic Vetting scheme. After key deletion `totalVettedKeys`
is set equal to `totalAddedKeys`. If invalid keys are not removed, the unvetting process will be repeated
and `decreaseVettedSigningKeysCount` will be called by StakingRouter.


```solidity
function removeKeys(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`startIndex`|`uint256`|Index of the first key|
|`keysCount`|`uint256`|Keys count to delete|


## Events
### NodeOperatorAdded

```solidity
event NodeOperatorAdded(
    uint256 indexed nodeOperatorId,
    address indexed managerAddress,
    address indexed rewardAddress,
    bool extendedManagerPermissions
);
```

### ReferrerSet

```solidity
event ReferrerSet(uint256 indexed nodeOperatorId, address indexed referrer);
```

### DepositableSigningKeysCountChanged

```solidity
event DepositableSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 depositableKeysCount);
```

### VettedSigningKeysCountChanged

```solidity
event VettedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 vettedKeysCount);
```

### VettedSigningKeysCountDecreased

```solidity
event VettedSigningKeysCountDecreased(uint256 indexed nodeOperatorId);
```

### DepositedSigningKeysCountChanged

```solidity
event DepositedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 depositedKeysCount);
```

### ExitedSigningKeysCountChanged

```solidity
event ExitedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 exitedKeysCount);
```

### TotalSigningKeysCountChanged

```solidity
event TotalSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 totalKeysCount);
```

### TargetValidatorsCountChanged

```solidity
event TargetValidatorsCountChanged(
    uint256 indexed nodeOperatorId, uint256 targetLimitMode, uint256 targetValidatorsCount
);
```

### WithdrawalSubmitted

```solidity
event WithdrawalSubmitted(
    uint256 indexed nodeOperatorId, uint256 keyIndex, uint256 exitBalance, uint256 slashingPenalty, bytes pubkey
);
```

### ValidatorSlashingReported

```solidity
event ValidatorSlashingReported(uint256 indexed nodeOperatorId, uint256 keyIndex, bytes pubkey);
```

### BatchEnqueued

```solidity
event BatchEnqueued(uint256 indexed queuePriority, uint256 indexed nodeOperatorId, uint256 count);
```

### KeyRemovalChargeApplied

```solidity
event KeyRemovalChargeApplied(uint256 indexed nodeOperatorId);
```

## Errors
### CannotAddKeys

```solidity
error CannotAddKeys();
```

### NodeOperatorDoesNotExist

```solidity
error NodeOperatorDoesNotExist();
```

### SenderIsNotEligible

```solidity
error SenderIsNotEligible();
```

### InvalidVetKeysPointer

```solidity
error InvalidVetKeysPointer();
```

### ExitedKeysHigherThanTotalDeposited

```solidity
error ExitedKeysHigherThanTotalDeposited();
```

### ExitedKeysDecrease

```solidity
error ExitedKeysDecrease();
```

### ZeroExitBalance

```solidity
error ZeroExitBalance();
```

### SlashingPenaltyIsNotApplicable

```solidity
error SlashingPenaltyIsNotApplicable();
```

### ValidatorSlashingAlreadyReported

```solidity
error ValidatorSlashingAlreadyReported();
```

### InvalidWithdrawnValidatorInfo

```solidity
error InvalidWithdrawnValidatorInfo();
```

### InvalidInput

```solidity
error InvalidInput();
```

### NotEnoughKeys

```solidity
error NotEnoughKeys();
```

### PriorityQueueAlreadyUsed

```solidity
error PriorityQueueAlreadyUsed();
```

### NotEligibleForPriorityQueue

```solidity
error NotEligibleForPriorityQueue();
```

### PriorityQueueMaxDepositsUsed

```solidity
error PriorityQueueMaxDepositsUsed();
```

### NoQueuedKeysToMigrate

```solidity
error NoQueuedKeysToMigrate();
```

### KeysLimitExceeded

```solidity
error KeysLimitExceeded();
```

### SigningKeysInvalidOffset

```solidity
error SigningKeysInvalidOffset();
```

### InvalidAmount

```solidity
error InvalidAmount();
```

### ZeroLocatorAddress

```solidity
error ZeroLocatorAddress();
```

### ZeroAccountingAddress

```solidity
error ZeroAccountingAddress();
```

### ZeroExitPenaltiesAddress

```solidity
error ZeroExitPenaltiesAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### ZeroSenderAddress

```solidity
error ZeroSenderAddress();
```

### ZeroParametersRegistryAddress

```solidity
error ZeroParametersRegistryAddress();
```

### DepositQueueHasUnsupportedWithdrawalCredentials

```solidity
error DepositQueueHasUnsupportedWithdrawalCredentials();
```

