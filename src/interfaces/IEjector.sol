// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IBaseModule } from "./IBaseModule.sol";
import { IExitTypes } from "./IExitTypes.sol";
import { ITriggerableWithdrawalsGateway } from "./ITriggerableWithdrawalsGateway.sol";

interface IEjector is IExitTypes {
    error SigningKeysInvalidOffset();
    error AlreadyWithdrawn();
    error ZeroAdminAddress();
    error ZeroModuleAddress();
    error ZeroStrikesAddress();
    error NodeOperatorDoesNotExist();
    error SenderIsNotEligible();
    error SenderIsNotStrikes();
    error NothingToEject();
    error DuplicateKeyIndex();
    error ZeroRefundRecipient();
    error StakingModuleIdNotFound();

    event VoluntaryEjectionRequested(uint256 indexed nodeOperatorId, bytes pubkey, address refundRecipient);

    event BadPerformerEjectionRequested(uint256 indexed nodeOperatorId, bytes pubkey, address refundRecipient);
    event StakingModuleIdCached(uint256 stakingModuleId);

    function stakingModuleId() external view returns (uint256);

    function MODULE() external view returns (IBaseModule);

    function STRIKES() external view returns (address);

    /// @notice Request triggerable full withdrawals for Node Operator validator keys
    /// @dev Called by the node operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndices Array of indices of the keys to withdraw
    /// @param refundRecipient Address to send the refund to
    function voluntaryEject(
        uint256 nodeOperatorId,
        uint256[] calldata keyIndices,
        address refundRecipient
    ) external payable;

    /// @notice Eject Node Operator's key as a bad performer
    /// @dev Called by the `ValidatorStrikes` contract.
    ///         See `ValidatorStrikes.processBadPerformanceProof` to use this method permissionless
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndex index of deposited key to eject
    /// @param refundRecipient Address to send the refund to
    function ejectBadPerformer(uint256 nodeOperatorId, uint256 keyIndex, address refundRecipient) external payable;

    /// @notice TriggerableWithdrawalsGateway implementation used by the contract.
    function triggerableWithdrawalsGateway() external view returns (ITriggerableWithdrawalsGateway);
}
