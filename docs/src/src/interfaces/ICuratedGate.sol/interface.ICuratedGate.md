# ICuratedGate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/ICuratedGate.sol)

**Inherits:**
[IMerkleGate](/src/interfaces/IMerkleGate.sol/interface.IMerkleGate.md)

**Title:**
Curated Gate Interface

Allows eligible addresses to create Node Operators and store metadata.


## Functions
### MODULE


```solidity
function MODULE() external view returns (ICuratedModule);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ICuratedModule`|MODULE Curated module reference|


### ACCOUNTING


```solidity
function ACCOUNTING() external view returns (IAccounting);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IAccounting`|ACCOUNTING Accounting reference|


### META_REGISTRY


```solidity
function META_REGISTRY() external view returns (IMetaRegistry);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IMetaRegistry`|META_REGISTRY Operators metadata registry reference|


### createNodeOperator

Create an empty Node Operator for the caller if eligible.
Stores provided name/description in MetaRegistry. Marks caller as consumed.


```solidity
function createNodeOperator(
    string calldata name,
    string calldata description,
    address managerAddress,
    address rewardAddress,
    bytes32[] calldata proof
) external returns (uint256 nodeOperatorId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|Display name of the Node Operator|
|`description`|`string`|Description of the Node Operator|
|`managerAddress`|`address`|Address to set as manager; if zero, defaults will be used by the module|
|`rewardAddress`|`address`|Address to set as rewards receiver; if zero, defaults will be used by the module|
|`proof`|`bytes32[]`|Merkle proof for the caller address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|Newly created Node Operator id|


## Errors
### InvalidCurveId
Errors


```solidity
error InvalidCurveId();
```

### ZeroModuleAddress

```solidity
error ZeroModuleAddress();
```

