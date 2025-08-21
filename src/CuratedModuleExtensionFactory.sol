// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { CuratedModuleExtension } from "./CuratedModuleExtension.sol";
import { OssifiableProxy } from "./lib/proxy/OssifiableProxy.sol";
import { ICuratedModuleExtensionFactory } from "./interfaces/ICuratedModuleExtensionFactory.sol";

contract CuratedModuleExtensionFactory is ICuratedModuleExtensionFactory {
    address public immutable CURATED_MODULE_EXTENSION_IMPL;

    constructor(address curatedModuleExtensionImpl) {
        if (curatedModuleExtensionImpl == address(0)) {
            revert ZeroImplementationAddress();
        }
        CURATED_MODULE_EXTENSION_IMPL = curatedModuleExtensionImpl;
    }

    /// @inheritdoc ICuratedModuleExtensionFactory
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance) {
        instance = address(
            new OssifiableProxy({
                implementation_: CURATED_MODULE_EXTENSION_IMPL,
                admin_: admin,
                data_: new bytes(0)
            })
        );

        CuratedModuleExtension(instance).initialize(
            curveId,
            treeRoot,
            treeCid,
            admin
        );

        emit CuratedModuleExtensionCreated(instance);
    }
}
