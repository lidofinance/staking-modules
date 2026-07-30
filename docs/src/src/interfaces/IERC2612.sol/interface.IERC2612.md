# IERC2612
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/interfaces/IERC2612.sol)


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

