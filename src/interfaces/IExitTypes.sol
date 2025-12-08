// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

interface IExitTypes {
    function VOLUNTARY_EXIT_TYPE_ID() external view returns (uint8);

    function STRIKES_EXIT_TYPE_ID() external view returns (uint8);
}
