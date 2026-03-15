# IReportAsyncProcessor
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/base-oracle/interfaces/IReportAsyncProcessor.sol)

A contract that gets consensus reports (i.e. hashes) pushed to and processes them
asynchronously.
HashConsensus doesn't expect any specific behavior from a report processor, and guarantees
the following:
1. HashConsensus won't submit reports via `IReportAsyncProcessor.submitConsensusReport` or ask
to discard reports via `IReportAsyncProcessor.discardConsensusReport` for any slot up to (and
including) the slot returned from `IReportAsyncProcessor.getLastProcessingRefSlot`.
2. HashConsensus won't accept member reports (and thus won't include such reports in calculating
the consensus) that have `consensusVersion` argument of the `HashConsensus.submitReport` call
holding a diff. value than the one returned from `IReportAsyncProcessor.getConsensusVersion()`
at the moment of the `HashConsensus.submitReport` call.


## Functions
### submitConsensusReport

Submits a consensus report for processing.
Note that submitting the report doesn't require the processor to start processing it right
away, this can happen later (see `getLastProcessingRefSlot`). Until processing is started,
HashConsensus is free to reach consensus on another report for the same reporting frame an
submit it using this same function, or to lose the consensus on the submitted report,
notifying the processor via `discardConsensusReport`.


```solidity
function submitConsensusReport(bytes32 report, uint256 refSlot, uint256 deadline) external;
```

### discardConsensusReport

Notifies that the report for the given ref. slot is not a consensus report anymore
and should be discarded. This can happen when a member changes their report, is removed
from the set, or when the quorum value gets increased.
Only called when, for the given reference slot:
1. there previously was a consensus report; AND
2. processing of the consensus report hasn't started yet; AND
3. report processing deadline is not expired yet; AND
4. there's no consensus report now (otherwise, `submitConsensusReport` is called instead).
Can be called even when there's no submitted non-discarded consensus report for the current
reference slot, i.e. can be called multiple times in succession.


```solidity
function discardConsensusReport(uint256 refSlot) external;
```

### getLastProcessingRefSlot

Returns the last reference slot for which processing of the report was started.
HashConsensus won't submit reports for any slot less than or equal to this slot.


```solidity
function getLastProcessingRefSlot() external view returns (uint256);
```

### getConsensusVersion

Returns the current consensus version.
Consensus version must change every time consensus rules change, meaning that
an oracle looking at the same reference slot would calculate a different hash.
HashConsensus won't accept member reports any consensus version different from the
one returned from this function.


```solidity
function getConsensusVersion() external view returns (uint256);
```

### getConsensusContract

Returns the address of the consensus contract.


```solidity
function getConsensusContract() external view returns (address);
```

