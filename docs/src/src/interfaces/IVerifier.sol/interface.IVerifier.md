# IVerifier
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IVerifier.sol)


## Functions
### BEACON_ROOTS


```solidity
function BEACON_ROOTS() external view returns (address);
```

### SLOTS_PER_EPOCH


```solidity
function SLOTS_PER_EPOCH() external view returns (uint64);
```

### SLOTS_PER_HISTORICAL_ROOT


```solidity
function SLOTS_PER_HISTORICAL_ROOT() external view returns (uint64);
```

### GI_FIRST_WITHDRAWAL_PREV


```solidity
function GI_FIRST_WITHDRAWAL_PREV() external view returns (GIndex);
```

### GI_FIRST_WITHDRAWAL_CURR


```solidity
function GI_FIRST_WITHDRAWAL_CURR() external view returns (GIndex);
```

### GI_FIRST_VALIDATOR_PREV


```solidity
function GI_FIRST_VALIDATOR_PREV() external view returns (GIndex);
```

### GI_FIRST_VALIDATOR_CURR


```solidity
function GI_FIRST_VALIDATOR_CURR() external view returns (GIndex);
```

### GI_FIRST_HISTORICAL_SUMMARY_PREV


```solidity
function GI_FIRST_HISTORICAL_SUMMARY_PREV() external view returns (GIndex);
```

### GI_FIRST_HISTORICAL_SUMMARY_CURR


```solidity
function GI_FIRST_HISTORICAL_SUMMARY_CURR() external view returns (GIndex);
```

### GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV


```solidity
function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV() external view returns (GIndex);
```

### GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR


```solidity
function GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR() external view returns (GIndex);
```

### FIRST_SUPPORTED_SLOT


```solidity
function FIRST_SUPPORTED_SLOT() external view returns (Slot);
```

### PIVOT_SLOT


```solidity
function PIVOT_SLOT() external view returns (Slot);
```

### CAPELLA_SLOT


```solidity
function CAPELLA_SLOT() external view returns (Slot);
```

### WITHDRAWAL_ADDRESS


```solidity
function WITHDRAWAL_ADDRESS() external view returns (address);
```

### MODULE


```solidity
function MODULE() external view returns (IBaseModule);
```

### processSlashedProof

Verify proof of a slashed validator being withdrawable and report it to the module


```solidity
function processSlashedProof(ProcessSlashedInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessSlashedInput`|@see ProcessSlashedInput|


### processWithdrawalProof

Verify withdrawal proof and report withdrawal to the module for valid proofs

The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
determining the exact penalty amounts and calling the `IBaseModule.reportSlashedWithdrawnValidators` method via
an EasyTrack motion.


```solidity
function processWithdrawalProof(ProcessWithdrawalInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessWithdrawalInput`|@see ProcessWithdrawalInput|


### processHistoricalWithdrawalProof

Verify withdrawal proof against historical summaries data and report withdrawal to the module for valid proofs

The method doesn't accept proofs for slashed validators. A dedicated committee is responsible for
determining the exact penalty amounts and calling the `IBaseModule.reportSlashedWithdrawnValidators` method via
an EasyTrack motion.


```solidity
function processHistoricalWithdrawalProof(ProcessHistoricalWithdrawalInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessHistoricalWithdrawalInput`|@see ProcessHistoricalWithdrawalInput|


### processBalanceProof

Verify a validator's balance proof from a recent beacon block and sync the key added balance.


```solidity
function processBalanceProof(ProcessBalanceProofInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessBalanceProofInput`|The balance proof input containing recent block header, validator witness, and balance witness.|


### processHistoricalBalanceProof

Verify a validator's balance proof from a historical beacon block and sync the key added balance.
A historical proof is needed because the validator's balance may have increased at some point in the past
and later decreased (e.g. due to inactivity leak or penalties). A recent proof alone would miss that peak,
so a historical proof allows capturing the highest observed balance.


```solidity
function processHistoricalBalanceProof(ProcessHistoricalBalanceProofInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessHistoricalBalanceProofInput`|The balance proof input containing recent + historical block headers, validator witness, and balance witness.|


## Errors
### RootNotFound

```solidity
error RootNotFound();
```

### InvalidBlockHeader

```solidity
error InvalidBlockHeader();
```

### InvalidChainConfig

```solidity
error InvalidChainConfig();
```

### PartialWithdrawal

```solidity
error PartialWithdrawal();
```

### ValidatorIsSlashed

```solidity
error ValidatorIsSlashed();
```

### ValidatorIsNotSlashed

```solidity
error ValidatorIsNotSlashed();
```

### ValidatorIsNotWithdrawable

```solidity
error ValidatorIsNotWithdrawable();
```

### InvalidWithdrawalAddress

```solidity
error InvalidWithdrawalAddress();
```

### InvalidPublicKey

```solidity
error InvalidPublicKey();
```

### InvalidValidatorIndex

```solidity
error InvalidValidatorIndex();
```

### UnsupportedSlot

```solidity
error UnsupportedSlot(Slot slot);
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroWithdrawalAddress

```solidity
error ZeroWithdrawalAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### InvalidPivotSlot

```solidity
error InvalidPivotSlot();
```

### InvalidCapellaSlot

```solidity
error InvalidCapellaSlot();
```

### HistoricalSummaryDoesNotExist

```solidity
error HistoricalSummaryDoesNotExist();
```

## Structs
### GIndices

```solidity
struct GIndices {
    GIndex gIFirstWithdrawalPrev;
    GIndex gIFirstWithdrawalCurr;
    GIndex gIFirstValidatorPrev;
    GIndex gIFirstValidatorCurr;
    GIndex gIFirstHistoricalSummaryPrev;
    GIndex gIFirstHistoricalSummaryCurr;
    GIndex gIFirstBlockRootInSummaryPrev;
    GIndex gIFirstBlockRootInSummaryCurr;
    GIndex gIFirstBalanceNodePrev;
    GIndex gIFirstBalanceNodeCurr;
}
```

### RecentHeaderWitness

```solidity
struct RecentHeaderWitness {
    BeaconBlockHeader header; // Header of a block which root is a root at rootsTimestamp.
    uint64 rootsTimestamp; // To be passed to the EIP-4788 block roots contract.
}
```

### HistoricalHeaderWitness

```solidity
struct HistoricalHeaderWitness {
    BeaconBlockHeader header;
    bytes32[] proof;
}
```

### WithdrawalWitness

```solidity
struct WithdrawalWitness {
    uint8 offset; // In the withdrawals list.
    Withdrawal object;
    bytes32[] proof;
}
```

### ValidatorWitness

```solidity
struct ValidatorWitness {
    uint64 index; // Index of a validator in a Beacon state.
    uint32 nodeOperatorId;
    uint32 keyIndex; // Index of the withdrawn key in the Node Operator's keys storage.
    Validator object;
    bytes32[] proof;
}
```

### BalanceWitness

```solidity
struct BalanceWitness {
    bytes32 node;
    bytes32[] proof;
}
```

### ProcessSlashedInput

```solidity
struct ProcessSlashedInput {
    ValidatorWitness validator;
    RecentHeaderWitness recentBlock;
}
```

### ProcessWithdrawalInput

```solidity
struct ProcessWithdrawalInput {
    WithdrawalWitness withdrawal;
    ValidatorWitness validator;
    RecentHeaderWitness withdrawalBlock;
}
```

### ProcessHistoricalWithdrawalInput

```solidity
struct ProcessHistoricalWithdrawalInput {
    WithdrawalWitness withdrawal;
    ValidatorWitness validator;
    RecentHeaderWitness recentBlock;
    HistoricalHeaderWitness withdrawalBlock;
}
```

### ProcessBalanceProofInput

```solidity
struct ProcessBalanceProofInput {
    RecentHeaderWitness recentBlock;
    ValidatorWitness validator;
    BalanceWitness balance;
}
```

### ProcessHistoricalBalanceProofInput

```solidity
struct ProcessHistoricalBalanceProofInput {
    RecentHeaderWitness recentBlock;
    HistoricalHeaderWitness historicalBlock;
    ValidatorWitness validator;
    BalanceWitness balance;
}
```

