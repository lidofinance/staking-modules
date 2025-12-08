// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { AssetRecovererLib } from "../lib/AssetRecovererLib.sol";

/// @title AssetRecoverer
/// @dev Abstract contract providing mechanisms for recovering various asset types (ETH, ERC20, ERC721, ERC1155) from a contract.
///      This contract is designed to allow asset recovery by an authorized address by implementing the onlyRecovererRole guardian
/// @notice Assets can be sent only to the `msg.sender`
abstract contract AssetRecoverer {
    /// @dev Allows sender to recover Ether held by the contract
    /// Emits an EtherRecovered event upon success
    function recoverEther() external {
        _onlyRecoverer();
        AssetRecovererLib.recoverEther();
    }

    /// @dev Allows sender to recover ERC20 tokens held by the contract
    /// @param token The address of the ERC20 token to recover
    /// @param amount The amount of the ERC20 token to recover
    /// Emits an ERC20Recovered event upon success
    /// Optionally, the inheriting contract can override this function to add additional restrictions
    function recoverERC20(address token, uint256 amount) external virtual {
        _onlyRecoverer();
        AssetRecovererLib.recoverERC20(token, amount);
    }

    /// @dev Allows sender to recover ERC721 tokens held by the contract
    /// @param token The address of the ERC721 token to recover
    /// @param tokenId The token ID of the ERC721 token to recover
    /// Emits an ERC721Recovered event upon success
    function recoverERC721(address token, uint256 tokenId) external {
        _onlyRecoverer();
        AssetRecovererLib.recoverERC721(token, tokenId);
    }

    /// @dev Allows sender to recover ERC1155 tokens held by the contract.
    /// @param token The address of the ERC1155 token to recover.
    /// @param tokenId The token ID of the ERC1155 token to recover.
    /// Emits an ERC1155Recovered event upon success.
    function recoverERC1155(address token, uint256 tokenId) external {
        _onlyRecoverer();
        AssetRecovererLib.recoverERC1155(token, tokenId);
    }

    /// @dev Guardian to restrict access to the recover methods.
    ///      Should be implemented by the inheriting contract
    function _onlyRecoverer() internal view virtual;
}
