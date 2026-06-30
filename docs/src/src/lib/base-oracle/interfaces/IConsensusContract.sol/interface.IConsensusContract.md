# IConsensusContract
[Git Source](https://github.com/lidofinance/staking-modules/blob/daa40a3672f26250a2437c260b2926e18e6eb453/src/lib/base-oracle/interfaces/IConsensusContract.sol)


## Functions
### MANAGE_FRAME_CONFIG_ROLE


```solidity
function MANAGE_FRAME_CONFIG_ROLE() external view returns (bytes32);
```

### getIsMember


```solidity
function getIsMember(address addr) external view returns (bool);
```

### getCurrentFrame


```solidity
function getCurrentFrame() external view returns (uint256 refSlot, uint256 reportProcessingDeadlineSlot);
```

### getChainConfig


```solidity
function getChainConfig() external view returns (uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime);
```

### getFrameConfig


```solidity
function getFrameConfig()
    external
    view
    returns (uint256 initialEpoch, uint256 epochsPerFrame, uint256 fastLaneLengthSlots);
```

### getInitialRefSlot


```solidity
function getInitialRefSlot() external view returns (uint256);
```

### setFrameConfig


```solidity
function setFrameConfig(uint256 epochsPerFrame, uint256 fastLaneLengthSlots) external;
```

