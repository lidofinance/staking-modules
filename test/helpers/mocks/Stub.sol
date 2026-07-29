// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

contract Stub {
    error NotImplemented();

    receive() external payable {}

    fallback() external payable {
        revert NotImplemented();
    }
}
