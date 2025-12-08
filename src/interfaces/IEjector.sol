// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { ICSModule } from "./ICSModule.sol";
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

    event VoluntaryEjectionRequested(
        uint256 indexed nodeOperatorId,
        bytes pubkey,
        address refundRecipient
    );

    event BadPerformerEjectionRequested(
        uint256 indexed nodeOperatorId,
        bytes pubkey,
        address refundRecipient
    );

    function PAUSE_ROLE() external view returns (bytes32);

    function RESUME_ROLE() external view returns (bytes32);

    function RECOVERER_ROLE() external view returns (bytes32);

    function STAKING_MODULE_ID() external view returns (uint256);

    function MODULE() external view returns (ICSModule);

    function STRIKES() external view returns (address);

    /// @notice Pause ejection methods calls
    /// @param duration Duration of the pause in seconds
    function pauseFor(uint256 duration) external;

    /// @notice Resume ejection methods calls
    function resume() external;

    /// @notice Withdraw the validator key from the Node Operator
    /// @notice Called by the node operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param startFrom Index of the first key to withdraw
    /// @param keysCount Number of keys to withdraw
    /// @param refundRecipient Address to send the refund to
    function voluntaryEject(
        uint256 nodeOperatorId,
        uint256 startFrom,
        uint256 keysCount,
        address refundRecipient
    ) external payable;

    /// @notice Withdraw the validator key from the Node Operator
    /// @notice Called by the node operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndices Array of indices of the keys to withdraw
    /// @param refundRecipient Address to send the refund to
    function voluntaryEjectByArray(
        uint256 nodeOperatorId,
        uint256[] calldata keyIndices,
        address refundRecipient
    ) external payable;

    /// @notice Eject Node Operator's key as a bad performer
    /// @notice Called by the `ValidatorStrikes` contract.
    ///         See `ValidatorStrikes.processBadPerformanceProof` to use this method permissionless
    /// @param nodeOperatorId ID of the Node Operator
    /// @param keyIndex index of deposited key to eject
    /// @param refundRecipient Address to send the refund to
    function ejectBadPerformer(
        uint256 nodeOperatorId,
        uint256 keyIndex,
        address refundRecipient
    ) external payable;

    /// @notice TriggerableWithdrawalsGateway implementation used by the contract.
    function triggerableWithdrawalsGateway()
        external
        view
        returns (ITriggerableWithdrawalsGateway);
}
