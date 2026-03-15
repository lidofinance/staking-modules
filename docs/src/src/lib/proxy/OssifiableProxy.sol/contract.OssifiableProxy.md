# OssifiableProxy
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/proxy/OssifiableProxy.sol)

**Inherits:**
ERC1967Proxy

An ossifiable proxy contract. Extends the ERC1967Proxy contract by
adding admin functionality


## Functions
### onlyAdmin

Validates that proxy is not ossified and that method is called by the admin
of the proxy


```solidity
modifier onlyAdmin() ;
```

### constructor

Initializes the upgradeable proxy with the initial implementation and admin


```solidity
constructor(address implementation_, address admin_, bytes memory data_) ERC1967Proxy(implementation_, data_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation_`|`address`|Address of the implementation|
|`admin_`|`address`|Address of the admin of the proxy|
|`data_`|`bytes`|Data used in a delegate call to implementation. The delegate call will be skipped if the data is empty bytes|


### receive

Fallback function that delegates calls to the address returned by `_implementation()`.


```solidity
receive() external payable virtual;
```

### proxy__ossify

Allows to transfer admin rights to zero address and prevent future
upgrades of the proxy


```solidity
function proxy__ossify() external onlyAdmin;
```

### proxy__changeAdmin

Changes the admin of the proxy


```solidity
function proxy__changeAdmin(address newAdmin_) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAdmin_`|`address`|Address of the new admin|


### proxy__upgradeTo

Upgrades the implementation of the proxy


```solidity
function proxy__upgradeTo(address newImplementation_) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation_`|`address`|Address of the new implementation|


### proxy__upgradeToAndCall

Upgrades the proxy to a new implementation, optionally performing an additional
setup call.


```solidity
function proxy__upgradeToAndCall(address newImplementation_, bytes calldata setupCalldata_) external onlyAdmin;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation_`|`address`|Address of the new implementation|
|`setupCalldata_`|`bytes`|Data for the setup call. The call is skipped if setupCalldata_ is empty|


### proxy__getAdmin

Returns the current admin of the proxy


```solidity
function proxy__getAdmin() external view returns (address);
```

### proxy__getImplementation

Returns the current implementation address


```solidity
function proxy__getImplementation() external view returns (address);
```

### proxy__getIsOssified

Returns whether the implementation is locked forever


```solidity
function proxy__getIsOssified() external view returns (bool);
```

### _onlyAdmin


```solidity
function _onlyAdmin() internal view;
```

## Events
### ProxyOssified

```solidity
event ProxyOssified();
```

## Errors
### NotAdmin

```solidity
error NotAdmin();
```

### ProxyIsOssified

```solidity
error ProxyIsOssified();
```

