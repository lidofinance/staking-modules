# ICuratedModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/ICuratedModule.sol)

**Inherits:**
[ICSModule](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/ICSModule.sol/interface.ICSModule.md)


## Functions
### OPERATOR_ADDRESSES_ADMIN_ROLE


```solidity
function OPERATOR_ADDRESSES_ADMIN_ROLE() external view returns (bytes32);
```

### changeNodeOperatorAddresses

Change both reward and manager addresses of a node operator.


```solidity
function changeNodeOperatorAddresses(uint256 nodeOperatorId, address newManagerAddress, address newRewardAddress)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newManagerAddress`|`address`|New manager address|
|`newRewardAddress`|`address`|New reward address|


## Errors
### NotImplemented

```solidity
error NotImplemented();
```

