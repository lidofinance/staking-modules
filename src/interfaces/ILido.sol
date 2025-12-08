// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IStETH } from "./IStETH.sol";

/**
 * @title Interface defining Lido contract
 */
interface ILido is IStETH {
    function STAKING_CONTROL_ROLE() external view returns (bytes32);

    function submit(address _referral) external payable returns (uint256);

    function deposit(
        uint256 _maxDepositsCount,
        uint256 _stakingModuleId,
        bytes calldata _depositCalldata
    ) external;

    function removeStakingLimit() external;

    function kernel() external returns (address);

    function sharesOf(address _account) external view returns (uint256);
}
