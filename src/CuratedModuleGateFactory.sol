// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { CuratedModuleGate } from "./CuratedModuleGate.sol";
import { OssifiableProxy } from "./lib/proxy/OssifiableProxy.sol";
import { ICuratedModuleGateFactory } from "./interfaces/ICuratedModuleGateFactory.sol";

contract CuratedModuleGateFactory is ICuratedModuleGateFactory {
    address public immutable CURATED_MODULE_GATE_IMPL;

    constructor(address curatedModuleGateImpl) {
        if (curatedModuleGateImpl == address(0)) {
            revert ZeroImplementationAddress();
        }
        CURATED_MODULE_GATE_IMPL = curatedModuleGateImpl;
    }

    /// @inheritdoc ICuratedModuleGateFactory
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance) {
        instance = address(
            new OssifiableProxy({
                implementation_: CURATED_MODULE_GATE_IMPL,
                admin_: admin,
                data_: new bytes(0)
            })
        );

        CuratedModuleGate(instance).initialize(
            curveId,
            treeRoot,
            treeCid,
            admin
        );

        emit CuratedModuleGateCreated(instance);
    }
}
