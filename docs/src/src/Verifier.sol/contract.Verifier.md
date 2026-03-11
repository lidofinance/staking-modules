# Verifier
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/Verifier.sol)

**Inherits:**
[IVerifier](/src/interfaces/IVerifier.sol/interface.IVerifier.md), AccessControlEnumerable, [PausableWithRoles](/src/abstract/PausableWithRoles.sol/abstract.PausableWithRoles.md)


## State Variables
### BEACON_ROOTS

```solidity
address public constant BEACON_ROOTS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02
```


### MAX_BP

```solidity
uint256 internal constant MAX_BP = 10_000
```


### MIN_WITHDRAWAL_RATIO
Minimum withdrawal amount as a ratio of total ether deposited to the validator,
expressed in basis points (10 000 = 100%). At ~3% top APY, losing >10% of balance
requires ~3 years offline — implausible for any legitimately run validator.
We do not accept slashed validators in normal withdrawal processing, so we do not need to account for slashing penalties here.
In case of unexpected network conditions, the DAO can always replace the verifier contract with one having a different threshold.


```solidity
uint256 internal constant MIN_WITHDRAWAL_RATIO = 9000
```


### SLOTS_PER_EPOCH

```solidity
uint64 public immutable SLOTS_PER_EPOCH
```


### SLOTS_PER_HISTORICAL_ROOT
Count of historical roots per accumulator.

See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters


```solidity
uint64 public immutable SLOTS_PER_HISTORICAL_ROOT
```


### GI_FIRST_WITHDRAWAL_PREV
This index is relative to a state like: `BeaconState.latest_execution_payload_header.withdrawals[0]`.


```solidity
GIndex public immutable GI_FIRST_WITHDRAWAL_PREV
```


### GI_FIRST_WITHDRAWAL_CURR
This index is relative to a state like: `BeaconState.latest_execution_payload_header.withdrawals[0]`.


```solidity
GIndex public immutable GI_FIRST_WITHDRAWAL_CURR
```


### GI_FIRST_VALIDATOR_PREV
This index is relative to a state like: `BeaconState.validators[0]`.


```solidity
GIndex public immutable GI_FIRST_VALIDATOR_PREV
```


### GI_FIRST_VALIDATOR_CURR
This index is relative to a state like: `BeaconState.validators[0]`.


```solidity
GIndex public immutable GI_FIRST_VALIDATOR_CURR
```


### GI_FIRST_HISTORICAL_SUMMARY_PREV
This index is relative to a state like: `BeaconState.historical_summaries[0]`.


```solidity
GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_PREV
```


### GI_FIRST_HISTORICAL_SUMMARY_CURR
This index is relative to a state like: `BeaconState.historical_summaries[0]`.


```solidity
GIndex public immutable GI_FIRST_HISTORICAL_SUMMARY_CURR
```


### GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV
This index is relative to HistoricalSummary like: HistoricalSummary.blockRoots[0].


```solidity
GIndex public immutable GI_FIRST_BLOCK_ROOT_IN_SUMMARY_PREV
```


### GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR
This index is relative to HistoricalSummary like: HistoricalSummary.blockRoots[0].


```solidity
GIndex public immutable GI_FIRST_BLOCK_ROOT_IN_SUMMARY_CURR
```


### GI_FIRST_BALANCES_NODE_PREV
This index is relative to a state like: `BeaconState.balances[0]`.


```solidity
GIndex public immutable GI_FIRST_BALANCES_NODE_PREV
```


### GI_FIRST_BALANCES_NODE_CURR
This index is relative to a state like: `BeaconState.balances[0]`.


```solidity
GIndex public immutable GI_FIRST_BALANCES_NODE_CURR
```


### FIRST_SUPPORTED_SLOT
The very first slot the verifier is supposed to accept proofs for.


```solidity
Slot public immutable FIRST_SUPPORTED_SLOT
```


### PIVOT_SLOT
The first slot of the currently compatible fork.


```solidity
Slot public immutable PIVOT_SLOT
```


### CAPELLA_SLOT
Historical summaries started accumulating from the slot of Capella fork.


```solidity
Slot public immutable CAPELLA_SLOT
```


### WITHDRAWAL_ADDRESS
An address withdrawals are supposed to happen to (Lido withdrawal credentials).


```solidity
address public immutable WITHDRAWAL_ADDRESS
```


### MODULE
Staking module contract.


```solidity
IBaseModule public immutable MODULE
```


## Functions
### constructor

The previous and current forks can be essentially the same.


```solidity
constructor(
    address withdrawalAddress,
    address module,
    uint64 slotsPerEpoch,
    uint64 slotsPerHistoricalRoot,
    GIndices memory gindices,
    Slot firstSupportedSlot,
    Slot pivotSlot,
    Slot capellaSlot,
    address admin
) ;
```

### processSlashedProof

Verify proof of a slashed validator being withdrawable and report it to the module


```solidity
function processSlashedProof(ProcessSlashedInput calldata data) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessSlashedInput`|@see ProcessSlashedInput|


### processWithdrawalProof

Verify withdrawal proof and report withdrawal to the module for valid proofs


```solidity
function processWithdrawalProof(ProcessWithdrawalInput calldata data) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessWithdrawalInput`|@see ProcessWithdrawalInput|


### processHistoricalWithdrawalProof

Verify withdrawal proof against historical summaries data and report withdrawal to the module for valid proofs


```solidity
function processHistoricalWithdrawalProof(ProcessHistoricalWithdrawalInput calldata data) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessHistoricalWithdrawalInput`|@see ProcessHistoricalWithdrawalInput|


### processBalanceProof

Verify a validator's balance proof from a recent beacon block and sync the key added balance.


```solidity
function processBalanceProof(ProcessBalanceProofInput calldata data) external whenResumed;
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
function processHistoricalBalanceProof(ProcessHistoricalBalanceProofInput calldata data) external whenResumed;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`ProcessHistoricalBalanceProofInput`|The balance proof input containing recent + historical block headers, validator witness, and balance witness.|


### _reportSingleValidator


```solidity
function _reportSingleValidator(WithdrawnValidatorInfo memory info) internal;
```

### _getParentBlockRoot


```solidity
function _getParentBlockRoot(uint64 blockTimestamp) internal view returns (bytes32);
```

### _processWithdrawalProof

`header` MUST be trusted at this point.


```solidity
function _processWithdrawalProof(
    WithdrawalWitness calldata withdrawal,
    ValidatorWitness calldata validator,
    BeaconBlockHeader calldata header,
    uint256 nodeOperatorId,
    uint256 keyIndex
) internal view returns (uint256 withdrawalAmount);
```

### _processBalanceProof


```solidity
function _processBalanceProof(
    ValidatorWitness calldata validator,
    BalanceWitness calldata balance,
    bytes32 stateRoot,
    Slot stateSlot
) internal view returns (uint64 balanceGwei);
```

### _verifyValidatorBalance


```solidity
function _verifyValidatorBalance(
    uint256 validatorIndex,
    bytes32 balanceNode,
    bytes32 stateRoot,
    Slot stateSlot,
    bytes32[] calldata proof
) internal view returns (uint64 balanceGwei);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`balanceGwei`|`uint64`|Validator's balance in gwei.|


### _getValidatorBalanceNodeInfo


```solidity
function _getValidatorBalanceNodeInfo(bytes32 balanceNode, uint256 validatorIndex, Slot stateSlot)
    internal
    view
    returns (GIndex gI, uint64 balanceGwei);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`gI`|`GIndex`|Generalized index of the node for the `validatorIndex` and `stateSlot`.|
|`balanceGwei`|`uint64`|Balance in gwei extracted from the `balanceNode`.|


### _getValidatorGI


```solidity
function _getValidatorGI(uint256 offset, Slot stateSlot) internal view returns (GIndex);
```

### _getWithdrawalGI


```solidity
function _getWithdrawalGI(uint256 offset, Slot stateSlot) internal view returns (GIndex);
```

### _getValidatorBalanceGI


```solidity
function _getValidatorBalanceGI(uint256 offset, Slot stateSlot) internal view returns (GIndex);
```

### _getHistoricalBlockRootGI


```solidity
function _getHistoricalBlockRootGI(Slot recentSlot, Slot targetSlot) internal view returns (GIndex gI);
```

### _computeEpochAtSlot


```solidity
function _computeEpochAtSlot(Slot slot) internal view returns (uint256);
```

### __checkRole


```solidity
function __checkRole(bytes32 role) internal view override;
```

