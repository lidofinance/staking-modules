// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IMetaOperatorRegistry } from "src/interfaces/IMetaOperatorRegistry.sol";

import { CSMMock } from "./CSMMock.sol";

contract CuratedMock is CSMMock {
    IMetaOperatorRegistry internal metaOperatorRegistry;

    function META_OPERATOR_REGISTRY()
        external
        view
        returns (IMetaOperatorRegistry)
    {
        return metaOperatorRegistry;
    }

    function mock_setMetaOperatorRegistry(address value) external {
        metaOperatorRegistry = IMetaOperatorRegistry(value);
    }
}
