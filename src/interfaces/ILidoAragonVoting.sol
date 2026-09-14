// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Lido Aragon Voting interface used by token lock vaults.
interface ILidoAragonVoting {
    /// @notice Assign delegate allowed to vote on behalf of msg.sender.
    /// @param delegate Address of the delegate.
    function assignDelegate(address delegate) external;

    /// @notice Remove msg.sender's current voting delegate.
    function unassignDelegate() external;

    /// @notice Vote directly from msg.sender's voting power.
    /// @param voteId Vote ID.
    /// @param support Whether to support the vote.
    /// @param executesIfDecided Deprecated flag kept for ABI compatibility.
    function vote(uint256 voteId, bool support, bool executesIfDecided) external;
}
