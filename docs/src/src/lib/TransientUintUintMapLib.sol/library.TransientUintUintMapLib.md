# TransientUintUintMapLib
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/TransientUintUintMapLib.sol)


## State Variables
### ANCHOR

```solidity
bytes32 private constant ANCHOR = 0x6e38e7eaa4307e6ee6c66720337876ca65012869fbef035f57219354c1728400
```


## Functions
### create


```solidity
function create() internal returns (TransientUintUintMap self);
```

### add


```solidity
function add(TransientUintUintMap self, uint256 key, uint256 value) internal;
```

### set


```solidity
function set(TransientUintUintMap self, uint256 key, uint256 value) internal;
```

### get


```solidity
function get(TransientUintUintMap self, uint256 key) internal view returns (uint256);
```

### load


```solidity
function load(bytes32 tslot) internal pure returns (TransientUintUintMap);
```

### _slot


```solidity
function _slot(TransientUintUintMap self, uint256 key) internal pure returns (bytes32);
```

