// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IStETH } from "../../../src/interfaces/IStETH.sol";

contract WithdrawalQueueMock {
    address public WSTETH;
    IStETH public stETH;
    /// @notice minimal amount of stETH that is possible to withdraw
    uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;

    /// @notice maximum amount of stETH that is possible to withdraw by a single request
    /// Prevents accumulating too much funds per single request fulfillment in the future.
    /// @dev To withdraw larger amounts, it's recommended to split it to several requests
    uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;

    constructor(address wsteth, address steth) {
        WSTETH = wsteth;
        stETH = IStETH(steth);
    }

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address /* _owner */
    ) external returns (uint256[] memory requestIds) {
        requestIds = new uint256[](_amounts.length);
        for (uint256 i = 0; i < _amounts.length; ++i) {
            stETH.transferFrom(msg.sender, address(this), _amounts[i]);
            requestIds[i] = i;
        }
    }
}
