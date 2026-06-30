# IStETH
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/interfaces/IStETH.sol)

**Inherits:**
[IERC20Permit](/src/interfaces/IERC20Permit.sol/interface.IERC20Permit.md)

**Title:**
Interface defining ERC20-compatible StETH token


## Functions
### getPooledEthByShares

Get stETH amount by the provided shares amount

dual to `getSharesByPooledEth`.


```solidity
function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_sharesAmount`|`uint256`|shares amount|


### getSharesByPooledEth

Get shares amount by the provided stETH amount

dual to `getPooledEthByShares`.


```solidity
function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_pooledEthAmount`|`uint256`|stETH amount|


### sharesOf

Get shares amount of the provided account


```solidity
function sharesOf(address _account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|provided account address.|


### transferSharesFrom

Transfer `_sharesAmount` stETH shares from `_sender` to `_recipient` using allowance.


```solidity
function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount) external returns (uint256);
```

### transferShares

Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.


```solidity
function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);
```

