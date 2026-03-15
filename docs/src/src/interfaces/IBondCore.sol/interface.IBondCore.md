# IBondCore
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/interfaces/IBondCore.sol)


## Functions
### LIDO_LOCATOR


```solidity
function LIDO_LOCATOR() external view returns (ILidoLocator);
```

### LIDO


```solidity
function LIDO() external view returns (ILido);
```

### WITHDRAWAL_QUEUE


```solidity
function WITHDRAWAL_QUEUE() external view returns (IWithdrawalQueue);
```

### WSTETH


```solidity
function WSTETH() external view returns (IWstETH);
```

### totalBondShares

Get total bond shares (stETH) stored on the contract


```solidity
function totalBondShares() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total bond shares (stETH)|


### getBondShares

Get bond shares (stETH) for the given Node Operator


```solidity
function getBondShares(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Bond in stETH shares|


### getBond

Get bond amount in ETH (stETH) for the given Node Operator


```solidity
function getBond(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Bond amount in ETH (stETH)|


### getBondDebt

Get bond debt in ETH for the given Node Operator.
Bond debt can occur when Node Operator's bond is not enough to cover the penalties.
Any bond debt will be covered as soon as the Node Operator deposits more bond or receives rewards.


```solidity
function getBondDebt(uint256 nodeOperatorId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Bond debt in ETH|


## Events
### BondDepositedETH

```solidity
event BondDepositedETH(uint256 indexed nodeOperatorId, address from, uint256 amount);
```

### BondDepositedStETH

```solidity
event BondDepositedStETH(uint256 indexed nodeOperatorId, address from, uint256 amount);
```

### BondDepositedWstETH

```solidity
event BondDepositedWstETH(uint256 indexed nodeOperatorId, address from, uint256 amount);
```

### BondClaimedUnstETH

```solidity
event BondClaimedUnstETH(uint256 indexed nodeOperatorId, address to, uint256 amount, uint256 requestId);
```

### BondClaimedStETH

```solidity
event BondClaimedStETH(uint256 indexed nodeOperatorId, address to, uint256 amount);
```

### BondClaimedWstETH

```solidity
event BondClaimedWstETH(uint256 indexed nodeOperatorId, address to, uint256 amount);
```

### BondBurned

```solidity
event BondBurned(uint256 indexed nodeOperatorId, uint256 amountToBurn, uint256 burnedAmount);
```

### BondCharged

```solidity
event BondCharged(uint256 indexed nodeOperatorId, uint256 amountToCharge, uint256 chargedAmount);
```

### BondDebtIncreased

```solidity
event BondDebtIncreased(uint256 indexed nodeOperatorId, uint256 amount);
```

### BondDebtCovered

```solidity
event BondDebtCovered(uint256 indexed nodeOperatorId, uint256 amount);
```

## Errors
### ZeroLocatorAddress

```solidity
error ZeroLocatorAddress();
```

### NothingToClaim

```solidity
error NothingToClaim();
```

