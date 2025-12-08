// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IWithdrawalQueue {
    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    function ORACLE_ROLE() external view returns (bytes32);

    function getRoleMember(
        bytes32 role,
        uint256 index
    ) external view returns (address);

    function WSTETH() external view returns (address);

    /// @notice minimal amount of stETH that is possible to withdraw
    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    /// @notice maximum amount of stETH that is possible to withdraw by a single request
    /// Prevents accumulating too much funds per single request fulfillment in the future.
    /// @dev To withdraw larger amounts, it's recommended to split it to several requests
    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    function getWithdrawalRequests(
        address _owner
    ) external view returns (uint256[] memory requestsIds);

    function isBunkerModeActive() external view returns (bool);

    function onOracleReport(
        bool _isBunkerModeNow,
        uint256 _bunkerStartTimestamp,
        uint256 _currentReportTimestamp
    ) external;
}
