// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { MAX_BP } from "src/lib/Constants.sol";
import { OperatorTierState } from "src/interfaces/ITiersRegistry.sol";

/// @dev Minimal TiersRegistry mock for MetaRegistry tests.
///      Stores weight multiplier increments above MAX_BP, mirroring TiersRegistry storage.
///      Effective weightMultiplier = MAX_BP + increment (0 increment = identity = MAX_BP).
contract TiersRegistryMock {
    mapping(uint256 => uint256) private _weightMultiplierInc;

    function getOperatorTierState(uint256 nodeOperatorId) external view returns (OperatorTierState memory state) {
        state.weightMultiplier = MAX_BP + _weightMultiplierInc[nodeOperatorId];
    }

    function mock_setWeightMultiplierInc(uint256 nodeOperatorId, uint256 increment) external {
        _weightMultiplierInc[nodeOperatorId] = increment;
    }
}
