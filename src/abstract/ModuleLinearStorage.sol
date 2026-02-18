// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "../interfaces/IBaseModule.sol";

import { DepositQueueLib } from "../lib/DepositQueueLib.sol";

abstract contract ModuleLinearStorage {
    /// @dev Having this mapping here to preserve the current layout of the storage of the CSModule.
    mapping(uint256 priority => DepositQueueLib.Queue queue) internal _depositQueueByPriority;

    bytes32 internal __freeSlot1;
    uint256 internal _upToDateOperatorDepositInfoCount;
    /// @dev Total number of withdrawn validators reported for the module.
    uint256 internal _totalWithdrawnValidators;
    mapping(uint256 noKeyIndexPacked => uint256) internal _keyAddedBalances;

    uint256 internal _nonce;
    mapping(uint256 nodeOperatorId => NodeOperator) internal _nodeOperators;
    /// @dev see KeyPointerLib.keyPointer function for details of noKeyIndexPacked structure
    mapping(uint256 noKeyIndexPacked => bool) internal _isValidatorWithdrawn;
    mapping(uint256 noKeyIndexPacked => bool) internal _isValidatorSlashed;

    uint64 internal _totalDepositedValidators;
    uint64 internal _totalExitedValidators;
    uint64 internal _depositableValidatorsCount;
    uint64 internal _nodeOperatorsCount;
}
