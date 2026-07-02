// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";

/// @notice Minimal per-operator vault holding locked ERC20 tokens.
contract ERC20LockVault is IERC20LockVault {
    using SafeERC20 for IERC20;

    uint256 public immutable NODE_OPERATOR_ID;
    address public immutable TOKEN;
    address public immutable PROVIDER;
    IBaseModule public immutable MODULE;

    constructor(uint256 nodeOperatorId, address token, address provider, address module) {
        if (token == address(0) || provider == address(0) || module == address(0)) revert ZeroAddress();

        NODE_OPERATOR_ID = nodeOperatorId;
        TOKEN = token;
        PROVIDER = provider;
        MODULE = IBaseModule(module);
    }

    /// @inheritdoc IERC20LockVault
    function transferTokens(address receiver, uint256 amount) external {
        _onlyProvider();
        if (receiver == address(0)) revert ZeroAddress();

        IERC20(TOKEN).safeTransfer(receiver, amount);
    }

    function _onlyNodeOperatorOwner() internal view {
        if (msg.sender != MODULE.getNodeOperatorOwner(NODE_OPERATOR_ID)) revert SenderIsNotNodeOperatorOwner();
    }

    function _onlyProvider() internal view {
        if (msg.sender != PROVIDER) revert SenderIsNotProvider();
    }
}
