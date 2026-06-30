# SSZ
[Git Source](https://github.com/lidofinance/staking-modules/blob/68bbef5148bb51c1967785a7c6ed6e168acccc0f/src/lib/SSZ.sol)


## Functions
### hashTreeRoot


```solidity
function hashTreeRoot(BeaconBlockHeader memory header) internal view returns (bytes32 root);
```

### hashTreeRoot


```solidity
function hashTreeRoot(Validator memory validator) internal view returns (bytes32 root);
```

### verifyProof

Modified version of `verify` from Solady `MerkleProofLib` to support generalized indices and sha256 precompile.

Reverts if `leaf` doesn't exist in the Merkle tree with `root`, given `proof`.


```solidity
function verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf, GIndex gI) internal view;
```

### hashTreeRoot


```solidity
function hashTreeRoot(Withdrawal memory withdrawal) internal pure returns (bytes32);
```

### toLittleEndian


```solidity
function toLittleEndian(uint256 v) internal pure returns (bytes32);
```

### toLittleEndian


```solidity
function toLittleEndian(bool v) internal pure returns (bytes32);
```

### endianReverse


```solidity
function endianReverse(bytes32 v) internal pure returns (bytes32);
```

## Errors
### BranchHasMissingItem

```solidity
error BranchHasMissingItem();
```

### BranchHasExtraItem

```solidity
error BranchHasExtraItem();
```

### InvalidProof

```solidity
error InvalidProof();
```

