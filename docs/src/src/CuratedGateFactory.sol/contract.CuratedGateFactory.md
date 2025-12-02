# CuratedGateFactory
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/CuratedGateFactory.sol)

**Inherits:**
[ICuratedGateFactory](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/ICuratedGateFactory.sol/interface.ICuratedGateFactory.md)


## State Variables
### CURATED_GATE_IMPL

```solidity
address public immutable CURATED_GATE_IMPL
```


## Functions
### constructor


```solidity
constructor(address curatedGateImpl) ;
```

### create

Creates a new CuratedGate instance behind the OssifiableProxy based on known implementation address


```solidity
function create(uint256 curveId, bytes32 treeRoot, string calldata treeCid, address admin)
    external
    returns (address instance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`curveId`|`uint256`|Id of the bond curve to be assigned for the eligible members|
|`treeRoot`|`bytes32`|Root of the eligible members Merkle Tree|
|`treeCid`|`string`|CID of the eligible members Merkle Tree|
|`admin`|`address`|Address of the admin role|


