// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "./IBaseModule.sol";

/// @notice Per-operator ERC20 vault used by the ERC20 lock boost provider.
interface IERC20LockVault {
    error ZeroTokenAddress();
    error ZeroProviderAddress();
    error ZeroModuleAddress();
    error ZeroReceiverAddress();
    error SenderIsNotProvider();
    error SenderIsNotNodeOperatorOwner();

    /// @notice Node Operator ID this vault belongs to.
    function nodeOperatorId() external view returns (uint256);

    /// @notice ERC20 token address.
    function TOKEN() external view returns (address);

    /// @notice ERC20 lock boost provider allowed to move tokens.
    function PROVIDER() external view returns (address);

    /// @notice Module used to resolve the current Node Operator owner.
    function MODULE() external view returns (IBaseModule);

    /// @notice Initialize per-vault state.
    /// @param nodeOperatorId Node Operator ID this vault belongs to.
    function initialize(uint256 nodeOperatorId) external;

    /// @notice Transfer tokens to the receiver.
    /// @param receiver Address to receive tokens.
    /// @param amount Token amount to transfer.
    function transferTokens(address receiver, uint256 amount) external;
}
