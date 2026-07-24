// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBaseModule } from "./interfaces/IBaseModule.sol";
import { IERC20LockVault } from "./interfaces/IERC20LockVault.sol";

/// @notice Minimal per-operator vault holding locked ERC20 tokens.
contract ERC20LockVault is IERC20LockVault, Initializable {
    using SafeERC20 for IERC20;

    uint256 private _nodeOperatorId;
    address public immutable TOKEN;
    address public immutable PROVIDER;
    IBaseModule public immutable MODULE;

    constructor(address token, address provider, address module) {
        if (token == address(0) || provider == address(0) || module == address(0)) revert ZeroAddress();

        TOKEN = token;
        PROVIDER = provider;
        MODULE = IBaseModule(module);

        _disableInitializers();
    }

    /// @inheritdoc IERC20LockVault
    function initialize(uint256 nodeOperatorId_) external virtual initializer {
        _nodeOperatorId = nodeOperatorId_;
    }

    /// @inheritdoc IERC20LockVault
    function transferTokens(address receiver, uint256 amount) external {
        _onlyProvider();
        if (receiver == address(0)) revert ZeroAddress();

        IERC20(TOKEN).safeTransfer(receiver, amount);
    }

    /// @inheritdoc IERC20LockVault
    function nodeOperatorId() external view returns (uint256) {
        return _nodeOperatorId;
    }

    function _onlyNodeOperatorOwner() internal view {
        if (msg.sender != MODULE.getNodeOperatorOwner(_nodeOperatorId)) revert SenderIsNotNodeOperatorOwner();
    }

    function _onlyProvider() internal view {
        if (msg.sender != PROVIDER) revert SenderIsNotProvider();
    }
}
