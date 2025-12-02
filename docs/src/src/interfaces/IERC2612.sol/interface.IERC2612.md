# IERC2612
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/interfaces/IERC2612.sol)


## Functions
### permit

Sets `value` as the allowance of `spender` over ``owner``'s tokens,
given ``owner``'s signed approval.
Emits an {Approval} event.
Requirements:
- `spender` cannot be the zero address.
- `deadline` must be a timestamp in the future.
- `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
over the EIP712-formatted function arguments.
- the signature must use ``owner``'s current nonce (see {nonces}).


```solidity
function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external;
```

