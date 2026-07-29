# INodeOperatorsRegistry
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/INodeOperatorsRegistry.sol)

Node operator registry interface for legacy curated module.


## Functions
### getNodeOperator

Returns the node operator by id.


```solidity
function getNodeOperator(uint256 _nodeOperatorId, bool _fullInfo)
    external
    view
    returns (
        bool active,
        string memory name,
        address rewardAddress,
        uint64 totalVettedValidators,
        uint64 totalExitedValidators,
        uint64 totalAddedValidators,
        uint64 totalDepositedValidators
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nodeOperatorId`|`uint256`|Node Operator id.|
|`_fullInfo`|`bool`|If true, name will be returned as well.|


### getNodeOperatorsCount

Returns total number of node operators


```solidity
function getNodeOperatorsCount() external view returns (uint256);
```

