// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperator } from "../interfaces/IBaseModule.sol";

import { DepositQueueLib } from "../lib/DepositQueueLib.sol";

abstract contract ModuleLinearStorage {
    /// @dev Linear storage layout of the module. All state lives in a single struct
    ///      accessed via `_baseStorage()` at slot 0.
    struct BaseModuleStorage {
        /// @dev Having this mapping here to preserve the current layout of the storage of the CSModule.
        mapping(uint256 priority => DepositQueueLib.Queue queue) depositQueueByPriority;
        bytes32 freeSlot1;
        uint256 upToDateOperatorDepositInfoCount;
        /// @dev Total number of withdrawn validators reported for the module.
        uint256 totalWithdrawnValidators;
        mapping(uint256 noKeyIndexPacked => uint256) keyAddedBalances;
        uint256 nonce;
        mapping(uint256 nodeOperatorId => NodeOperator) nodeOperators;
        /// @dev see KeyPointerLib.keyPointer function for details of noKeyIndexPacked structure
        mapping(uint256 noKeyIndexPacked => bool) isValidatorWithdrawn;
        mapping(uint256 noKeyIndexPacked => bool) isValidatorSlashed;
        uint64 totalDepositedValidators;
        uint64 totalExitedValidators;
        uint64 depositableValidatorsCount;
        uint64 nodeOperatorsCount;
    }

    function _baseStorage() internal pure returns (BaseModuleStorage storage $) {
        assembly ("memory-safe") {
            // ModuleLinearStorage starts at slot 0 in the current inheritance layout.
            $.slot := 0
        }
    }
}
