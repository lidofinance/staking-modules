// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

/// @notice Exact-share model for FeeDistributor's stETH dependency.
/// @dev Models only sharesOf and transferShares. It assumes successful transfers move
///      exactly the requested shares and do not call back. It does not model stETH
///      rebases, pooled-ETH conversion, allowances, upgrades, or a malicious token.
contract FeeTokenModel {
    mapping(address => uint256) private _shares;

    /// @notice Returns the modeled share balance.
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    /// @notice Transfers exact shares; self-transfers preserve the balance.
    /// @dev Returning shares as pooled ETH is immaterial: FeeDistributor ignores it.
    function transferShares(address to, uint256 shares) external returns (uint256) {
        _transfer(to, shares);
        return shares;
    }

    /// @notice Supports the ERC-20 recovery path when checking guard mutations.
    /// @dev The same 1:1 return convention is used solely for this share model.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(to, amount);
        return true;
    }

    function _transfer(address to, uint256 shares) private {
        require(to != address(0) && to != address(this), "invalid share recipient");
        _shares[msg.sender] -= shares;
        _shares[to] += shares;
    }

    /// @notice Supplies shares in executable model tests; not a production method.
    function mintShares(address to, uint256 shares) external {
        _shares[to] += shares;
    }
}
