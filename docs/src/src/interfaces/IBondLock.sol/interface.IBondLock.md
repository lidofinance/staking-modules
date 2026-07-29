# IBondLock
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IBondLock.sol)


## Functions
### MIN_BOND_LOCK_PERIOD


```solidity
function MIN_BOND_LOCK_PERIOD() external view returns (uint256);
```

### MAX_BOND_LOCK_PERIOD


```solidity
function MAX_BOND_LOCK_PERIOD() external view returns (uint256);
```

### getBondLockPeriod

Get default bond lock period


```solidity
function getBondLockPeriod() external view returns (uint256 period);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`period`|`uint256`|Default bond lock period|


### getLockedBondInfo

Get information about the locked bond for the given Node Operator


```solidity
function getLockedBondInfo(uint256 nodeOperatorId) external view returns (BondLockData memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BondLockData`|Locked bond info|


### getLockedBond

Get amount of the locked bond in ETH (stETH) by the given Node Operator


```solidity
function getLockedBond(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Amount of the actual locked bond|


### getBondLockNonce

Get bond lock nonce for the given Node Operator


```solidity
function getBondLockNonce(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Bond lock nonce|


### isLockExpired

Check if the bond lock for the given Node Operator has expired


```solidity
function isLockExpired(uint256 nodeOperatorId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the bond lock has expired, false otherwise|


## Events
### BondLockChanged

```solidity
event BondLockChanged(uint256 indexed nodeOperatorId, uint256 newAmount, uint256 until);
```

### BondLockRemoved

```solidity
event BondLockRemoved(uint256 indexed nodeOperatorId);
```

### BondLockPeriodChanged

```solidity
event BondLockPeriodChanged(uint256 period);
```

### BondLockNonceIncremented

```solidity
event BondLockNonceIncremented(uint256 indexed nodeOperatorId, uint256 newNonce);
```

## Errors
### InvalidBondLockPeriod

```solidity
error InvalidBondLockPeriod();
```

### InvalidBondLockAmount

```solidity
error InvalidBondLockAmount();
```

### BondLockNotExpired

```solidity
error BondLockNotExpired();
```

### NoBondLocked

```solidity
error NoBondLocked();
```

## Structs
### BondLockData
Bond lock structure.
It contains:
- amount   |> amount of locked bond
- until    |> timestamp until locked bond is retained


```solidity
struct BondLockData {
    uint128 amount;
    uint128 until;
}
```

