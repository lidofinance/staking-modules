# Validator
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/Types.sol)


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

