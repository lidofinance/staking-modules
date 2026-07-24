// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ERC20LockVault } from "./ERC20LockVault.sol";
import { IAragonVotingLockVault } from "./interfaces/IAragonVotingLockVault.sol";
import { ILidoAragonVoting } from "./interfaces/ILidoAragonVoting.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";
import { ISnapshotDelegation } from "./interfaces/ISnapshotDelegation.sol";
import { ISnapshotDelegationLockVault } from "./interfaces/ISnapshotDelegationLockVault.sol";
import { SNAPSHOT_ALL_SPACES } from "./lib/Constants.sol";

/// @notice ERC20 lock vault with Lido Aragon Voting and Snapshot delegation capabilities.
contract LidoGovernanceLockVault is ERC20LockVault, IAragonVotingLockVault, ISnapshotDelegationLockVault {
    address public immutable VOTING_CONTRACT;
    address public immutable SNAPSHOT_DELEGATION;

    constructor(
        address token,
        address provider,
        address module,
        address votingContract,
        address snapshotDelegation_
    ) ERC20LockVault(token, provider, module) {
        if (votingContract == address(0) || snapshotDelegation_ == address(0)) {
            revert IERC20LockVault.ZeroAddress();
        }

        VOTING_CONTRACT = votingContract;
        SNAPSHOT_DELEGATION = snapshotDelegation_;
    }

    /// @inheritdoc IAragonVotingLockVault
    function assignVotingDelegate(address votingDelegate) external {
        _onlyNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).assignDelegate(votingDelegate);
    }

    /// @inheritdoc IAragonVotingLockVault
    function unassignVotingDelegate() external {
        _onlyNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).unassignDelegate();
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function assignSnapshotDelegate(address snapshotDelegate) external {
        _onlyNodeOperatorOwner();

        ISnapshotDelegation(snapshotDelegation()).setDelegate(SNAPSHOT_ALL_SPACES, snapshotDelegate);
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function unassignSnapshotDelegate() external {
        _onlyNodeOperatorOwner();

        ISnapshotDelegation(snapshotDelegation()).clearDelegate(SNAPSHOT_ALL_SPACES);
    }

    /// @inheritdoc IAragonVotingLockVault
    function vote(uint256 voteId, bool support) external {
        _onlyNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).vote(voteId, support, false);
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function snapshotDelegation() public view returns (address) {
        return SNAPSHOT_DELEGATION;
    }
}
