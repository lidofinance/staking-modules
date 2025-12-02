# BondLock
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/abstract/BondLock.sol)

**Inherits:**
[IBondLock](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IBondLock.sol/interface.IBondLock.md), Initializable

**Author:**
vgorkavenko

Bond lock mechanics abstract contract.
It gives the ability to lock the bond amount of the Node Operator.
There is a period of time during which the module can settle the lock in any way (for example, by penalizing the bond).
After that period, the lock is removed, and the bond amount is considered unlocked.
The contract contains:
- set default bond lock period
- get default bond lock period
- lock bond
- get locked bond info
- get actual locked bond amount
- reduce locked bond amount
- remove bond lock
It should be inherited by a module contract or a module-related contract.
Internal non-view methods should be used in the Module contract with additional requirements (if any).


## State Variables
### INFINITE_BOND_LOCK_UNTIL

```solidity
uint128 public constant INFINITE_BOND_LOCK_UNTIL = type(uint128).max
```


### BOND_LOCK_STORAGE_LOCATION

```solidity
bytes32 private constant BOND_LOCK_STORAGE_LOCATION =
    0x78c5a36767279da056404c09083fca30cf3ea61c442cfaba6669f76a37393f00
```


### MIN_BOND_LOCK_PERIOD

```solidity
uint256 public immutable MIN_BOND_LOCK_PERIOD
```


### MAX_BOND_LOCK_PERIOD

```solidity
uint256 public immutable MAX_BOND_LOCK_PERIOD
```


## Functions
### constructor


```solidity
constructor(uint256 minBondLockPeriod, uint256 maxBondLockPeriod) ;
```

### getBondLockPeriod

Get default bond lock period


```solidity
function getBondLockPeriod() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|period Default bond lock period|


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


### getActualLockedBond

Get amount of the locked bond in ETH (stETH) by the given Node Operator


```solidity
function getActualLockedBond(uint256 nodeOperatorId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Amount of the actual locked bond|


### _lock

Lock bond amount for the given Node Operator until the period.


```solidity
function _lock(uint256 nodeOperatorId, uint256 amount) internal;
```

### _unlock

Unlock the locked bond amount for the given Node Operator without changing the lock period


```solidity
function _unlock(uint256 nodeOperatorId, uint256 amount) internal;
```

### _changeBondLock


```solidity
function _changeBondLock(uint256 nodeOperatorId, uint256 amount, uint256 until) internal;
```

### __BondLock_init


```solidity
function __BondLock_init(uint256 period) internal onlyInitializing;
```

### _setBondLockPeriod

Set default bond lock period. That period will be added to the block timestamp of the lock translation to determine the bond lock duration


```solidity
function _setBondLockPeriod(uint256 period) internal;
```

### _getBondLockStorage


```solidity
function _getBondLockStorage() private pure returns (BondLockStorage storage $);
```

## Structs
### BondLockStorage
**Note:**
storage-location: erc7201:BondLock


```solidity
struct BondLockStorage {
    /// @dev Default bond lock period for all locks
    ///      After this period the bond lock is removed and no longer valid
    uint256 bondLockPeriod;
    /// @dev Mapping of the Node Operator id to the bond lock
    mapping(uint256 nodeOperatorId => BondLockData) bondLock;
}
```

