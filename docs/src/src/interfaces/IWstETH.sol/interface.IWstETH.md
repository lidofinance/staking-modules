# IWstETH
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IWstETH.sol)

**Inherits:**
[IERC20Permit](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IERC20Permit.sol/interface.IERC20Permit.md)


## Functions
### wrap


```solidity
function wrap(uint256 _stETHAmount) external returns (uint256);
```

### unwrap


```solidity
function unwrap(uint256 _wstETHAmount) external returns (uint256);
```

### getStETHByWstETH


```solidity
function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
```

### getWstETHByStETH


```solidity
function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
```

