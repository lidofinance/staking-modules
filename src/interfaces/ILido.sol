// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStETH } from "./IStETH.sol";

/**
 * @title Interface defining Lido contract
 */
interface ILido is IStETH {
    function STAKING_CONTROL_ROLE() external view returns (bytes32);

    function submit(address _referral) external payable returns (uint256);

    function getDepositableEther() external view returns (uint256);

    function removeStakingLimit() external;

    function kernel() external returns (address);

    function sharesOf(address _account) external view returns (uint256);
}
