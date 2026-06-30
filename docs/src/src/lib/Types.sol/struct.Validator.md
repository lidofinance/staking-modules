# Validator
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/Types.sol)


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

