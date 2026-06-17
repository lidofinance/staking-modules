// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { MAX_BP } from "src/lib/Constants.sol";
import { OperatorTierState } from "src/interfaces/IAdditionalBondRegistry.sol";

/// @dev Minimal AdditionalBondRegistry mock for MetaRegistry tests.
///      Stores the weight multiplier increment above MAX_BP, mirroring AdditionalBondRegistry storage;
///      getOperatorTierState returns the effective value MAX_BP + increment (0 = identity = MAX_BP).
contract AdditionalBondRegistryMock {
    mapping(uint256 => uint256) private _weightMultiplier;

    function getOperatorTierState(uint256 nodeOperatorId) external view returns (OperatorTierState memory state) {
        state.weightMultiplier = MAX_BP + _weightMultiplier[nodeOperatorId];
    }

    function mock_setWeightMultiplier(uint256 nodeOperatorId, uint256 weightMultiplier) external {
        _weightMultiplier[nodeOperatorId] = weightMultiplier;
    }
}
