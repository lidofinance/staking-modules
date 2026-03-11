# HashConsensus
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/base-oracle/HashConsensus.sol)

**Inherits:**
[IConsensusContract](/src/lib/base-oracle/interfaces/IConsensusContract.sol/interface.IConsensusContract.md), AccessControlEnumerableUpgradeable

A contract managing oracle members committee and allowing the members to reach
consensus on a hash for each reporting frame.
Time is divided in frames of equal length, each having reference slot and processing
deadline. Report data must be gathered by looking at the world state at the moment of
the frame's reference slot (including any state changes made in that slot), and must
be processed before the frame's processing deadline.
Frame length is defined in Ethereum consensus layer epochs. Reference slot for each
frame is set to the last slot of the epoch preceding the frame's first epoch. The
processing deadline is set to the last slot of the last epoch of the frame.
This means that all state changes a report processing could entail are guaranteed to be
observed while gathering data for the next frame's report. This is an important property
given that oracle reports sometimes have to contain diffs instead of the full state which
might be impractical or even impossible to transmit and process.


## State Variables
### MANAGE_MEMBERS_AND_QUORUM_ROLE
An ACL role granting the permission to modify members list members and
change the quorum by calling addMember, removeMember, and setQuorum functions.


```solidity
bytes32 public constant MANAGE_MEMBERS_AND_QUORUM_ROLE = keccak256("MANAGE_MEMBERS_AND_QUORUM_ROLE")
```


### DISABLE_CONSENSUS_ROLE
An ACL role granting the permission to disable the consensus by calling
the disableConsensus function. Enabling the consensus back requires the possession
of the MANAGE_MEMBERS_AND_QUORUM_ROLE.


```solidity
bytes32 public constant DISABLE_CONSENSUS_ROLE = keccak256("DISABLE_CONSENSUS_ROLE")
```


### MANAGE_FRAME_CONFIG_ROLE
An ACL role granting the permission to change reporting interval duration
and fast lane reporting interval length by calling setFrameConfig.


```solidity
bytes32 public constant MANAGE_FRAME_CONFIG_ROLE = keccak256("MANAGE_FRAME_CONFIG_ROLE")
```


### MANAGE_FAST_LANE_CONFIG_ROLE
An ACL role granting the permission to change fast lane reporting interval
length by calling setFastLaneLengthSlots.


```solidity
bytes32 public constant MANAGE_FAST_LANE_CONFIG_ROLE = keccak256("MANAGE_FAST_LANE_CONFIG_ROLE")
```


### MANAGE_REPORT_PROCESSOR_ROLE
An ACL role granting the permission to change the report processor
contract by calling setReportProcessor.


```solidity
bytes32 public constant MANAGE_REPORT_PROCESSOR_ROLE = keccak256("MANAGE_REPORT_PROCESSOR_ROLE")
```


### UNREACHABLE_QUORUM
A quorum value that effectively disables the oracle.


```solidity
uint256 internal constant UNREACHABLE_QUORUM = type(uint256).max
```


### ZERO_HASH

```solidity
bytes32 internal constant ZERO_HASH = bytes32(0)
```


### DEADLINE_SLOT_OFFSET
An offset from the processing deadline slot of the previous frame (i.e. the last slot
at which a report for the prev. frame can be submitted and its processing started) to the
reference slot of the next frame (equal to the last slot of the previous frame).
frame[i].reportProcessingDeadlineSlot := frame[i + 1].refSlot - DEADLINE_SLOT_OFFSET

Declared as immutable to allow for changes in test scenarios.


```solidity
uint256 internal immutable DEADLINE_SLOT_OFFSET = 0
```


### SLOTS_PER_EPOCH
Chain specification


```solidity
uint64 internal immutable SLOTS_PER_EPOCH
```


### SECONDS_PER_SLOT

```solidity
uint64 internal immutable SECONDS_PER_SLOT
```


### GENESIS_TIME

```solidity
uint64 internal immutable GENESIS_TIME
```


### _frameConfig
Reporting frame configuration


```solidity
FrameConfig internal _frameConfig
```


### _memberStates
Oracle committee members states array


```solidity
MemberState[] internal _memberStates
```


### _memberAddresses
Oracle committee members' addresses array


```solidity
address[] internal _memberAddresses
```


### _memberIndices1b
Mapping from an oracle committee member address to the 1-based index in the
members array


```solidity
mapping(address => uint256) internal _memberIndices1b
```


### _reportingState
A structure containing the last reference slot any report was received for, the last
reference slot consensus report was achieved for, and the last consensus variant index


```solidity
ReportingState internal _reportingState
```


### _quorum
Oracle committee members quorum value, must be larger than totalMembers // 2


```solidity
uint256 internal _quorum
```


### _reportVariants
Mapping from a report variant index to the ReportVariant structure


```solidity
mapping(uint256 => ReportVariant) internal _reportVariants
```


### _reportVariantsLength
The number of report variants


```solidity
uint256 internal _reportVariantsLength
```


### _reportProcessor
The address of the report processor contract


```solidity
address internal _reportProcessor
```


## Functions
### constructor


Initialization


```solidity
constructor(
    uint256 slotsPerEpoch,
    uint256 secondsPerSlot,
    uint256 genesisTime,
    uint256 epochsPerFrame,
    uint256 fastLaneLengthSlots,
    address admin,
    address reportProcessor
) ;
```

### getChainConfig


Time

Returns the immutable chain parameters required to calculate epoch and slot
given a timestamp.


```solidity
function getChainConfig()
    external
    view
    returns (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime);
```

### getFrameConfig

Returns the time-related configuration.


```solidity
function getFrameConfig()
    external
    view
    returns (uint256 initialEpoch, uint256 epochsPerFrame, uint256 fastLaneLengthSlots);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`initialEpoch`|`uint256`|Epoch of the frame with zero index.|
|`epochsPerFrame`|`uint256`|Length of a frame in epochs.|
|`fastLaneLengthSlots`|`uint256`|Length of the fast lane interval in slots; see `getIsFastLaneMember`.|


### getCurrentFrame

Returns the current reporting frame.


```solidity
function getCurrentFrame() external view returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`refSlot`|`uint256`|The frame's reference slot: if the data the consensus is being reached upon includes or depends on any onchain state, this state should be queried at the reference slot. If the slot contains a block, the state should include all changes from that block.|
|`reportProcessingDeadlineSlot`|`uint256`|The last slot at which the report can be processed by the report processor contract.|


### getInitialRefSlot

Returns the earliest possible reference slot, i.e. the reference slot of the
reporting frame with zero index.


```solidity
function getInitialRefSlot() external view returns (uint256);
```

### updateInitialEpoch

Sets a new initial epoch given that the current initial epoch is in the future.


```solidity
function updateInitialEpoch(uint256 initialEpoch) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`initialEpoch`|`uint256`|The new initial epoch.|


### setFrameConfig

Updates the time-related configuration.


```solidity
function setFrameConfig(uint256 epochsPerFrame, uint256 fastLaneLengthSlots)
    external
    onlyRole(MANAGE_FRAME_CONFIG_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`epochsPerFrame`|`uint256`|Length of a frame in epochs.|
|`fastLaneLengthSlots`|`uint256`|Length of the fast lane interval in slots; see `getIsFastLaneMember`.|


### getIsMember


Members

Returns whether the given address is currently a member of the consensus.


```solidity
function getIsMember(address addr) external view returns (bool);
```

### getIsFastLaneMember

Returns whether the given address is a fast lane member for the current reporting
frame.
Fast lane members is a subset of all members that changes each reporting frame. These
members can, and are expected to, submit a report during the first part of the frame called
the "fast lane interval" and defined via `setFrameConfig` or `setFastLaneLengthSlots`. Under
regular circumstances, all other members are only allowed to submit a report after the fast
lane interval passes.
The fast lane subset consists of `quorum` members; selection is implemented as a sliding
window of the `quorum` width over member indices (mod total members). The window advances
by one index each reporting frame.
This is done to encourage each member from the full set to participate in reporting on a
regular basis, and identify any malfunctioning members.
With the fast lane mechanism active, it's sufficient for the monitoring to check that
consensus is consistently reached during the fast lane part of each frame to conclude that
all members are active and share the same consensus rules.
However, there is no guarantee that, at any given time, it holds true that only the current
fast lane members can or were able to report during the currently-configured fast lane
interval of the current frame. In particular, this assumption can be violated in any frame
during which the members set, initial epoch, or the quorum number was changed, or the fast
lane interval length was increased. Thus, the fast lane mechanism should not be used for any
purpose other than monitoring of the members liveness, and monitoring tools should take into
consideration the potential irregularities within frames with any configuration changes.


```solidity
function getIsFastLaneMember(address addr) external view returns (bool);
```

### getMembers

Returns all current members, together with the last reference slot each member
submitted a report for.


```solidity
function getMembers() external view returns (address[] memory addresses, uint256[] memory lastReportedRefSlots);
```

### getFastLaneMembers

Returns the subset of the oracle committee members (consisting of `quorum` items)
that changes each frame.
See `getIsFastLaneMember`.


```solidity
function getFastLaneMembers()
    external
    view
    returns (address[] memory addresses, uint256[] memory lastReportedRefSlots);
```

### setFastLaneLengthSlots

Sets the duration of the fast lane interval of the reporting frame.
See `getIsFastLaneMember`.


```solidity
function setFastLaneLengthSlots(uint256 fastLaneLengthSlots) external onlyRole(MANAGE_FAST_LANE_CONFIG_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fastLaneLengthSlots`|`uint256`|The length of the fast lane reporting interval in slots. Setting it to zero disables the fast lane subset, allowing any oracle to report starting from the first slot of a frame and until the frame's reporting deadline.|


### addMember


```solidity
function addMember(address addr, uint256 quorum) external onlyRole(MANAGE_MEMBERS_AND_QUORUM_ROLE);
```

### removeMember


```solidity
function removeMember(address addr, uint256 quorum) external onlyRole(MANAGE_MEMBERS_AND_QUORUM_ROLE);
```

### getQuorum


```solidity
function getQuorum() external view returns (uint256);
```

### setQuorum


```solidity
function setQuorum(uint256 quorum) external;
```

### disableConsensus

Disables the oracle by setting the quorum to an unreachable value.


```solidity
function disableConsensus() external;
```

### getReportProcessor


Report processor


```solidity
function getReportProcessor() external view returns (address);
```

### setReportProcessor


```solidity
function setReportProcessor(address newProcessor) external onlyRole(MANAGE_REPORT_PROCESSOR_ROLE);
```

### getConsensusState


Consensus

Returns info about the current frame and consensus state in that frame.


```solidity
function getConsensusState()
    external
    view
    returns (uint256 refSlot, bytes32 consensusReport, bool isReportProcessing);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`refSlot`|`uint256`|Reference slot of the current reporting frame.|
|`consensusReport`|`bytes32`|Consensus report for the current frame, if any. Zero bytes otherwise.|
|`isReportProcessing`|`bool`|If consensus report for the current frame is already being processed. Consensus can be changed before the processing starts.|


### getReportVariants

Returns report variants and their support for the current reference slot.


```solidity
function getReportVariants() external view returns (bytes32[] memory variants, uint256[] memory support);
```

### getConsensusStateForMember

Returns the extended information related to an oracle committee member with the
given address and the current consensus state. Provides all the information needed for
an oracle daemon to decide if it needs to submit a report.


```solidity
function getConsensusStateForMember(address addr) external view returns (MemberConsensusState memory result);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The member address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`MemberConsensusState`|See the docs for `MemberConsensusState`.|


### submitReport

Used by oracle members to submit hash of the data calculated for the given
reference slot.


```solidity
function submitReport(uint256 slot, bytes32 report, uint256 consensusVersion) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slot`|`uint256`|The reference slot the data was calculated for. Reverts if doesn't match the current reference slot.|
|`report`|`bytes32`|Hash of the data calculated for the given reference slot.|
|`consensusVersion`|`uint256`|Version of the oracle consensus rules. Reverts if doesn't match the version returned by the currently set consensus report processor, or zero if no report processor is set.|


### _setFrameConfig


Implementation: time


```solidity
function _setFrameConfig(
    uint256 initialEpoch,
    uint256 epochsPerFrame,
    uint256 fastLaneLengthSlots,
    FrameConfig memory prevConfig
) internal;
```

### _getCurrentFrame


```solidity
function _getCurrentFrame() internal view returns (ConsensusFrame memory);
```

### _getInitialFrame


```solidity
function _getInitialFrame() internal view returns (ConsensusFrame memory);
```

### _getFrameAtTimestamp


```solidity
function _getFrameAtTimestamp(uint256 timestamp, FrameConfig memory config)
    internal
    view
    returns (ConsensusFrame memory);
```

### _getFrameAtIndex


```solidity
function _getFrameAtIndex(uint256 frameIndex, FrameConfig memory config)
    internal
    view
    returns (ConsensusFrame memory);
```

### _computeFrameStartEpoch


```solidity
function _computeFrameStartEpoch(uint256 timestamp, FrameConfig memory config) internal view returns (uint256);
```

### _computeStartEpochOfFrameWithIndex


```solidity
function _computeStartEpochOfFrameWithIndex(uint256 frameIndex, FrameConfig memory config)
    internal
    pure
    returns (uint256);
```

### _computeFrameIndex


```solidity
function _computeFrameIndex(uint256 timestamp, FrameConfig memory config) internal view returns (uint256);
```

### _computeTimestampAtSlot


```solidity
function _computeTimestampAtSlot(uint256 slot) internal view returns (uint256);
```

### _computeSlotAtTimestamp


```solidity
function _computeSlotAtTimestamp(uint256 timestamp) internal view returns (uint256);
```

### _computeEpochAtSlot


```solidity
function _computeEpochAtSlot(uint256 slot) internal view returns (uint256);
```

### _computeEpochAtTimestamp


```solidity
function _computeEpochAtTimestamp(uint256 timestamp) internal view returns (uint256);
```

### _computeStartSlotAtEpoch


```solidity
function _computeStartSlotAtEpoch(uint256 epoch) internal view returns (uint256);
```

### _getTime


```solidity
function _getTime() internal view virtual returns (uint256);
```

### _isMember


Implementation: members


```solidity
function _isMember(address addr) internal view returns (bool);
```

### _getMemberIndex


```solidity
function _getMemberIndex(address addr) internal view returns (uint256);
```

### _addMember


```solidity
function _addMember(address addr, uint256 quorum) internal;
```

### _removeMember


```solidity
function _removeMember(address addr, uint256 quorum) internal;
```

### _setFastLaneLengthSlots


```solidity
function _setFastLaneLengthSlots(uint256 fastLaneLengthSlots) internal;
```

### _getFastLaneSubset

Returns start and past-end indices (mod totalMembers) of the fast lane members subset.


```solidity
function _getFastLaneSubset(uint256 frameIndex, uint256 totalMembers)
    internal
    view
    returns (uint256 startIndex, uint256 pastEndIndex);
```

### _isFastLaneMember

Tests whether the member with the given `index` is in the fast lane subset for the
given reporting `frameIndex`.


```solidity
function _isFastLaneMember(uint256 index, uint256 frameIndex) internal view returns (bool);
```

### _getMembers


```solidity
function _getMembers(bool fastLane)
    internal
    view
    returns (address[] memory addresses, uint256[] memory lastReportedRefSlots);
```

### _submitReport


Implementation: consensus


```solidity
function _submitReport(uint256 slot, bytes32 report, uint256 consensusVersion) internal;
```

### _consensusReached


```solidity
function _consensusReached(ConsensusFrame memory frame, bytes32 report, uint256 variantIndex, uint256 support)
    internal;
```

### _consensusNotReached


```solidity
function _consensusNotReached(ConsensusFrame memory frame) internal;
```

### _setQuorumAndCheckConsensus


```solidity
function _setQuorumAndCheckConsensus(uint256 quorum, uint256 totalMembers) internal;
```

### _checkConsensus


```solidity
function _checkConsensus(uint256 quorum) internal;
```

### _getConsensusReport


```solidity
function _getConsensusReport(uint256 currentRefSlot, uint256 quorum)
    internal
    view
    returns (bytes32 report, int256 variantIndex, uint256 support);
```

### _setReportProcessor


Implementation: report processing


```solidity
function _setReportProcessor(address newProcessor) internal;
```

### _getLastProcessingRefSlot


```solidity
function _getLastProcessingRefSlot() internal view returns (uint256);
```

### _submitReportForProcessing


```solidity
function _submitReportForProcessing(ConsensusFrame memory frame, bytes32 report) internal;
```

### _cancelReportProcessing


```solidity
function _cancelReportProcessing(ConsensusFrame memory frame) internal;
```

### _getConsensusVersion


```solidity
function _getConsensusVersion() internal view returns (uint256);
```

## Events
### FrameConfigSet

```solidity
event FrameConfigSet(uint256 newInitialEpoch, uint256 newEpochsPerFrame);
```

### FastLaneConfigSet

```solidity
event FastLaneConfigSet(uint256 fastLaneLengthSlots);
```

### MemberAdded

```solidity
event MemberAdded(address indexed addr, uint256 newTotalMembers, uint256 newQuorum);
```

### MemberRemoved

```solidity
event MemberRemoved(address indexed addr, uint256 newTotalMembers, uint256 newQuorum);
```

### QuorumSet

```solidity
event QuorumSet(uint256 newQuorum, uint256 totalMembers, uint256 prevQuorum);
```

### ReportReceived

```solidity
event ReportReceived(uint256 indexed refSlot, address indexed member, bytes32 report);
```

### ConsensusReached

```solidity
event ConsensusReached(uint256 indexed refSlot, bytes32 report, uint256 support);
```

### ConsensusLost

```solidity
event ConsensusLost(uint256 indexed refSlot);
```

### ReportProcessorSet

```solidity
event ReportProcessorSet(address indexed processor, address indexed prevProcessor);
```

## Errors
### InvalidChainConfig

```solidity
error InvalidChainConfig();
```

### NumericOverflow

```solidity
error NumericOverflow();
```

### AdminCannotBeZero

```solidity
error AdminCannotBeZero();
```

### ReportProcessorCannotBeZero

```solidity
error ReportProcessorCannotBeZero();
```

### DuplicateMember

```solidity
error DuplicateMember();
```

### AddressCannotBeZero

```solidity
error AddressCannotBeZero();
```

### InitialEpochIsYetToArrive

```solidity
error InitialEpochIsYetToArrive();
```

### InitialEpochAlreadyArrived

```solidity
error InitialEpochAlreadyArrived();
```

### InitialEpochRefSlotCannotBeEarlierThanProcessingSlot

```solidity
error InitialEpochRefSlotCannotBeEarlierThanProcessingSlot();
```

### EpochsPerFrameCannotBeZero

```solidity
error EpochsPerFrameCannotBeZero();
```

### NonMember

```solidity
error NonMember();
```

### UnexpectedConsensusVersion

```solidity
error UnexpectedConsensusVersion(uint256 expected, uint256 received);
```

### QuorumTooSmall

```solidity
error QuorumTooSmall(uint256 minQuorum, uint256 receivedQuorum);
```

### InvalidSlot

```solidity
error InvalidSlot();
```

### DuplicateReport

```solidity
error DuplicateReport();
```

### EmptyReport

```solidity
error EmptyReport();
```

### StaleReport

```solidity
error StaleReport();
```

### NonFastLaneMemberCannotReportWithinFastLaneInterval

```solidity
error NonFastLaneMemberCannotReportWithinFastLaneInterval();
```

### NewProcessorCannotBeTheSame

```solidity
error NewProcessorCannotBeTheSame();
```

### ConsensusReportAlreadyProcessing

```solidity
error ConsensusReportAlreadyProcessing();
```

### FastLanePeriodCannotBeLongerThanFrame

```solidity
error FastLanePeriodCannotBeLongerThanFrame();
```

## Structs
### FrameConfig

```solidity
struct FrameConfig {
    uint64 initialEpoch;
    uint64 epochsPerFrame;
    uint64 fastLaneLengthSlots;
}
```

### ConsensusFrame
Oracle reporting is divided into frames, each lasting the same number of slots.
The start slot of the next frame is always the next slot after the end slot of the previous
frame.
Each frame also has a reference slot: if the oracle report contains any data derived from
onchain data, the onchain data should be sampled at the reference slot.


```solidity
struct ConsensusFrame {
    // frame index; increments by 1 with each frame but resets to zero on frame size change
    uint256 index;
    // the slot at which to read the state around which consensus is being reached;
    // if the slot contains a block, the state should include all changes from that block
    uint256 refSlot;
    // the last slot at which a report can be reported and processed
    uint256 reportProcessingDeadlineSlot;
}
```

### ReportingState

```solidity
struct ReportingState {
    // the last reference slot any report was received for
    uint64 lastReportRefSlot;
    // the last reference slot a consensus was reached for
    uint64 lastConsensusRefSlot;
    // the last consensus variant index
    uint64 lastConsensusVariantIndex;
}
```

### MemberState

```solidity
struct MemberState {
    // the last reference slot a report from this member was received for
    uint64 lastReportRefSlot;
    // the variant index of the last report from this member
    uint64 lastReportVariantIndex;
}
```

### ReportVariant

```solidity
struct ReportVariant {
    // the reported hash
    bytes32 hash;
    // how many unique members from the current set reported this hash in the current frame
    uint64 support;
}
```

### MemberConsensusState

```solidity
struct MemberConsensusState {
    /// @notice Current frame's reference slot.
    uint256 currentFrameRefSlot;
    /// @notice Consensus report for the current frame, if any. Zero bytes otherwise.
    bytes32 currentFrameConsensusReport;
    /// @notice Whether the provided address is a member of the oracle committee.
    bool isMember;
    /// @notice Whether the oracle committee member is in the fast lane members subset
    /// of the current reporting frame. See `getIsFastLaneMember`.
    bool isFastLane;
    /// @notice Whether the oracle committee member is allowed to submit a report at
    /// the moment of the call.
    bool canReport;
    /// @notice The last reference slot for which the member submitted a report.
    uint256 lastMemberReportRefSlot;
    /// @notice The hash reported by the member for the current frame, if any.
    /// Zero bytes otherwise.
    bytes32 currentFrameMemberReport;
}
```

