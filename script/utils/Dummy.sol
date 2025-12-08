// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

contract Dummy {
    error ImDummy();

    receive() external payable {
        revert ImDummy();
    }
}
