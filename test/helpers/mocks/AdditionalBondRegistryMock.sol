// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IWeightBoostProvider } from "src/interfaces/IWeightBoostProvider.sol";
import { MAX_BP } from "src/lib/Constants.sol";

/// @dev Minimal AdditionalBondRegistry mock for MetaRegistry tests.
///      Stores the weight multiplier increment above MAX_BP, mirroring AdditionalBondRegistry storage.
contract AdditionalBondRegistryMock is IWeightBoostProvider {
    mapping(uint256 => uint256) private _weightMultiplier;

    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP) {
        multiplierBP = MAX_BP + _weightMultiplier[nodeOperatorId];
    }

    function mock_setWeightMultiplier(uint256 nodeOperatorId, uint256 weightMultiplier) external {
        _weightMultiplier[nodeOperatorId] = weightMultiplier;
    }
}
