// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { ILidoLocator } from "./ILidoLocator.sol";
import { ILido } from "./ILido.sol";
import { IWithdrawalQueue } from "./IWithdrawalQueue.sol";
import { IWstETH } from "./IWstETH.sol";

interface IBondCore {
    event BondDepositedETH(
        uint256 indexed nodeOperatorId,
        address from,
        uint256 amount
    );
    event BondDepositedStETH(
        uint256 indexed nodeOperatorId,
        address from,
        uint256 amount
    );
    event BondDepositedWstETH(
        uint256 indexed nodeOperatorId,
        address from,
        uint256 amount
    );
    event BondClaimedUnstETH(
        uint256 indexed nodeOperatorId,
        address to,
        uint256 amount,
        uint256 requestId
    );
    event BondClaimedStETH(
        uint256 indexed nodeOperatorId,
        address to,
        uint256 amount
    );
    event BondClaimedWstETH(
        uint256 indexed nodeOperatorId,
        address to,
        uint256 amount
    );
    event BondBurned(
        uint256 indexed nodeOperatorId,
        uint256 amountToBurn,
        uint256 burnedAmount
    );
    event BondCharged(
        uint256 indexed nodeOperatorId,
        uint256 toChargeAmount,
        uint256 chargedAmount
    );

    error ZeroLocatorAddress();
    error NothingToClaim();

    function LIDO_LOCATOR() external view returns (ILidoLocator);

    function LIDO() external view returns (ILido);

    function WITHDRAWAL_QUEUE() external view returns (IWithdrawalQueue);

    function WSTETH() external view returns (IWstETH);

    /// @notice Get total bond shares (stETH) stored on the contract
    /// @return Total bond shares (stETH)
    function totalBondShares() external view returns (uint256);

    /// @notice Get bond shares (stETH) for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond in stETH shares
    function getBondShares(
        uint256 nodeOperatorId
    ) external view returns (uint256);

    /// @notice Get bond amount in ETH (stETH) for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond amount in ETH (stETH)
    function getBond(uint256 nodeOperatorId) external view returns (uint256);
}
