// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

/// @notice Minimal module interface required by `OperatorsData`
interface INodeOperatorOwner {
    function getNodeOperatorOwner(
        uint256 nodeOperatorId
    ) external view returns (address);
}
