// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

/// @notice Optional Aragon Voting capability for an ERC20 lock vault.
interface IAragonVotingLockVault {
    /// @notice Lido Aragon Voting contract used by this vault.
    function VOTING_CONTRACT() external view returns (address);

    /// @notice Assign an Aragon Voting delegate from the vault address.
    /// @param votingDelegate Address to assign as delegate.
    function assignVotingDelegate(address votingDelegate) external;

    /// @notice Remove the current Aragon Voting delegate from the vault address.
    function unassignVotingDelegate() external;

    /// @notice Cast a direct Aragon vote from the vault address.
    /// @param voteId Vote ID.
    /// @param support Whether to support the vote.
    function vote(uint256 voteId, bool support) external;
}
