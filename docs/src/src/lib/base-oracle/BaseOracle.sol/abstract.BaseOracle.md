# BaseOracle
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/base-oracle/BaseOracle.sol)

**Inherits:**
[IReportAsyncProcessor](/src/lib/base-oracle/interfaces/IReportAsyncProcessor.sol/interface.IReportAsyncProcessor.md), AccessControlEnumerableUpgradeable, [Versioned](/src/lib/utils/Versioned.sol/contract.Versioned.md)


## State Variables
### MANAGE_CONSENSUS_CONTRACT_ROLE
An ACL role granting the permission to set the consensus
contract address by calling setConsensusContract.


```solidity
bytes32 public constant MANAGE_CONSENSUS_CONTRACT_ROLE = keccak256("MANAGE_CONSENSUS_CONTRACT_ROLE")
```


### MANAGE_CONSENSUS_VERSION_ROLE
An ACL role granting the permission to set the consensus
version by calling setConsensusVersion.


```solidity
bytes32 public constant MANAGE_CONSENSUS_VERSION_ROLE = keccak256("MANAGE_CONSENSUS_VERSION_ROLE")
```


### CONSENSUS_CONTRACT_POSITION
Storage slot: address consensusContract


```solidity
bytes32 internal constant CONSENSUS_CONTRACT_POSITION = keccak256("lido.BaseOracle.consensusContract")
```


### CONSENSUS_VERSION_POSITION
Storage slot: uint256 consensusVersion


```solidity
bytes32 internal constant CONSENSUS_VERSION_POSITION = keccak256("lido.BaseOracle.consensusVersion")
```


### LAST_PROCESSING_REF_SLOT_POSITION
Storage slot: uint256 lastProcessingRefSlot


```solidity
bytes32 internal constant LAST_PROCESSING_REF_SLOT_POSITION = keccak256("lido.BaseOracle.lastProcessingRefSlot")
```


### CONSENSUS_REPORT_POSITION
Storage slot: ConsensusReport consensusReport


```solidity
bytes32 internal constant CONSENSUS_REPORT_POSITION = keccak256("lido.BaseOracle.consensusReport")
```


### SECONDS_PER_SLOT

```solidity
uint256 public immutable SECONDS_PER_SLOT
```


### GENESIS_TIME

```solidity
uint256 public immutable GENESIS_TIME
```


## Functions
### constructor


Initialization & admin functions


```solidity
constructor(uint256 secondsPerSlot, uint256 genesisTime) ;
```

### getConsensusContract

Returns the address of the HashConsensus contract.


```solidity
function getConsensusContract() external view returns (address);
```

### setConsensusContract

Sets the address of the HashConsensus contract.


```solidity
function setConsensusContract(address addr) external onlyRole(MANAGE_CONSENSUS_CONTRACT_ROLE);
```

### getConsensusVersion

Returns the current consensus version expected by the oracle contract.
Consensus version must change every time consensus rules change, meaning that
an oracle looking at the same reference slot would calculate a different hash.


```solidity
function getConsensusVersion() external view returns (uint256);
```

### setConsensusVersion

Sets the consensus version expected by the oracle contract.


```solidity
function setConsensusVersion(uint256 version) external onlyRole(MANAGE_CONSENSUS_VERSION_ROLE);
```

### getConsensusReport


Data provider interface

Returns the last consensus report hash and metadata.

Zero hash means that either there have been no reports yet, or the report for `refSlot` was discarded.


```solidity
function getConsensusReport()
    external
    view
    returns (bytes32 hash, uint256 refSlot, uint256 processingDeadlineTime, bool processingStarted);
```

### submitConsensusReport


Consensus contract interface

Called by HashConsensus contract to push a consensus report for processing.
Note that submitting the report doesn't require the processor to start processing it right
away, this can happen later (see `getLastProcessingRefSlot`). Until processing is started,
HashConsensus is free to reach consensus on another report for the same reporting frame an
submit it using this same function, or to lose the consensus on the submitted report,
notifying the processor via `discardConsensusReport`.


```solidity
function submitConsensusReport(bytes32 reportHash, uint256 refSlot, uint256 deadline) external;
```

### discardConsensusReport

Called by HashConsensus contract to notify that the report for the given ref. slot
is not a consensus report anymore and should be discarded. This can happen when a member
changes their report, is removed from the set, or when the quorum value gets increased.
Only called when, for the given reference slot:
1. there previously was a consensus report; AND
2. processing of the consensus report hasn't started yet; AND
3. report processing deadline is not expired yet (enforced by HashConsensus); AND
4. there's no consensus report now (otherwise, `submitConsensusReport` is called instead) (enforced by HashConsensus).
Can be called even when there's no submitted non-discarded consensus report for the current
reference slot, i.e. can be called multiple times in succession.


```solidity
function discardConsensusReport(uint256 refSlot) external;
```

### getLastProcessingRefSlot

Returns the last reference slot for which processing of the report was started.


```solidity
function getLastProcessingRefSlot() external view returns (uint256);
```

### _initialize


Descendant contract interface

Initializes the contract storage. Must be called by a descendant
contract as part of its initialization.


```solidity
function _initialize(address consensusContract, uint256 consensusVersion, uint256 lastProcessingRefSlot)
    internal
    virtual;
```

### _isConsensusMember

Returns whether the given address is a member of the oracle committee.


```solidity
function _isConsensusMember(address addr) internal view returns (bool);
```

### _handleConsensusReport

Called when the oracle gets a new consensus report from the HashConsensus contract.
Keep in mind that, until you call `_startProcessing`, the oracle committee is free to
reach consensus on another report for the same reporting frame and re-submit it using
this function, or lose consensus on the report and ask to discard it by calling the
`_handleConsensusReportDiscarded` function.


```solidity
function _handleConsensusReport(
    ConsensusReport memory report,
    uint256 prevSubmittedRefSlot,
    uint256 prevProcessingRefSlot
) internal virtual;
```

### _handleConsensusReportDiscarded

Called when the HashConsensus contract loses consensus on a previously submitted
report that is not processing yet and asks to discard this report. Only called if there is
no new consensus report at the moment; otherwise, `_handleConsensusReport` is called instead.


```solidity
function _handleConsensusReportDiscarded(ConsensusReport memory report) internal virtual;
```

### _checkConsensusData

May be called by a descendant contract to check if the received data matches
the currently submitted consensus report. Reverts otherwise.


```solidity
function _checkConsensusData(uint256 refSlot, uint256 consensusVersion, bytes32 hash) internal view;
```

### _startProcessing

Called by a descendant contract to mark the current consensus report
as being processed. Returns the last ref. slot which processing was started
before the call.
Before this function is called, the oracle committee is free to reach consensus
on another report for the same reporting frame. After this function is called,
the consensus report for the current frame is guaranteed to remain the same.


```solidity
function _startProcessing() internal returns (uint256);
```

### _checkProcessingDeadline


```solidity
function _checkProcessingDeadline(uint256 deadlineTime) internal view;
```

### _setConsensusVersion


Implementation & helpers


```solidity
function _setConsensusVersion(uint256 version) internal;
```

### _setConsensusContract


```solidity
function _setConsensusContract(address addr, uint256 lastProcessingRefSlot) internal;
```

### _checkSenderIsConsensusContract


```solidity
function _checkSenderIsConsensusContract() internal view;
```

### _getTime


```solidity
function _getTime() internal view virtual returns (uint256);
```

### _storageConsensusReport


```solidity
function _storageConsensusReport() internal pure returns (StorageConsensusReport storage r);
```

## Events
### ConsensusHashContractSet

```solidity
event ConsensusHashContractSet(address indexed addr, address indexed prevAddr);
```

### ConsensusVersionSet

```solidity
event ConsensusVersionSet(uint256 indexed version, uint256 indexed prevVersion);
```

### ReportSubmitted

```solidity
event ReportSubmitted(uint256 indexed refSlot, bytes32 hash, uint256 processingDeadlineTime);
```

### ReportDiscarded

```solidity
event ReportDiscarded(uint256 indexed refSlot, bytes32 hash);
```

### ProcessingStarted

```solidity
event ProcessingStarted(uint256 indexed refSlot, bytes32 hash);
```

### WarnProcessingMissed

```solidity
event WarnProcessingMissed(uint256 indexed refSlot);
```

## Errors
### AddressCannotBeZero

```solidity
error AddressCannotBeZero();
```

### AddressCannotBeSame

```solidity
error AddressCannotBeSame();
```

### VersionCannotBeSame

```solidity
error VersionCannotBeSame();
```

### VersionCannotBeZero

```solidity
error VersionCannotBeZero();
```

### UnexpectedChainConfig

```solidity
error UnexpectedChainConfig();
```

### SenderIsNotTheConsensusContract

```solidity
error SenderIsNotTheConsensusContract();
```

### InitialRefSlotCannotBeLessThanProcessingOne

```solidity
error InitialRefSlotCannotBeLessThanProcessingOne(uint256 initialRefSlot, uint256 processingRefSlot);
```

### RefSlotMustBeGreaterThanProcessingOne

```solidity
error RefSlotMustBeGreaterThanProcessingOne(uint256 refSlot, uint256 processingRefSlot);
```

### RefSlotCannotDecrease

```solidity
error RefSlotCannotDecrease(uint256 refSlot, uint256 prevRefSlot);
```

### NoConsensusReportToProcess

```solidity
error NoConsensusReportToProcess();
```

### ProcessingDeadlineMissed

```solidity
error ProcessingDeadlineMissed(uint256 deadline);
```

### RefSlotAlreadyProcessing

```solidity
error RefSlotAlreadyProcessing();
```

### UnexpectedRefSlot

```solidity
error UnexpectedRefSlot(uint256 consensusRefSlot, uint256 dataRefSlot);
```

### UnexpectedConsensusVersion

```solidity
error UnexpectedConsensusVersion(uint256 expectedVersion, uint256 receivedVersion);
```

### HashCannotBeZero

```solidity
error HashCannotBeZero();
```

### UnexpectedDataHash

```solidity
error UnexpectedDataHash(bytes32 consensusHash, bytes32 receivedHash);
```

### SecondsPerSlotCannotBeZero

```solidity
error SecondsPerSlotCannotBeZero();
```

## Structs
### ConsensusReport

```solidity
struct ConsensusReport {
    bytes32 hash;
    uint64 refSlot;
    uint64 processingDeadlineTime;
}
```

### StorageConsensusReport

Storage helpers


```solidity
struct StorageConsensusReport {
    ConsensusReport value;
}
```

