# CuratedModule
[Git Source](https://github.com/lidofinance/community-staking-module/blob/9963782f1f7ba72c08b80bceeb147febcf501cea/src/CuratedModule.sol)

**Inherits:**
[ICuratedModule](/Users/dgusakov/projects/community-staking-module/docs/src/src/interfaces/ICuratedModule.sol/interface.ICuratedModule.md), [CSModule](/Users/dgusakov/projects/community-staking-module/docs/src/src/CSModule.sol/contract.CSModule.md)


## State Variables
### OPERATOR_ADDRESSES_ADMIN_ROLE

```solidity
bytes32 public constant OPERATOR_ADDRESSES_ADMIN_ROLE = keccak256("OPERATOR_ADDRESSES_ADMIN_ROLE")
```


## Functions
### constructor


```solidity
constructor(
    bytes32 moduleType,
    address lidoLocator,
    address parametersRegistry,
    address _accounting, // solhint-disable-line lido-csm/vars-with-underscore
    address exitPenalties
) CSModule(moduleType, lidoLocator, parametersRegistry, _accounting, exitPenalties);
```

### obtainDepositData


```solidity
function obtainDepositData(
    uint256,
    /* depositsCount */
    bytes calldata /* depositCalldata */
)
    external
    override(CSModule, IStakingModule)
    onlyRole(STAKING_ROUTER_ROLE)
    returns (bytes memory publicKeys, bytes memory signatures);
```

### changeNodeOperatorAddresses

Change both reward and manager addresses of a node operator.


```solidity
function changeNodeOperatorAddresses(uint256 nodeOperatorId, address newManagerAddress, address newRewardAddress)
    external
    onlyRole(OPERATOR_ADDRESSES_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeOperatorId`|`uint256`|ID of the Node Operator|
|`newManagerAddress`|`address`|New manager address|
|`newRewardAddress`|`address`|New reward address|


