// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ERC20LockVault } from "./ERC20LockVault.sol";
import { IAragonVotingLockVault } from "./interfaces/IAragonVotingLockVault.sol";
import { ILidoAragonVoting } from "./interfaces/ILidoAragonVoting.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";
import { ILidoGovernanceLockVaultFactory } from "./interfaces/ILidoGovernanceLockVaultFactory.sol";
import { ISnapshotDelegation } from "./interfaces/ISnapshotDelegation.sol";
import { ISnapshotDelegationLockVault } from "./interfaces/ISnapshotDelegationLockVault.sol";

/// @notice ERC20 lock vault with Lido Aragon Voting and Snapshot delegation capabilities.
contract LidoGovernanceLockVault is ERC20LockVault, IAragonVotingLockVault, ISnapshotDelegationLockVault {
    address public immutable VOTING_CONTRACT;
    ILidoGovernanceLockVaultFactory public immutable GOVERNANCE_CONFIG;

    constructor(
        uint256 nodeOperatorId,
        address token,
        address provider,
        address module,
        address votingContract,
        address governanceConfig
    ) ERC20LockVault(nodeOperatorId, token, provider, module) {
        if (votingContract == address(0) || governanceConfig == address(0)) {
            revert IERC20LockVault.ZeroAddress();
        }

        VOTING_CONTRACT = votingContract;
        GOVERNANCE_CONFIG = ILidoGovernanceLockVaultFactory(governanceConfig);
    }

    /// @inheritdoc IAragonVotingLockVault
    function assignVotingDelegate(address votingDelegate) external {
        _checkNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).assignDelegate(votingDelegate);
    }

    /// @inheritdoc IAragonVotingLockVault
    function unassignVotingDelegate() external {
        _checkNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).unassignDelegate();
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function assignSnapshotDelegate(bytes32 snapshotSpaceId, address snapshotDelegate) external {
        _checkNodeOperatorOwner();

        ISnapshotDelegation(snapshotDelegation()).setDelegate(snapshotSpaceId, snapshotDelegate);
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function unassignSnapshotDelegate(bytes32 snapshotSpaceId) external {
        _checkNodeOperatorOwner();

        ISnapshotDelegation(snapshotDelegation()).clearDelegate(snapshotSpaceId);
    }

    /// @inheritdoc IAragonVotingLockVault
    function vote(uint256 voteId, bool support) external {
        _checkNodeOperatorOwner();

        ILidoAragonVoting(VOTING_CONTRACT).vote(voteId, support, false);
    }

    /// @inheritdoc ISnapshotDelegationLockVault
    function snapshotDelegation() public view returns (address) {
        return GOVERNANCE_CONFIG.snapshotDelegation();
    }
}
