// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IERC2612 } from "./IERC2612.sol";

/**
 * @title Interface defining ERC20-compatible token
 */
interface IERC20Permit is IERC2612 {
    function balanceOf(address _account) external view returns (uint256);

    /**
     * @notice Moves `_amount` from the caller's account to the `_recipient` account.
     */
    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool);

    /**
     * @notice Moves `_amount` from the `_sender` account to the `_recipient` account.
     */
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);

    function approve(address _spender, uint256 _amount) external returns (bool);

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256);
}
