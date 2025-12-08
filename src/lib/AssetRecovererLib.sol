// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ILido } from "../interfaces/ILido.sol";

interface IAssetRecovererLib {
    event EtherRecovered(address indexed recipient, uint256 amount);
    event ERC20Recovered(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event StETHSharesRecovered(address indexed recipient, uint256 shares);
    event ERC721Recovered(
        address indexed token,
        uint256 tokenId,
        address indexed recipient
    );
    event ERC1155Recovered(
        address indexed token,
        uint256 tokenId,
        address indexed recipient,
        uint256 amount
    );

    error FailedToSendEther();
    error NotAllowedToRecover();
}

/*
 * @title AssetRecovererLib
 * @dev Library providing mechanisms for recovering various asset types (ETH, ERC20, ERC721, ERC1155).
 * This library is designed to be used by a contract that implements the AssetRecoverer interface.
 */
library AssetRecovererLib {
    using SafeERC20 for IERC20;

    /**
     * @dev Allows the sender to recover Ether held by the contract.
     * Emits an EtherRecovered event upon success.
     */
    function recoverEther() external {
        uint256 amount = address(this).balance;
        (bool success, ) = msg.sender.call{ value: amount }("");
        if (!success) {
            revert IAssetRecovererLib.FailedToSendEther();
        }

        emit IAssetRecovererLib.EtherRecovered(msg.sender, amount);
    }

    /**
     * @dev Allows the sender to recover ERC20 tokens held by the contract.
     * @param token The address of the ERC20 token to recover.
     * @param amount The amount of the ERC20 token to recover.
     * Emits an ERC20Recovered event upon success.
     */
    function recoverERC20(address token, uint256 amount) external {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit IAssetRecovererLib.ERC20Recovered(token, msg.sender, amount);
    }

    /**
     * @dev Allows the sender to recover stETH shares held by the contract.
     * The use of a separate method for stETH is to avoid rounding problems when converting shares to stETH.
     * @param lido The address of the Lido contract.
     * @param shares The amount of stETH shares to recover.
     * Emits an StETHSharesRecovered event upon success.
     */
    function recoverStETHShares(address lido, uint256 shares) external {
        ILido(lido).transferShares(msg.sender, shares);
        emit IAssetRecovererLib.StETHSharesRecovered(msg.sender, shares);
    }

    /**
     * @dev Allows the sender to recover ERC721 tokens held by the contract.
     * @param token The address of the ERC721 token to recover.
     * @param tokenId The token ID of the ERC721 token to recover.
     * Emits an ERC721Recovered event upon success.
     */
    function recoverERC721(address token, uint256 tokenId) external {
        IERC721(token).safeTransferFrom(address(this), msg.sender, tokenId);
        emit IAssetRecovererLib.ERC721Recovered(token, tokenId, msg.sender);
    }

    /**
     * @dev Allows the sender to recover ERC1155 tokens held by the contract.
     * @param token The address of the ERC1155 token to recover.
     * @param tokenId The token ID of the ERC1155 token to recover.
     * Emits an ERC1155Recovered event upon success.
     */
    function recoverERC1155(address token, uint256 tokenId) external {
        uint256 amount = IERC1155(token).balanceOf(address(this), tokenId);
        IERC1155(token).safeTransferFrom({
            from: address(this),
            to: msg.sender,
            id: tokenId,
            value: amount,
            data: ""
        });
        emit IAssetRecovererLib.ERC1155Recovered(
            token,
            tokenId,
            msg.sender,
            amount
        );
    }
}
