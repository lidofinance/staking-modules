# TwoPhaseFrameConfigUpdate
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/utils/TwoPhaseFrameConfigUpdate.sol)

A helper to offset the Oracle report schedule (e.g., move the report window by N epochs).
This is achieved via a two-phase frame configuration update in the HashConsensus contract used by the Oracle:
- Offset phase: set a transitional frame size (shorter or longer than the original) and disable the fast
lane after the Oracle has completed main phase in report processing for a defined number of reports with the original frame config.
- Restore phase: set the original frame size and the desired fast lane length after the Oracle has
completed main phase in report processing for a defined number of reports with the transitional config.
As a result, the Oracle report window is shifted by the following calculation:
- If currentEpochsPerFrame > offsetPhaseEpochsPerFrame:
`shift = reportsToProcessBeforeRestorePhase * (currentEpochsPerFrame - offsetPhaseEpochsPerFrame)`
- If offsetPhaseEpochsPerFrame > currentEpochsPerFrame:
`shift = reportsToProcessBeforeRestorePhase * (offsetPhaseEpochsPerFrame - currentEpochsPerFrame)`
---
Due to the CSM Oracle off-chain sanity checks, the frame config cannot be changed if there is a missing
report. Also, the frame config for the CSM oracle should not be changed such that the new reference slot is
in the past.

The contract should have `MANAGE_FRAME_CONFIG_ROLE` role granted on the
`HashConsensus` contract in order to be able to call `setFrameConfig`.


## State Variables
### ORACLE

```solidity
IReportAsyncProcessor public immutable ORACLE
```


### HASH_CONSENSUS

```solidity
IConsensusContract public immutable HASH_CONSENSUS
```


### SECONDS_PER_SLOT

```solidity
uint256 public immutable SECONDS_PER_SLOT
```


### GENESIS_TIME

```solidity
uint256 public immutable GENESIS_TIME
```


### SLOTS_PER_EPOCH

```solidity
uint256 public immutable SLOTS_PER_EPOCH
```


### OFFSET_PHASE_FAST_LANE_LENGTH
Fast lane is expected to be disabled during the offset phase.


```solidity
uint256 public constant OFFSET_PHASE_FAST_LANE_LENGTH = 0
```


### offsetPhase

```solidity
PhaseState public offsetPhase
```


### restorePhase

```solidity
PhaseState public restorePhase
```


## Functions
### constructor


```solidity
constructor(address oracle, PhasesConfig memory phasesConfig) ;
```

### executeOffsetPhase


```solidity
function executeOffsetPhase() external;
```

### executeRestorePhase


```solidity
function executeRestorePhase() external;
```

### renounceRoleWhenExpired

Fallback to renounce the role if phases are expired.


```solidity
function renounceRoleWhenExpired() external;
```

### isReadyForOffsetPhase


```solidity
function isReadyForOffsetPhase() external view returns (bool ready);
```

### isReadyForRestorePhase


```solidity
function isReadyForRestorePhase() external view returns (bool ready);
```

### getExpirationStatus


```solidity
function getExpirationStatus() external view returns (bool offsetExpired, bool restoreExpired);
```

### _renounceRole


```solidity
function _renounceRole() internal;
```

### _validate


```solidity
function _validate(PhaseState storage phaseState) internal view;
```

### _getCurrentSlot


```solidity
function _getCurrentSlot() internal view returns (uint256 currentSlot);
```

### _isReady


```solidity
function _isReady(PhaseState storage phaseState) internal view returns (bool ready);
```

### _isExpired


```solidity
function _isExpired(PhaseState storage phaseState) internal view returns (bool expired);
```

### _hasExpectedRefSlot


```solidity
function _hasExpectedRefSlot(PhaseState storage phaseState)
    internal
    view
    returns (bool matches, uint256 lastProcessingRefSlot);
```

## Events
### OffsetPhaseExecuted

```solidity
event OffsetPhaseExecuted();
```

### RestorePhaseExecuted

```solidity
event RestorePhaseExecuted();
```

## Errors
### ZeroOracleAddress

```solidity
error ZeroOracleAddress();
```

### ZeroEpochsPerFrame

```solidity
error ZeroEpochsPerFrame();
```

### ZeroReportsToEnableUpdate

```solidity
error ZeroReportsToEnableUpdate();
```

### CurrentReportMainPhaseIsNotCompleted

```solidity
error CurrentReportMainPhaseIsNotCompleted();
```

### FastLanePeriodCannotBeLongerThanFrame

```solidity
error FastLanePeriodCannotBeLongerThanFrame();
```

### FastLaneTooShort

```solidity
error FastLaneTooShort();
```

### NoneOfPhasesExpired

```solidity
error NoneOfPhasesExpired();
```

### PhaseAlreadyExecuted

```solidity
error PhaseAlreadyExecuted();
```

### OffsetPhaseNotExecuted

```solidity
error OffsetPhaseNotExecuted();
```

### PhaseExpired

```solidity
error PhaseExpired(uint256 currentSlot, uint256 deadlineSlot);
```

### UnexpectedLastProcessingRefSlot

```solidity
error UnexpectedLastProcessingRefSlot(uint256 actual, uint256 expected);
```

## Structs
### PhasesConfig

```solidity
struct PhasesConfig {
    /// @notice Reports to complete main phase in report processing from the `lastProcessingRefSlot` (as of deployment) to enable the offset phase.
    uint256 reportsToProcessBeforeOffsetPhase;
    /// @notice Reports to complete main phase in report processing after the offset phase completion to enable the restore phase.
    uint256 reportsToProcessBeforeRestorePhase;
    /// @notice Offset phase epochs per frame.
    uint256 offsetPhaseEpochsPerFrame;
    /// @notice Restore phase fast lane length in slots.
    uint256 restorePhaseFastLaneLengthSlots;
}
```

### PhaseState

```solidity
struct PhaseState {
    /// @notice Expected oracle's last processing ref slot for phase execution.
    ///         This phase can be executed when ORACLE.getLastProcessingRefSlot()
    ///         equals this value (i.e., oracle has completed the expected number of main phases in report processing).
    uint256 expectedProcessingRefSlot;
    /// @notice Slot when this phase expires.
    ///         This phase expires when the current slot (calculated from block.timestamp)
    ///         is greater than or equal to this value.
    uint256 expirationSlot;
    uint256 epochsPerFrame;
    uint256 fastLaneLengthSlots;
    bool executed;
}
```

