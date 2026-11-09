// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { BondCore } from "../../src/abstract/BondCore.sol";

/// @notice Exposes the production BondCore internals for conditional verification.
/// @dev This is not Accounting: authorization, required bond, lock protection and
///      fee splits are outside this harness. `credit` assumes funds have already
///      arrived; `debit` assumes the caller has checked the available shares.
contract BondCoreHarness is BondCore {
    constructor(address locator) BondCore(locator) {}

    function credit(uint256 id, uint256 shares) external {
        _creditBondShares(id, shares);
    }

    function debit(uint256 id, uint256 shares) external {
        _unsafeReduceBond(id, shares);
    }

    function depositETH(address from, uint256 id) external payable {
        _depositETH(from, id);
    }

    function depositStETH(address from, uint256 id, uint256 amount) external {
        _depositStETH(from, id, amount);
    }

    function depositWstETH(address from, uint256 id, uint256 amount) external {
        _depositWstETH(from, id, amount);
    }

    function burn(uint256 id, uint256 amount) external returns (uint256) {
        return _burn(id, amount);
    }

    function charge(uint256 id, uint256 amount, address to) external returns (bool) {
        return _charge(id, amount, to);
    }

    function claimStETH(uint256 id, uint256 amount, uint256 claimable, address to) external returns (uint256) {
        return _claimStETH(id, amount, claimable, to);
    }

    function claimWstETH(uint256 id, uint256 amount, uint256 claimable, address to) external returns (uint256) {
        return _claimWstETH(id, amount, claimable, to);
    }

    function claimUnstETH(uint256 id, uint256 amount, uint256 claimable, address to) external returns (uint256) {
        return _claimUnstETH(id, amount, claimable, to);
    }

    function tokenShares(address who) external view returns (uint256) {
        return LIDO.sharesOf(who);
    }

    function sharesByEth(uint256 amount) external view returns (uint256) {
        return _sharesByEth(amount);
    }

    function ethByShares(uint256 shares) external view returns (uint256) {
        return _ethByShares(shares);
    }
}
