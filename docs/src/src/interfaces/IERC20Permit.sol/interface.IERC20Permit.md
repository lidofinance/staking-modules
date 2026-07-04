# IERC20Permit
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IERC20Permit.sol)

**Inherits:**
[IERC2612](/src/interfaces/IERC2612.sol/interface.IERC2612.md)

**Title:**
Interface defining ERC20-compatible token


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

