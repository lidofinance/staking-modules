# Versioned
[Git Source](https://github.com/lidofinance/community-staking-module/blob/de4144084a97217bb3f534716c5d2055d3f33c86/src/lib/utils/Versioned.sol)


## State Variables
### CONTRACT_VERSION_POSITION
Storage slot: uint256 version
Version of the initialized contract storage.
The version stored in CONTRACT_VERSION_POSITION equals to:
- 0 right after the deployment, before an initializer is invoked (and only at that moment);
- N after calling initialize(), where N is the initially deployed contract version;
- N after upgrading contract by calling finalizeUpgrade_vN().


```solidity
bytes32 internal constant CONTRACT_VERSION_POSITION = keccak256("lido.Versioned.contractVersion")
```


### PETRIFIED_VERSION_MARK

```solidity
uint256 internal constant PETRIFIED_VERSION_MARK = type(uint256).max
```


## Functions
### constructor


```solidity
constructor() ;
```

### getContractVersion

Returns the current contract version.


```solidity
function getContractVersion() public view returns (uint256);
```

### _initializeContractVersionTo

Sets the contract version to N. Should be called from the initialize() function.


```solidity
function _initializeContractVersionTo(uint256 version) internal;
```

### _updateContractVersion

Updates the contract version. Should be called from a finalizeUpgrade_vN() function.


```solidity
function _updateContractVersion(uint256 newVersion) internal;
```

### _checkContractVersion


```solidity
function _checkContractVersion(uint256 version) internal view;
```

### _setContractVersion


```solidity
function _setContractVersion(uint256 version) private;
```

## Events
### ContractVersionSet

```solidity
event ContractVersionSet(uint256 version);
```

## Errors
### NonZeroContractVersionOnInit

```solidity
error NonZeroContractVersionOnInit();
```

### InvalidContractVersion

```solidity
error InvalidContractVersion();
```

### InvalidContractVersionIncrement

```solidity
error InvalidContractVersionIncrement();
```

### UnexpectedContractVersion

```solidity
error UnexpectedContractVersion(uint256 expected, uint256 received);
```

