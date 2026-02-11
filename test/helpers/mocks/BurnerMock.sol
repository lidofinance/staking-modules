// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IStETH } from "../../../src/interfaces/IStETH.sol";

contract BurnerMock {
    address public STETH;
    error ZeroBurnAmount();

    constructor(address _stETH) {
        STETH = _stETH;
    }

    function requestBurnMyShares(uint256 _sharesAmountToBurn) external {
        if (_sharesAmountToBurn == 0) revert ZeroBurnAmount();
        IStETH(STETH).transferSharesFrom(msg.sender, address(this), _sharesAmountToBurn);
    }
}
