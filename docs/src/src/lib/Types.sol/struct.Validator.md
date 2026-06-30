# Validator
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/Types.sol)


```solidity
struct Validator {
bytes pubkey;
bytes32 withdrawalCredentials;
uint64 effectiveBalance;
bool slashed;
uint64 activationEligibilityEpoch;
uint64 activationEpoch;
uint64 exitEpoch;
uint64 withdrawableEpoch;
}
```

