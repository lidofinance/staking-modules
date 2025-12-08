// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IExitTypes } from "../interfaces/IExitTypes.sol";

abstract contract ExitTypes is IExitTypes {
    uint8 public constant VOLUNTARY_EXIT_TYPE_ID = 0;
    uint8 public constant STRIKES_EXIT_TYPE_ID = 1;
}
