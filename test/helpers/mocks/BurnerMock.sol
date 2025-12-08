// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;
import { IStETH } from "../../../src/interfaces/IStETH.sol";

contract BurnerMock {
    address public STETH;
    error ZeroBurnAmount();

    constructor(address _stETH) {
        STETH = _stETH;
    }

    function requestBurnShares(
        address _from,
        uint256 _sharesAmountToBurn
    ) external {
        if (_sharesAmountToBurn == 0) revert ZeroBurnAmount();
        IStETH(STETH).transferSharesFrom(
            _from,
            address(this),
            _sharesAmountToBurn
        );
    }
}
