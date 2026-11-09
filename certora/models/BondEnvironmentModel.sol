// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Executable, non-reentrant environment for the BondCore proof scene.
/// @dev Fixed conversion: 3 pooled-ETH units per 2 shares, with floor rounding.
///      This deliberately exercises rounding; it is NOT a model of all stETH
///      rates or rebases. Transfers are share-exact and never call recipients.
///      Allowance/role checks are omitted: the production dependencies are
///      assumed to authorize BondCore. Public mint is fixture-only and no rule
///      claims invariants under arbitrary calls to model methods.
contract BondTokenModel {
    mapping(address => uint256) public sharesOf;

    function getSharesByPooledEth(uint256 amount) public pure returns (uint256) {
        return Math.mulDiv(amount, 2, 3);
    }

    function getPooledEthByShares(uint256 shares) public pure returns (uint256) {
        return Math.mulDiv(shares, 3, 2);
    }

    function mintShares(address to, uint256 shares) external {
        sharesOf[to] += shares;
    }

    function submit(address) external payable returns (uint256 shares) {
        shares = getSharesByPooledEth(msg.value);
        sharesOf[msg.sender] += shares;
    }

    function transferShares(address to, uint256 shares) external returns (uint256) {
        _transfer(msg.sender, to, shares);
        return getPooledEthByShares(shares);
    }

    function transferSharesFrom(address from, address to, uint256 shares) external returns (uint256) {
        _transfer(from, to, shares);
        return getPooledEthByShares(shares);
    }

    function _transfer(address from, address to, uint256 shares) private {
        require(to != address(0), "zero recipient");
        sharesOf[from] -= shares;
        sharesOf[to] += shares;
    }
}

/// @dev Shares are moved into Burner custody immediately; no rebase is modeled.
contract BondBurnerModel {
    BondTokenModel public immutable TOKEN;

    constructor(BondTokenModel token) {
        TOKEN = token;
    }

    function requestBurnMyShares(uint256 shares) external {
        TOKEN.transferSharesFrom(msg.sender, address(this), shares);
    }
}

/// @dev One wrapped token unit represents one stETH share; wrapping rounds down
///      the stETH input through the same conversion as BondTokenModel.
contract BondWstETHModel {
    BondTokenModel public immutable TOKEN;
    mapping(address => uint256) public balanceOf;

    constructor(BondTokenModel token) {
        TOKEN = token;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _transfer(from, to, amount);
        return true;
    }

    function wrap(uint256 amount) external returns (uint256 shares) {
        shares = TOKEN.getSharesByPooledEth(amount);
        TOKEN.transferSharesFrom(msg.sender, address(this), shares);
        balanceOf[msg.sender] += shares;
    }

    function unwrap(uint256 shares) external returns (uint256) {
        balanceOf[msg.sender] -= shares;
        TOKEN.transferShares(msg.sender, shares);
        return TOKEN.getPooledEthByShares(shares);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "zero recipient");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @dev Only request submission is modeled, for a single amount. Finalization,
///      redemption, bunker mode, and production min/max limits are out of scope.
contract BondWithdrawalQueueModel {
    BondTokenModel public immutable TOKEN;
    address public immutable WSTETH;
    uint256 public nextRequestId;
    address public lastOwner;
    uint256 public lastShares;

    constructor(BondTokenModel token, address wstETH) {
        TOKEN = token;
        WSTETH = wstETH;
    }

    function requestWithdrawals(uint256[] calldata amounts, address owner) external returns (uint256[] memory ids) {
        require(amounts.length == 1, "single request model");
        require(owner != address(0), "zero owner");
        uint256 shares = TOKEN.getSharesByPooledEth(amounts[0]);
        require(shares != 0, "zero shares");
        TOKEN.transferSharesFrom(msg.sender, address(this), shares);
        lastOwner = owner;
        lastShares = shares;
        ids = new uint256[](1);
        ids[0] = ++nextRequestId;
    }
}

/// @dev Constructor adapter only. Proof config explicitly links runtime fields.
contract BondLocatorModel {
    address public immutable lido;
    address public immutable burner;
    address public immutable withdrawalQueue;

    constructor(address token, address burner_, address queue) {
        lido = token;
        burner = burner_;
        withdrawalQueue = queue;
    }
}
