# Validator
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/Types.sol)


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

