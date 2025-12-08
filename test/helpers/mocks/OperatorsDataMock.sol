// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { OperatorInfo } from "../../../src/interfaces/IOperatorsData.sol";

contract OperatorsDataMock {
    function set(
        uint256 moduleId,
        uint256 nodeOperatorId,
        OperatorInfo calldata info
    ) external {}
}
