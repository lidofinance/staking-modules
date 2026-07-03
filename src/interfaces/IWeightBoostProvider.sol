// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Weight multiplier provider consumed by MetaRegistry.
interface IWeightBoostProvider {
    /// @notice Return weight multiplier in basis points for a node operator.
    /// @param nodeOperatorId Node Operator ID.
    /// @return multiplierBP Full multiplier in basis points. 10_000 means no scaling.
    function getWeightBoostMultiplierBP(uint256 nodeOperatorId) external view returns (uint256 multiplierBP);
}
