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
        /* 0 */ mapping(uint256 priority => DepositQueueLib.Queue queue) depositQueueByPriority;
        /* 1 */ mapping(uint256 noKeyIndexPacked => uint256) keyAllocatedBalance;
        /* 2 */ mapping(uint256 noKeyIndexPacked => uint256) keyConfirmedBalance;
        /// @dev Total number of withdrawn validators reported for the module.
        /* 3 */ uint256 totalWithdrawnValidators;
        /* 4 */ uint256 upToDateOperatorDepositInfoCount;
        /* 5 */ uint256 nonce;
        /* 6 */ mapping(uint256 nodeOperatorId => NodeOperator) nodeOperators;
        /// @dev see KeyPointerLib.keyPointer function for details of noKeyIndexPacked structure
        /* 7 */ mapping(uint256 noKeyIndexPacked => bool) isValidatorWithdrawn;
        /* 8 */ mapping(uint256 noKeyIndexPacked => bool) isValidatorSlashed;
        /* 9 */ uint64 totalDepositedValidators;
        /* 9 */ uint64 totalExitedValidators;
        /* 9 */ uint64 depositableValidatorsCount;
        /* 9 */ uint64 nodeOperatorsCount;
        /* 10 */ mapping(uint256 nodeOperatorId => uint256 extraBalance) operatorBalances;
        /* 11 */ uint256 totalExtraStake;
    }

    function _baseStorage() internal pure returns (BaseModuleStorage storage $) {
        assembly ("memory-safe") {
            // ModuleLinearStorage starts at slot 0 in the current inheritance layout.
            $.slot := 0
        }
    }
}
