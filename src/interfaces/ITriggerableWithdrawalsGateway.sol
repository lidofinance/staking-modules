// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

struct ValidatorData {
    uint256 stakingModuleId;
    uint256 nodeOperatorId;
    bytes pubkey;
}

interface ITriggerableWithdrawalsGateway {
    function ADD_FULL_WITHDRAWAL_REQUEST_ROLE() external view returns (bytes32);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function getRoleMember(
        bytes32 role,
        uint256 index
    ) external view returns (address);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    /**
     * @dev Submits Triggerable Withdrawal Requests to the Withdrawal Vault as full withdrawal requests
     *      for the specified validator public keys.
     *
     * @param triggerableExitsData An array of `ValidatorData` structs, each representing a validator
     * for which a withdrawal request will be submitted. Each entry includes:
     *   - `stakingModuleId`: ID of the staking module.
     *   - `nodeOperatorId`: ID of the node operator.
     *   - `pubkey`: Validator public key, 48 bytes length.
     * @param refundRecipient The address that will receive any excess ETH sent for fees.
     * @param exitType A parameter indicating the type of exit, passed to the Staking Module.
     *
     * Emits `TriggerableExitRequest` event for each validator in list.
     *
     * @notice Reverts if:
     *     - The caller does not have the `ADD_FULL_WITHDRAWAL_REQUEST_ROLE`
     *     - The total fee value sent is insufficient to cover all provided TW requests.
     *     - There is not enough limit quota left in the current frame to process all requests.
     */
    function triggerFullWithdrawals(
        ValidatorData[] calldata triggerableExitsData,
        address refundRecipient,
        uint256 exitType
    ) external payable;
}
