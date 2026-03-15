# IValidatorStrikes
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IValidatorStrikes.sol)


## Functions
### ORACLE


```solidity
function ORACLE() external view returns (address);
```

### MODULE


```solidity
function MODULE() external view returns (IBaseModule);
```

### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```

### EXIT_PENALTIES


```solidity
function EXIT_PENALTIES() external view returns (IExitPenalties);
```

### PARAMETERS_REGISTRY


```solidity
function PARAMETERS_REGISTRY() external view returns (IParametersRegistry);
```

### ejector


```solidity
function ejector() external view returns (IEjector);
```

### treeRoot


```solidity
function treeRoot() external view returns (bytes32);
```

### treeCid


```solidity
function treeCid() external view returns (string calldata);
```

### setEjector

Set the address of the Ejector contract


```solidity
function setEjector(address _ejector) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_ejector`|`address`|Address of the Ejector contract|


### processBadPerformanceProof

Report multiple keys as bad performing


```solidity
function processBadPerformanceProof(
    KeyStrikes[] calldata keyStrikesList,
    bytes32[] calldata proof,
    bool[] calldata proofFlags,
    address refundRecipient
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikesList`|`KeyStrikes[]`|List of KeyStrikes structs|
|`proof`|`bytes32[]`|Multi-proof of the strikes|
|`proofFlags`|`bool[]`|Flags to process the multi-proof, see OZ `processMultiProof`|
|`refundRecipient`|`address`|Address to send the refund to|


### processOracleReport

Receive the data of the Merkle tree from the Oracle contract and process it

New tree might be empty and it is valid value because of `strikesLifetime`


```solidity
function processOracleReport(bytes32 _treeRoot, string calldata _treeCid) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treeRoot`|`bytes32`|Root of the Merkle tree|
|`_treeCid`|`string`|an IPFS CID of the tree|


### verifyProof

Check the contract accepts the provided multi-proof


```solidity
function verifyProof(
    KeyStrikes[] calldata keyStrikesList,
    bytes[] memory pubkeys,
    bytes32[] calldata proof,
    bool[] calldata proofFlags
) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikesList`|`KeyStrikes[]`|List of KeyStrikes structs|
|`pubkeys`|`bytes[]`|Public keys corresponding to each entry in keyStrikesList|
|`proof`|`bytes32[]`|Multi-proof of the strikes|
|`proofFlags`|`bool[]`|Flags to process the multi-proof, see OZ `processMultiProof`|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool True if proof is accepted|


### hashLeaf

Get a hash of a leaf in a tree of strikes

Double hash the leaf to prevent second pre-image attacks


```solidity
function hashLeaf(KeyStrikes calldata keyStrikes, bytes calldata pubkey) external pure returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`keyStrikes`|`KeyStrikes`|KeyStrikes struct|
|`pubkey`|`bytes`|Public key|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Hash of the leaf|


### getInitializedVersion

Returns the initialized version of the contract


```solidity
function getInitializedVersion() external view returns (uint64);
```

## Events
### StrikesDataUpdated
Emitted when strikes data is updated


```solidity
event StrikesDataUpdated(bytes32 treeRoot, string treeCid);
```

### StrikesDataWiped
Emitted when strikes is updated from non-empty to empty


```solidity
event StrikesDataWiped();
```

### EjectorSet

```solidity
event EjectorSet(address ejector);
```

## Errors
### ZeroEjectorAddress

```solidity
error ZeroEjectorAddress();
```

### SameEjectorAddress

```solidity
error SameEjectorAddress();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

### ZeroOracleAddress

```solidity
error ZeroOracleAddress();
```

### ZeroExitPenaltiesAddress

```solidity
error ZeroExitPenaltiesAddress();
```

### ZeroParametersRegistryAddress

```solidity
error ZeroParametersRegistryAddress();
```

### ZeroAdminAddress

```solidity
error ZeroAdminAddress();
```

### SenderIsNotOracle

```solidity
error SenderIsNotOracle();
```

### ValueNotEvenlyDivisible

```solidity
error ValueNotEvenlyDivisible();
```

### EmptyKeyStrikesList

```solidity
error EmptyKeyStrikesList();
```

### ZeroMsgValue

```solidity
error ZeroMsgValue();
```

### InvalidReportData

```solidity
error InvalidReportData();
```

### InvalidProof

```solidity
error InvalidProof();
```

### NotEnoughStrikesToEject

```solidity
error NotEnoughStrikesToEject();
```

## Structs
### KeyStrikes

```solidity
struct KeyStrikes {
    uint256 nodeOperatorId;
    uint256 keyIndex;
    uint256[] data;
}
```

