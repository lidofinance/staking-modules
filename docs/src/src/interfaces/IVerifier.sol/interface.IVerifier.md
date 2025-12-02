# IVerifier
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IVerifier.sol)


## Functions
### PAUSE_ROLE


```solidity
function PAUSE_ROLE() external view returns (bytes32);
```

### RESUME_ROLE


```solidity
function RESUME_ROLE() external view returns (bytes32);
```

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
function MODULE() external view returns (ICSModule);
```

### pauseFor

Pause write methods calls for `duration` seconds


```solidity
function pauseFor(uint256 duration) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`duration`|`uint256`|Duration of the pause in seconds|


### resume

Resume write methods calls


```solidity
function resume() external;
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
determining the exact penalty amounts and calling the `ICSModule.reportWithdrawnValidators` method via an EasyTrack
motion.


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
determining the exact penalty amounts and calling the `ICSModule.reportWithdrawnValidators` method via an EasyTrack
motion.


```solidity
function processHistoricalWithdrawalProof(ProcessHistoricalWithdrawalInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessHistoricalWithdrawalInput`|@see ProcessHistoricalWithdrawalInput|


### processConsolidation

Processes a validator's consolidation from a module's validator. The balance before consolidation is
assumed to be the withdrawal balance.

The caveat is that a pending consolidation is processed later, making it impossible to account for losses
or rewards during the waiting period, as there's no indication of consolidation processing in the state.


```solidity
function processConsolidation(ProcessConsolidationInput calldata data) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessConsolidationInput`|@see ProcessConsolidationInput|


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

### InvalidConsolidationSource

```solidity
error InvalidConsolidationSource();
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
    GIndex gIFirstPendingConsolidationPrev;
    GIndex gIFirstPendingConsolidationCurr;
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

### PendingConsolidationWitness

```solidity
struct PendingConsolidationWitness {
    PendingConsolidation object;
    uint64 offset; // in the list of pending consolidations
    bytes32[] proof;
}
```

### ProcessConsolidationInput

```solidity
struct ProcessConsolidationInput {
    PendingConsolidationWitness consolidation;
    ValidatorWitness validator;
    // Represents the validator's balance before the CL processes the pending consolidation. Used as a proxy for the
    // "withdrawal balance" in accounting/penalties, since consolidation is not an EL withdrawal.
    BalanceWitness balance;
    RecentHeaderWitness recentBlock;
    HistoricalHeaderWitness consolidationBlock;
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

