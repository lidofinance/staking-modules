# PausableUntil
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/lib/utils/PausableUntil.sol)


## State Variables
### RESUME_SINCE_TIMESTAMP_POSITION
Contract resume/pause control storage slot


```solidity
bytes32 internal constant RESUME_SINCE_TIMESTAMP_POSITION = keccak256("lido.PausableUntil.resumeSinceTimestamp")
```


### PAUSE_INFINITELY
Special value for the infinite pause


```solidity
uint256 public constant PAUSE_INFINITELY = type(uint256).max
```


## Functions
### whenPaused

Reverts when resumed


```solidity
modifier whenPaused() ;
```

### whenResumed

Reverts when paused


```solidity
modifier whenResumed() ;
```

### getResumeSinceTimestamp

Returns one of:
- PAUSE_INFINITELY if paused infinitely returns
- first second when get contract get resumed if paused for specific duration
- some timestamp in past if not paused


```solidity
function getResumeSinceTimestamp() external view returns (uint256);
```

### isPaused

Returns whether the contract is paused


```solidity
function isPaused() public view returns (bool);
```

### _resume


```solidity
function _resume() internal;
```

### _pauseFor


```solidity
function _pauseFor(uint256 duration) internal;
```

### _pauseUntil


```solidity
function _pauseUntil(uint256 pauseUntilInclusive) internal;
```

### _setPausedState


```solidity
function _setPausedState(uint256 resumeSince) internal;
```

### _checkPaused


```solidity
function _checkPaused() internal view;
```

### _checkResumed


```solidity
function _checkResumed() internal view;
```

## Events
### Paused
Emitted when paused by the `pauseFor` or `pauseUntil` call


```solidity
event Paused(uint256 duration);
```

### Resumed
Emitted when resumed by the `resume` call


```solidity
event Resumed();
```

## Errors
### ZeroPauseDuration

```solidity
error ZeroPauseDuration();
```

### PausedExpected

```solidity
error PausedExpected();
```

### ResumedExpected

```solidity
error ResumedExpected();
```

### PauseUntilMustBeInFuture

```solidity
error PauseUntilMustBeInFuture();
```

