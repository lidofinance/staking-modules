# MerkleGateFactory
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/MerkleGateFactory.sol)

**Inherits:**
[IMerkleGateFactory](/src/interfaces/IMerkleGateFactory.sol/interface.IMerkleGateFactory.md)


## State Variables
### GATE_IMPL

```solidity
address public immutable GATE_IMPL
```


## Functions
### constructor


```solidity
constructor(address gateImpl) ;
```

### create

Creates a new gate proxy for the predefined implementation and initializes it.


```solidity
function create(uint256 curveId, bytes32 treeRoot, string calldata treeCid, address admin)
    external
    returns (address instance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve id to assign to eligible members.|
|`treeRoot`|`bytes32`|Initial Merkle tree root.|
|`treeCid`|`string`|Initial Merkle tree CID.|
|`admin`|`address`|Address of the proxy admin and DEFAULT_ADMIN_ROLE holder.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|Address of the created proxy instance.|


