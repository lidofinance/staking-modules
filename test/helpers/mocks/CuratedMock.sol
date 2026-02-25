// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";

import { CSMMock } from "./CSMMock.sol";

contract CuratedMock is CSMMock {
    IMetaRegistry internal metaRegistry;

    function META_REGISTRY() external view returns (IMetaRegistry) {
        return metaRegistry;
    }

    function mock_setMetaRegistry(address value) external {
        metaRegistry = IMetaRegistry(value);
    }

    function notifyNodeOperatorWeightChange(uint256, uint256, uint256) external {}

    function requestFullDepositInfoUpdate() external {}
}
