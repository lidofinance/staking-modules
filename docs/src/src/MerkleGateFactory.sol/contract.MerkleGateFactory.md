# MerkleGateFactory
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/MerkleGateFactory.sol)

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
function create(uint256 curveId, bytes32 treeRoot, string calldata treeCid, string calldata name, address admin)
    external
    returns (address instance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Bond curve id used by the gate.|
|`treeRoot`|`bytes32`|Initial Merkle tree root.|
|`treeCid`|`string`|Initial Merkle tree CID.|
|`name`|`string`|Human-readable gate name.|
|`admin`|`address`|Address of the proxy admin and DEFAULT_ADMIN_ROLE holder.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`instance`|`address`|Address of the created proxy instance.|


