// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Factory creating per-operator ERC20 lock vaults.
interface IERC20LockVaultFactory {
    error ZeroAddress();

    /// @notice Create a vault for the provided Node Operator.
    /// @param nodeOperatorId Node Operator ID.
    /// @param token ERC20 token locked in the vault.
    /// @param provider ERC20 lock boost provider allowed to move locked tokens.
    /// @param module Module used by optional vault capabilities to resolve the current owner.
    /// @return vault Created vault address.
    function createVault(
        uint256 nodeOperatorId,
        address token,
        address provider,
        address module
    ) external returns (address vault);
}
