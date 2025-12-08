// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IERC20Permit } from "./IERC20Permit.sol";

/**
 * @title Interface defining ERC20-compatible StETH token
 */
interface IStETH is IERC20Permit {
    /**
     * @notice Get stETH amount by the provided shares amount
     * @param _sharesAmount shares amount
     * @dev dual to `getSharesByPooledEth`.
     */
    function getPooledEthByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);

    /**
     * @notice Get shares amount by the provided stETH amount
     * @param _pooledEthAmount stETH amount
     * @dev dual to `getPooledEthByShares`.
     */
    function getSharesByPooledEth(
        uint256 _pooledEthAmount
    ) external view returns (uint256);

    /**
     * @notice Get shares amount of the provided account
     * @param _account provided account address.
     */
    function sharesOf(address _account) external view returns (uint256);

    /**
     * @notice Transfer `_sharesAmount` stETH shares from `_sender` to `_recipient` using allowance.
     */
    function transferSharesFrom(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    /**
     * @notice Moves `_sharesAmount` token shares from the caller's account to the `_recipient` account.
     */
    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);
}
