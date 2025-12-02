# IERC20Permit
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IERC20Permit.sol)

**Inherits:**
[IERC2612](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/IERC2612.sol/interface.IERC2612.md)


## Functions
### balanceOf


```solidity
function balanceOf(address _account) external view returns (uint256);
```

### transfer

Moves `_amount` from the caller's account to the `_recipient` account.


```solidity
function transfer(address _recipient, uint256 _amount) external returns (bool);
```

### transferFrom

Moves `_amount` from the `_sender` account to the `_recipient` account.


```solidity
function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
```

### approve


```solidity
function approve(address _spender, uint256 _amount) external returns (bool);
```

### allowance


```solidity
function allowance(address _owner, address _spender) external view returns (uint256);
```

