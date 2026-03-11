# IBaseModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IBaseModule.sol)

**Inherits:**
[IStakingModule](/src/interfaces/IStakingModule.sol/interface.IStakingModule.md), IAccessControlEnumerable, [INOAddresses](/src/lib/NOAddresses.sol/interface.INOAddresses.md), [IAssetRecovererLib](/src/lib/AssetRecovererLib.sol/interface.IAssetRecovererLib.md)

Base module interface for repository modules such as `ICSModule` and `ICuratedModule`.


## Functions
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

### REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE


```solidity
function REPORT_REGULAR_WITHDRAWN_VALIDATORS_ROLE() external view returns (bytes32);
```

### REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE


```solidity
function REPORT_SLASHED_WITHDRAWN_VALIDATORS_ROLE() external view returns (bytes32);
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

Increases locked bond by `amount + additionalFine` for this report


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

Compensate general delayed penalty (locked bond) for the given Node Operator from Node Operator's bond

Can only be called by the Node Operator manager


```solidity
function compensateGeneralDelayedPenalty(uint256 nodeOperatorId) external;
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

Settles locked bond for eligible Node Operators

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


### updateDepositableValidatorsCount

Update depositable validators data for the given Node Operator.

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


### onNodeOperatorBondCurveChange

Notify the module about a node operator bond curve change.


```solidity
function onNodeOperatorBondCurveChange(uint256 nodeOperatorId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### requestFullDepositInfoUpdate

Request a full update of deposit info for all node operators.
Should be called after external changes that can affect deposit info such as bond curve change or parameters update.


```solidity
function requestFullDepositInfoUpdate() external;
```

### batchDepositInfoUpdate

Request a batch update of deposit info for node operators.
If `requestFullDepositInfoUpdate` was called before, the update will start from the first operator.
Otherwise, it will continue from the next operator after the last updated one.


```solidity
function batchDepositInfoUpdate(uint256 maxCount) external returns (uint256 operatorsLeft);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxCount`|`uint256`|Maximum number of operators to update in this batch|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`operatorsLeft`|`uint256`|Number of operators left to update|


### getNodeOperatorDepositInfoToUpdateCount

Get the number of Node Operators with outdated deposit info that requires update.


```solidity
function getNodeOperatorDepositInfoToUpdateCount() external view returns (uint256 count);
```

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


### reportValidatorSlashing

Report Node Operator's key as slashed.

Called by `Verifier` contract. See `Verifier.processSlashedProof`.


```solidity
function reportValidatorSlashing(uint256 nodeOperatorId, uint256 keyIndex) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the Node Operator|
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|


### reportValidatorBalance

Sync tracked added balance for a key based on proven validator balance.

The function only increases the key added value at the moment.


```solidity
function reportValidatorBalance(uint256 nodeOperatorId, uint256 keyIndex, uint256 currentBalanceWei) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|
|`currentBalanceWei`|`uint256`|Proven current validator balance in wei|


### getKeyAddedBalance

Get tracked added balance for a particular key


```solidity
function getKeyAddedBalance(uint256 nodeOperatorId, uint256 keyIndex) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`keyIndex`|`uint256`|Index of the Key in the Node Operator's keys storage|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Tracked added balance (wei)|


### reportRegularWithdrawnValidators

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
function reportRegularWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`validatorInfos`|`WithdrawnValidatorInfo[]`|An array of WithdrawnValidatorInfo structs|


### reportSlashedWithdrawnValidators

Report withdrawn validators that have been slashed.

Called by the Easy Track EVM script executor via a motion started by the dedicated committee.


```solidity
function reportSlashedWithdrawnValidators(WithdrawnValidatorInfo[] calldata validatorInfos) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`validatorInfos`|`WithdrawnValidatorInfo[]`|An array of WithdrawnValidatorInfo structs|


### isValidatorSlashed

Checks if a validator was reported as slashed


```solidity
function isValidatorSlashed(uint256 nodeOperatorId, uint256 keyIndex) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|The ID of the node operator|
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|

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
|`keyIndex`|`uint256`|Index of the key in the Node Operator's keys storage|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Is validator reported as withdrawn or not|


### removeKeys

Remove keys for the Node Operator. Charging is module-specific (e.g., CSM applies a per-key fee).
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

### ValidatorWithdrawn

```solidity
event ValidatorWithdrawn(
    uint256 indexed nodeOperatorId, uint256 keyIndex, uint256 exitBalance, uint256 slashingPenalty, bytes pubkey
);
```

### ValidatorSlashingReported

```solidity
event ValidatorSlashingReported(uint256 indexed nodeOperatorId, uint256 keyIndex, bytes pubkey);
```

### KeyAddedBalanceChanged

```solidity
event KeyAddedBalanceChanged(uint256 indexed nodeOperatorId, uint256 indexed keyIndex, uint256 newTotal);
```

### KeyRemovalChargeApplied

```solidity
event KeyRemovalChargeApplied(uint256 indexed nodeOperatorId);
```

### GeneralDelayedPenaltyReported

```solidity
event GeneralDelayedPenaltyReported(
    uint256 indexed nodeOperatorId,
    bytes32 indexed penaltyType,
    uint256 amount,
    uint256 additionalFine,
    string details
);
```

### GeneralDelayedPenaltyCancelled

```solidity
event GeneralDelayedPenaltyCancelled(uint256 indexed nodeOperatorId, uint256 amount);
```

### GeneralDelayedPenaltyCompensated

```solidity
event GeneralDelayedPenaltyCompensated(uint256 indexed nodeOperatorId, uint256 amount);
```

### GeneralDelayedPenaltySettled

```solidity
event GeneralDelayedPenaltySettled(uint256 indexed nodeOperatorId, uint256 amount);
```

### NodeOperatorDepositInfoFullyUpdated

```solidity
event NodeOperatorDepositInfoFullyUpdated();
```

### FullDepositInfoUpdateRequested

```solidity
event FullDepositInfoUpdateRequested();
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

### PubkeyMismatch

```solidity
error PubkeyMismatch();
```

### InvalidAmount

```solidity
error InvalidAmount();
```

### InvalidInput

```solidity
error InvalidInput();
```

### NotEnoughKeys

```solidity
error NotEnoughKeys();
```

### KeysLimitExceeded

```solidity
error KeysLimitExceeded();
```

### SigningKeysInvalidOffset

```solidity
error SigningKeysInvalidOffset();
```

### DepositableKeysWithUnsupportedWithdrawalCredentials

```solidity
error DepositableKeysWithUnsupportedWithdrawalCredentials();
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

### ZeroModuleType

```solidity
error ZeroModuleType();
```

### ZeroPenaltyType

```solidity
error ZeroPenaltyType();
```

### DepositInfoIsNotUpToDate

```solidity
error DepositInfoIsNotUpToDate();
```

### UnreportableBalance

```solidity
error UnreportableBalance();
```

