# IStakingModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IStakingModule.sol)

**Title:**
Lido's Staking Module interface


## Functions
### reportValidatorExitDelay

Handles tracking and penalization logic for a validator that remains active beyond its eligible exit window.

This function is called by the StakingRouter to report the current exit-related status of a validator
belonging to a specific node operator. It accepts a validator's public key, associated
with the duration (in seconds) it was eligible to exit but has not exited.
This data could be used to trigger penalties for the node operator if the validator has exceeded the allowed exit window.


```solidity
function reportValidatorExitDelay(
    uint256 _nodeOperatorId,
    uint256 _proofSlotTimestamp,
    bytes calldata _publicKey,
    uint256 _eligibleToExitInSec
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|The ID of the node operator whose validator's status is being delivered.|
|`_proofSlotTimestamp`|`uint256`|The timestamp (slot time) when the validator was last known to be in an active ongoing state.|
|`_publicKey`|`bytes`|The public key of the validator being reported.|
|`_eligibleToExitInSec`|`uint256`|The duration (in seconds) indicating how long the validator has been eligible to exit but has not exited.|


### onValidatorExitTriggered

Handles the triggerable exit event for a validator belonging to a specific node operator.

This function is called by the StakingRouter when a validator is exited using the triggerable
exit request on the Execution Layer (EL).


```solidity
function onValidatorExitTriggered(
    uint256 _nodeOperatorId,
    bytes calldata _publicKey,
    uint256 _withdrawalRequestPaidFee,
    uint256 _exitType
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|The ID of the node operator.|
|`_publicKey`|`bytes`|The public key of the validator being reported.|
|`_withdrawalRequestPaidFee`|`uint256`|Fee amount paid to send a withdrawal request on the Execution Layer (EL).|
|`_exitType`|`uint256`|The type of exit being performed. This parameter may be interpreted differently across various staking modules, depending on their specific implementation.|


### isValidatorExitDelayPenaltyApplicable

Determines whether a validator's exit status should be updated and will have an effect on the Node Operator.


```solidity
function isValidatorExitDelayPenaltyApplicable(
    uint256 _nodeOperatorId,
    uint256 _proofSlotTimestamp,
    bytes calldata _publicKey,
    uint256 _eligibleToExitInSec
) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|The ID of the node operator.|
|`_proofSlotTimestamp`|`uint256`|The timestamp (slot time) when the validator was last known to be in an active ongoing state.|
|`_publicKey`|`bytes`|The public key of the validator.|
|`_eligibleToExitInSec`|`uint256`|The number of seconds the validator was eligible to exit but did not.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Returns true if the contract should receive the updated status of the validator.|


### exitDeadlineThreshold

Returns the number of seconds after which a validator is considered late.


```solidity
function exitDeadlineThreshold(uint256 _nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|The ID of the node operator.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The exit deadline threshold in seconds.|


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


### getNodeOperatorSummary

Returns all-validators summary belonging to the node operator with the given id


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
function getNodeOperatorIds(uint256 offset, uint256 limit) external view returns (uint256[] memory nodeOperatorIds);
```

### onRewardsMinted

Called by StakingRouter to signal that stETH rewards were minted for this module.

IMPORTANT: this method SHOULD revert with empty error data ONLY because of "out of gas".
Details about error data: https://docs.soliditylang.org/en/v0.8.9/control-structures.html#error-handling-assert-require-revert-and-exceptions


```solidity
function onRewardsMinted(uint256 totalShares) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`totalShares`|`uint256`|Amount of stETH shares that were minted to reward all node operators.|


### decreaseVettedSigningKeysCount

Called by StakingRouter to decrease the number of vetted keys for Node Operators with given ids


```solidity
function decreaseVettedSigningKeysCount(bytes calldata nodeOperatorIds, bytes calldata vettedSigningKeysCounts)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`bytes`|Bytes packed array of the Node Operator ids|
|`vettedSigningKeysCounts`|`bytes`|Bytes packed array of the new numbers of vetted keys for the Node Operators|


### updateExitedValidatorsCount

Updates the number of the validators in the EXITED state for node operator with given id


```solidity
function updateExitedValidatorsCount(bytes calldata nodeOperatorIds, bytes calldata exitedValidatorsCounts) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorIds`|`bytes`|bytes packed array of the node operators id|
|`exitedValidatorsCounts`|`bytes`|bytes packed array of the new number of EXITED validators for the node operators|


### updateTargetValidatorsLimits

Updates the limit of the validators that can be used for deposit


```solidity
function updateTargetValidatorsLimits(uint256 nodeOperatorId, uint256 targetLimitMode, uint256 targetLimit) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`targetLimitMode`|`uint256`|Target limit mode for the Node Operator (see https://hackmd.io/@lido/BJXRTxMRp) 0 - disabled 1 - soft mode 2 - forced mode|
|`targetLimit`|`uint256`|Target limit of validators|


### unsafeUpdateValidatorsCount

Unsafely updates the number of validators in the EXITED/STUCK states for node operator with given id
'unsafely' means that this method can both increase and decrease exited and stuck counters


```solidity
function unsafeUpdateValidatorsCount(uint256 _nodeOperatorId, uint256 _exitedValidatorsCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|Id of the node operator|
|`_exitedValidatorsCount`|`uint256`|New number of EXITED validators for the node operator|


### obtainDepositData

Obtains deposit data to be used by StakingRouter to deposit to the Ethereum Deposit
contract


```solidity
function obtainDepositData(uint256 depositsCount, bytes calldata depositCalldata)
    external
    returns (bytes memory publicKeys, bytes memory signatures);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`depositsCount`|`uint256`|Number of deposits to be done|
|`depositCalldata`|`bytes`|Staking module defined data encoded as bytes. IMPORTANT: depositCalldata MUST NOT modify the deposit data set of the staking module|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`publicKeys`|`bytes`|Batch of the concatenated public validators keys|
|`signatures`|`bytes`|Batch of the concatenated deposit signatures for returned public keys|


### onExitedAndStuckValidatorsCountsUpdated

Called by StakingRouter after it finishes updating exited and stuck validators
counts for this module's node operators.
Guaranteed to be called after an oracle report is applied, regardless of whether any node
operator in this module has actually received any updated counts as a result of the report
but given that the total number of exited validators returned from getStakingModuleSummary
is the same as StakingRouter expects based on the total count received from the oracle.

IMPORTANT: this method SHOULD revert with empty error data ONLY because of "out of gas".
Details about error data: https://docs.soliditylang.org/en/v0.8.9/control-structures.html#error-handling-assert-require-revert-and-exceptions


```solidity
function onExitedAndStuckValidatorsCountsUpdated() external;
```

### onWithdrawalCredentialsChanged

Called by StakingRouter when withdrawal credentials are changed.

This method MUST discard all StakingModule's unused deposit data cause they become
invalid after the withdrawal credentials are changed

IMPORTANT: this method SHOULD revert with empty error data ONLY because of "out of gas".
Details about error data: https://docs.soliditylang.org/en/v0.8.9/control-structures.html#error-handling-assert-require-revert-and-exceptions


```solidity
function onWithdrawalCredentialsChanged() external;
```

## Events
### NonceChanged
Event to be emitted on StakingModule's nonce change


```solidity
event NonceChanged(uint256 nonce);
```

### SigningKeyAdded
Event to be emitted when a signing key is added to the StakingModule


```solidity
event SigningKeyAdded(uint256 indexed nodeOperatorId, bytes pubkey);
```

### SigningKeyRemoved
Event to be emitted when a signing key is removed from the StakingModule


```solidity
event SigningKeyRemoved(uint256 indexed nodeOperatorId, bytes pubkey);
```

