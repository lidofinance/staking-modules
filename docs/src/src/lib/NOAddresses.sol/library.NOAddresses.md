# NOAddresses
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/NOAddresses.sol)

External deployment-linked library used by BaseModule-compatible modules.


## Functions
### proposeNodeOperatorManagerAddressChange

Propose a new manager address for the Node Operator.

Passing address(0) clears the pending proposal without changing the current manager address.


```solidity
function proposeNodeOperatorManagerAddressChange(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address proposedAddress
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`proposedAddress`|`address`|Proposed manager address, or address(0) to cancel the current proposal|


### confirmNodeOperatorManagerAddressChange

Confirm a new manager address for the Node Operator.
Should be called from the currently proposed address


```solidity
function confirmNodeOperatorManagerAddressChange(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### proposeNodeOperatorRewardAddressChange

Propose a new reward address for the Node Operator.

Passing address(0) clears the pending proposal without changing the current reward address.


```solidity
function proposeNodeOperatorRewardAddressChange(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address proposedAddress
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`proposedAddress`|`address`|Proposed reward address, or address(0) to cancel the current proposal|


### confirmNodeOperatorRewardAddressChange

Confirm a new reward address for the Node Operator.
Should be called from the currently proposed address


```solidity
function confirmNodeOperatorRewardAddressChange(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### resetNodeOperatorManagerAddress

Reset the manager address to the reward address.
Should be called from the reward address


```solidity
function resetNodeOperatorManagerAddress(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|


### changeNodeOperatorRewardAddress

Change rewardAddress if extendedManagerPermissions is enabled for the Node Operator.
Should be called from the current manager address


```solidity
function changeNodeOperatorRewardAddress(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address newAddress,
    address stETH
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newAddress`|`address`|New reward address|
|`stETH`|`address`||


### changeNodeOperatorAddresses

Change both reward and manager addresses of a node operator.

XXX: Use with caution! No check of the caller.


```solidity
function changeNodeOperatorAddresses(
    mapping(uint256 => NodeOperator) storage nodeOperators,
    uint256 nodeOperatorId,
    address newManagerAddress,
    address newRewardAddress,
    address stETH
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperators`|`mapping(uint256 => NodeOperator)`||
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newManagerAddress`|`address`|New manager address|
|`newRewardAddress`|`address`|New reward address|
|`stETH`|`address`||


