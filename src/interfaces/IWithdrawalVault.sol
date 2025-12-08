// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IWithdrawalVault {
    event WithdrawalRequestAdded(bytes request);

    function getWithdrawalRequestFee() external view returns (uint256);
}
