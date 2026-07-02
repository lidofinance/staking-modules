// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import { ILidoGovernanceLockVaultFactory } from "./interfaces/ILidoGovernanceLockVaultFactory.sol";
import { LidoGovernanceLockVault } from "./LidoGovernanceLockVault.sol";

/// @notice Factory creating ERC20 lock vaults with Lido governance capabilities.
contract LidoGovernanceLockVaultFactory is ILidoGovernanceLockVaultFactory, AccessControlEnumerable {
    address public immutable VOTING_CONTRACT;
    address public snapshotDelegation;

    constructor(address admin, address votingContract, address snapshotDelegation_) {
        if (admin == address(0) || votingContract == address(0) || snapshotDelegation_ == address(0)) {
            revert ZeroAddress();
        }

        VOTING_CONTRACT = votingContract;
        snapshotDelegation = snapshotDelegation_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Set Snapshot delegation registry used by all created vaults.
    /// @param snapshotDelegation_ New Snapshot delegation registry.
    function setSnapshotDelegation(address snapshotDelegation_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (snapshotDelegation_ == address(0)) revert ZeroAddress();
        if (snapshotDelegation == snapshotDelegation_) revert SameSnapshotDelegation();

        snapshotDelegation = snapshotDelegation_;
        emit SnapshotDelegationSet(snapshotDelegation_);
    }

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
    ) external returns (address vault) {
        vault = address(
            new LidoGovernanceLockVault({
                nodeOperatorId: nodeOperatorId,
                token: token,
                provider: provider,
                module: module,
                votingContract: VOTING_CONTRACT,
                vaultFactory: address(this)
            })
        );
    }
}
