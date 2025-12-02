# IVettedGateFactory
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IVettedGateFactory.sol)


## Functions
### VETTED_GATE_IMPL

address of the VettedGate implementation to be used for the new instances


```solidity
function VETTED_GATE_IMPL() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|address of the VettedGate implementation|


### create

Creates a new VettedGate instance behind the OssifiableProxy based on known implementation address


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


## Events
### VettedGateCreated

```solidity
event VettedGateCreated(address indexed gate);
```

## Errors
### ZeroImplementationAddress

```solidity
error ZeroImplementationAddress();
```

