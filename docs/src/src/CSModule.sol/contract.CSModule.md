# CSModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/CSModule.sol)

**Inherits:**
[ICSModule](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/ICSModule.sol/interface.ICSModule.md), Initializable, AccessControlEnumerableUpgradeable, [PausableUntil](/Users/dgusakov/projects/community-staking-module/docs/src/src/lib/utils/PausableUntil.sol/contract.PausableUntil.md), [AssetRecoverer](/Users/dgusakov/projects/community-staking-module/docs/src/src/abstract/AssetRecoverer.sol/abstract.AssetRecoverer.md)


## State Variables
### PAUSE_ROLE

```solidity
bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE")
```


### RESUME_ROLE

```solidity
bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE")
```


### STAKING_ROUTER_ROLE

```solidity
bytes32 public constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE")
```


### REPORT_GENERAL_DELAYED_PENALTY_ROLE

```solidity
bytes32 public constant REPORT_GENERAL_DELAYED_PENALTY_ROLE = keccak256("REPORT_GENERAL_DELAYED_PENALTY_ROLE")
```


### SETTLE_GENERAL_DELAYED_PENALTY_ROLE

```solidity
bytes32 public constant SETTLE_GENERAL_DELAYED_PENALTY_ROLE = keccak256("SETTLE_GENERAL_DELAYED_PENALTY_ROLE")
```


### VERIFIER_ROLE

```solidity
bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE")
```


### SUBMIT_WITHDRAWALS_ROLE

```solidity
bytes32 public constant SUBMIT_WITHDRAWALS_ROLE = keccak256("SUBMIT_WITHDRAWALS_ROLE")
```


### RECOVERER_ROLE

```solidity
bytes32 public constant RECOVERER_ROLE = keccak256("RECOVERER_ROLE")
```


### CREATE_NODE_OPERATOR_ROLE

```solidity
bytes32 public constant CREATE_NODE_OPERATOR_ROLE = keccak256("CREATE_NODE_OPERATOR_ROLE")
```


### FORCED_TARGET_LIMIT_MODE_ID

```solidity
uint8 private constant FORCED_TARGET_LIMIT_MODE_ID = 2
```


### OPERATORS_CREATED_IN_TX_MAP_TSLOT

```solidity
bytes32 private constant OPERATORS_CREATED_IN_TX_MAP_TSLOT =
    0x1b07bc0838fdc4254cbabb5dd0c94d936f872c6758547168d513d8ad1dc3a500
```


### MODULE_TYPE

```solidity
bytes32 private immutable MODULE_TYPE
```


### LIDO_LOCATOR

```solidity
ILidoLocator public immutable LIDO_LOCATOR
```


### STETH

```solidity
IStETH public immutable STETH
```


### PARAMETERS_REGISTRY

```solidity
IParametersRegistry public immutable PARAMETERS_REGISTRY
```


### ACCOUNTING

```solidity
IAccounting public immutable ACCOUNTING
```


### EXIT_PENALTIES

```solidity
IExitPenalties public immutable EXIT_PENALTIES
```


### FEE_DISTRIBUTOR

```solidity
address public immutable FEE_DISTRIBUTOR
```


### QUEUE_LOWEST_PRIORITY
QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].


```solidity
uint256 public immutable QUEUE_LOWEST_PRIORITY
```


### _queueByPriority
**Notes:**
- oz-renamed-from: keyRemovalCharge

- oz-retyped-from: uint256


```solidity
mapping(uint256 queuePriority => QueueLib.Queue queue) internal _queueByPriority
```


### _legacyQueue
Unused

**Note:**
oz-renamed-from: depositQueue


```solidity
QueueLib.Queue internal _legacyQueue
```


### _accountingOld
Unused. Nullified in the finalizeUpgradeV2

**Note:**
oz-renamed-from: accounting


```solidity
IAccounting internal _accountingOld
```


### _earlyAdoption
Unused. Nullified in v2 upgrade

**Note:**
oz-renamed-from: earlyAdoption


```solidity
address internal _earlyAdoption
```


### _publicRelease
deprecated. Nullified in v2 upgrade

**Note:**
oz-renamed-from: publicRelease


```solidity
bool internal _publicRelease
```


### _nonce

```solidity
uint256 private _nonce
```


### _nodeOperators

```solidity
mapping(uint256 => NodeOperator) internal _nodeOperators
```


### _isValidatorWithdrawn
see _keyPointer function for details of noKeyIndexPacked structure


```solidity
mapping(uint256 noKeyIndexPacked => bool) private _isValidatorWithdrawn
```


### _isValidatorSlashed

```solidity
mapping(uint256 noKeyIndexPacked => bool) private _isValidatorSlashed
```


### _totalDepositedValidators

```solidity
uint64 private _totalDepositedValidators
```


### _totalExitedValidators

```solidity
uint64 private _totalExitedValidators
```


### _depositableValidatorsCount

```solidity
uint64 private _depositableValidatorsCount
```


### _nodeOperatorsCount

```solidity
uint64 private _nodeOperatorsCount
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
) ;
```

### initialize

initialize the module from scratch


```solidity
function initialize(address admin) external reinitializer(2);
```

### finalizeUpgradeV2

This method is expected to be called only when the contract is upgraded from version 1 to version 2 for the existing version 1 deployment.
If the version 2 contract is deployed from scratch, the `initialize` method should be used instead.


```solidity
function finalizeUpgradeV2() external reinitializer(2);
```

### resume

Resume creation of the Node Operators and keys upload


```solidity
function resume() external onlyRole(RESUME_ROLE);
```

### pauseFor

Pause creation of the Node Operators and keys upload for `duration` seconds.
Existing NO management and reward claims are still available.
To pause reward claims use pause method on Accounting


```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSE_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### createNodeOperator

Permissioned method to add a new Node Operator
Should be called by `*Gate.sol` contracts. See `PermissionlessGate.sol` and `VettedGate.sol` for examples


```solidity
function createNodeOperator(
    address from,
    NodeOperatorManagementProperties calldata managementProperties,
    address referrer
) external onlyRole(CREATE_NODE_OPERATOR_ROLE) whenResumed returns (uint256 nodeOperatorId);
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
    bytes calldata publicKeys,
    bytes calldata signatures
) external payable whenResumed;
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


```solidity
function addValidatorKeysStETH(
    address from,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures,
    IAccounting.PermitInput calldata permit
) external whenResumed;
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


```solidity
function addValidatorKeysWstETH(
    address from,
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures,
    IAccounting.PermitInput calldata permit
) external whenResumed;
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


### onRewardsMinted

Called by StakingRouter to signal that stETH rewards were minted for this module.

Passes through the minted stETH shares to the fee distributor


```solidity
function onRewardsMinted(uint256 totalShares) external onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`totalShares`|`uint256`|Amount of stETH shares that were minted to reward all node operators.|


### updateExitedValidatorsCount

Updates the number of the validators in the EXITED state for node operator with given id


```solidity
function updateExitedValidatorsCount(bytes calldata nodeOperatorIds, bytes calldata exitedValidatorsCounts)
    external
    onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`bytes`|bytes packed array of the node operators id|
|`exitedValidatorsCounts`|`bytes`|bytes packed array of the new number of EXITED validators for the node operators|


### updateTargetValidatorsLimits

Updates the limit of the validators that can be used for deposit


```solidity
function updateTargetValidatorsLimits(uint256 nodeOperatorId, uint256 targetLimitMode, uint256 targetLimit)
    external
    onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`targetLimitMode`|`uint256`|Target limit mode for the Node Operator (see https://hackmd.io/@lido/BJXRTxMRp) 0 - disabled 1 - soft mode 2 - forced mode|
|`targetLimit`|`uint256`|Target limit of validators|


### onExitedAndStuckValidatorsCountsUpdated

Called by StakingRouter after it finishes updating exited and stuck validators
counts for this module's node operators.
Guaranteed to be called after an oracle report is applied, regardless of whether any node
operator in this module has actually received any updated counts as a result of the report
but given that the total number of exited validators returned from getStakingModuleSummary
is the same as StakingRouter expects based on the total count received from the oracle.

This method is not used in CSM, hence it does nothing

NOTE: No role checks because of empty body to save bytecode.


```solidity
function onExitedAndStuckValidatorsCountsUpdated() external;
```

### unsafeUpdateValidatorsCount

TODO: Figure out if we can remove the body of this function to save bytecode


```solidity
function unsafeUpdateValidatorsCount(uint256 nodeOperatorId, uint256 exitedValidatorsKeysCount)
    external
    onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`||
|`exitedValidatorsKeysCount`|`uint256`||


### decreaseVettedSigningKeysCount

Called by StakingRouter to decrease the number of vetted keys for Node Operators with given ids


```solidity
function decreaseVettedSigningKeysCount(bytes calldata nodeOperatorIds, bytes calldata vettedSigningKeysCounts)
    external
    onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`bytes`|Bytes packed array of the Node Operator ids|
|`vettedSigningKeysCounts`|`bytes`|Bytes packed array of the new numbers of vetted keys for the Node Operators|


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


### reportGeneralDelayedPenalty

Report general delayed penalty for the given Node Operator


```solidity
function reportGeneralDelayedPenalty(
    uint256 nodeOperatorId,
    bytes32 penaltyType,
    uint256 amount,
    string calldata details
) external onlyRole(REPORT_GENERAL_DELAYED_PENALTY_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`penaltyType`|`bytes32`|Type of the penalty|
|`amount`|`uint256`|Penalty amount in ETH|
|`details`|`string`|Additional details about the penalty|


### cancelGeneralDelayedPenalty

Cancel previously reported and not settled general delayed penalty for the given Node Operator


```solidity
function cancelGeneralDelayedPenalty(uint256 nodeOperatorId, uint256 amount)
    external
    onlyRole(REPORT_GENERAL_DELAYED_PENALTY_ROLE);
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
function settleGeneralDelayedPenalty(uint256[] calldata nodeOperatorIds, uint256[] calldata maxAmounts)
    external
    onlyRole(SETTLE_GENERAL_DELAYED_PENALTY_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`uint256[]`|IDs of the Node Operators|
|`maxAmounts`|`uint256[]`|Maximum amounts to settle for each Node Operator|


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


### onValidatorSlashed

Report Node Operator's key as slashed.


```solidity
function onValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external onlyRole(VERIFIER_ROLE);
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


```solidity
function reportWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos)
    external
    onlyRole(SUBMIT_WITHDRAWALS_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`validatorInfos`|`WithdrawnValidatorInfo[]`|An array WithdrawnValidatorInfo structs|


### reportValidatorExitDelay

Handles tracking and penalization logic for a validator that remains active beyond its eligible exit window.

This function is called by the StakingRouter to report the current exit-related status of a validator
belonging to a specific node operator. It accepts a validator's public key, associated
with the duration (in seconds) it was eligible to exit but has not exited.
This data could be used to trigger penalties for the node operator if the validator has exceeded the allowed exit window.


```solidity
function reportValidatorExitDelay(
    uint256 nodeOperatorId,
    uint256,
    /* proofSlotTimestamp */
    bytes calldata publicKey,
    uint256 eligibleToExitInSec
) external onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`||
|`<none>`|`uint256`||
|`publicKey`|`bytes`||
|`eligibleToExitInSec`|`uint256`||


### onValidatorExitTriggered

Handles the triggerable exit event for a validator belonging to a specific node operator.

This function is called by the StakingRouter when a validator is exited using the triggerable
exit request on the Execution Layer (EL).


```solidity
function onValidatorExitTriggered(
    uint256 nodeOperatorId,
    bytes calldata publicKey,
    uint256 withdrawalRequestPaidFee,
    uint256 exitType
) external onlyRole(STAKING_ROUTER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`||
|`publicKey`|`bytes`||
|`withdrawalRequestPaidFee`|`uint256`||
|`exitType`|`uint256`||


### onWithdrawalCredentialsChanged

Called by StakingRouter when withdrawal credentials are changed.

Changing the WC means that the current deposit data in the queue is not valid anymore and can't be deposited.
If there are depositable validators in the queue, the method should revert to prevent deposits with invalid
withdrawal credentials.


```solidity
function onWithdrawalCredentialsChanged() external onlyRole(STAKING_ROUTER_ROLE);
```

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
    virtual
    onlyRole(STAKING_ROUTER_ROLE)
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


### getInitializedVersion

Returns the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

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


### getType

Returns the type of the staking module


```solidity
function getType() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Module type|


### getStakingModuleSummary

Returns all-validators summary in the staking module


```solidity
function getStakingModuleSummary()
    external
    view
    returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalExitedValidators`|`uint256`|total number of validators in the EXITED state on the Consensus Layer. This value can't decrease in normal conditions|
|`totalDepositedValidators`|`uint256`|total number of validators deposited via the official Deposit Contract. This value is a cumulative counter: even when the validator goes into EXITED state this counter is not decreasing|
|`depositableValidatorsCount`|`uint256`|number of validators in the set available for deposit|


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


### getNodeOperatorSummary

depositableValidatorsCount depends on:
- totalVettedKeys
- totalDepositedKeys
- totalExitedKeys
- targetLimitMode
- targetValidatorsCount
- totalUnbondedKeys


```solidity
function getNodeOperatorSummary(uint256 nodeOperatorId)
    external
    view
    returns (
        uint256 targetLimitMode,
        uint256 targetValidatorsCount,
        uint256 stuckValidatorsCount,
        uint256 refundedValidatorsCount,
        uint256 stuckPenaltyEndTimestamp,
        uint256 totalExitedValidators,
        uint256 totalDepositedValidators,
        uint256 depositableValidatorsCount
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|id of the operator to return report for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`targetLimitMode`|`uint256`|shows whether the current target limit applied to the node operator (1 = soft mode, 2 = forced mode)|
|`targetValidatorsCount`|`uint256`|relative target active validators limit for operator|
|`stuckValidatorsCount`|`uint256`|number of validators with an expired request to exit time|
|`refundedValidatorsCount`|`uint256`|number of validators that can't be withdrawn, but deposit costs were compensated to the Lido by the node operator|
|`stuckPenaltyEndTimestamp`|`uint256`|time when the penalty for stuck validators stops applying to node operator rewards|
|`totalExitedValidators`|`uint256`|total number of validators in the EXITED state on the Consensus Layer. This value can't decrease in normal conditions|
|`totalDepositedValidators`|`uint256`|total number of validators deposited via the official Deposit Contract. This value is a cumulative counter: even when the validator goes into EXITED state this counter is not decreasing|
|`depositableValidatorsCount`|`uint256`|number of validators in the set available for deposit|


### getNodeOperatorTotalDepositedKeys

Get Node Operator total deposited keys


```solidity
function getNodeOperatorTotalDepositedKeys(uint256 nodeOperatorId)
    external
    view
    returns (uint256 totalDepositedKeys);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalDepositedKeys`|`uint256`|Total deposited keys count|


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


### getNonce

Returns a counter that MUST change its value whenever the deposit data set changes.
Below is the typical list of actions that requires an update of the nonce:
1. a node operator's deposit data is added
2. a node operator's deposit data is removed
3. a node operator's ready-to-deposit data size is changed
4. a node operator was activated/deactivated
5. a node operator's deposit data is used for the deposit
Note: Depending on the StakingModule implementation above list might be extended

In some scenarios, it's allowed to update nonce without actual change of the deposit
data subset, but it MUST NOT lead to the DOS of the staking module via continuous
update of the nonce by the malicious actor


```solidity
function getNonce() external view returns (uint256);
```

### getNodeOperatorsCount

Returns total number of node operators


```solidity
function getNodeOperatorsCount() external view returns (uint256);
```

### getActiveNodeOperatorsCount

Returns number of active node operators


```solidity
function getActiveNodeOperatorsCount() external view returns (uint256);
```

### getNodeOperatorIsActive

Returns if the node operator with given id is active


```solidity
function getNodeOperatorIsActive(uint256 nodeOperatorId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Id of the node operator|


### getNodeOperatorIds

Returns up to `limit` node operator ids starting from the `offset`. The order of
the returned ids is not defined and might change between calls.

This view must not revert in case of invalid data passed. When `offset` exceeds the
total node operators count or when `limit` is equal to 0 MUST be returned empty array.


```solidity
function getNodeOperatorIds(uint256 offset, uint256 limit)
    external
    view
    returns (uint256[] memory nodeOperatorIds);
```

### isValidatorExitDelayPenaltyApplicable

Determines whether a validator's exit status should be updated and will have an effect on the Node Operator.


```solidity
function isValidatorExitDelayPenaltyApplicable(
    uint256 nodeOperatorId,
    uint256,
    /* proofSlotTimestamp */
    bytes calldata publicKey,
    uint256 eligibleToExitInSec
) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`||
|`<none>`|`uint256`||
|`publicKey`|`bytes`||
|`eligibleToExitInSec`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Returns true if the contract should receive the updated status of the validator.|


### exitDeadlineThreshold

Returns the number of seconds after which a validator is considered late.


```solidity
function exitDeadlineThreshold(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The exit deadline threshold in seconds.|


### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(AccessControlEnumerableUpgradeable)
    returns (bool);
```

### _incrementModuleNonce


```solidity
function _incrementModuleNonce() internal;
```

### _onUncompensatedPenalty


```solidity
function _onUncompensatedPenalty(uint256 nodeOperatorId) internal;
```

### _addKeysAndUpdateDepositableValidatorsCount


```solidity
function _addKeysAndUpdateDepositableValidatorsCount(
    uint256 nodeOperatorId,
    uint256 keysCount,
    bytes calldata publicKeys,
    bytes calldata signatures
) internal;
```

### _updateExitedValidatorsCount

TODO: Figure out if we can remove this method

Update exited validators count for a single Node Operator

Allows decrease the count for unsafe updates


```solidity
function _updateExitedValidatorsCount(uint256 nodeOperatorId, uint256 exitedValidatorsCount, bool allowDecrease)
    internal;
```

### _updateDepositableValidatorsCount


```solidity
function _updateDepositableValidatorsCount(uint256 nodeOperatorId, bool incrementNonceIfUpdated) internal;
```

### _enqueueNodeOperatorKeys


```solidity
function _enqueueNodeOperatorKeys(uint256 nodeOperatorId) internal;
```

### _enqueueNodeOperatorKeys


```solidity
function _enqueueNodeOperatorKeys(uint256 nodeOperatorId, uint256 queuePriority, uint32 count) internal;
```

### _recordOperatorCreator


```solidity
function _recordOperatorCreator(uint256 nodeOperatorId) internal;
```

### _forgetOperatorCreator


```solidity
function _forgetOperatorCreator(uint256 nodeOperatorId) internal;
```

### _setTargetLimit


```solidity
function _setTargetLimit(uint256 nodeOperatorId, uint256 targetLimitMode, uint256 targetLimit) internal;
```

### _getOperatorCreator


```solidity
function _getOperatorCreator(uint256 nodeOperatorId) internal view returns (address);
```

### _checkCanAddKeys


```solidity
function _checkCanAddKeys(uint256 nodeOperatorId, address who) internal view;
```

### _onlyNodeOperatorManager


```solidity
function _onlyNodeOperatorManager(uint256 nodeOperatorId, address from) internal view;
```

### _onlyExistingNodeOperator


```solidity
function _onlyExistingNodeOperator(uint256 nodeOperatorId) internal view;
```

### _onlyValidIndexRange


```solidity
function _onlyValidIndexRange(uint256 nodeOperatorId, uint256 startIndex, uint256 keysCount) internal view;
```

### _getBondCurveId


```solidity
function _getBondCurveId(uint256 nodeOperatorId) internal view returns (uint256);
```

### _accounting

This function is used to get the accounting contract from immutables to save bytecode.


```solidity
function _accounting() internal view returns (IAccounting);
```

### _onlyRecoverer


```solidity
function _onlyRecoverer() internal view override;
```

### _keyPointer

Both nodeOperatorId and keyIndex are limited to uint64 by the contract


```solidity
function _keyPointer(uint256 nodeOperatorId, uint256 keyIndex) internal pure returns (uint256);
```

