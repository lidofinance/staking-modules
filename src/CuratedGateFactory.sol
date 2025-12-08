// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { CuratedGate } from "./CuratedGate.sol";
import { OssifiableProxy } from "./lib/proxy/OssifiableProxy.sol";
import { ICuratedGateFactory } from "./interfaces/ICuratedGateFactory.sol";

contract CuratedGateFactory is ICuratedGateFactory {
    address public immutable CURATED_GATE_IMPL;

    constructor(address curatedGateImpl) {
        if (curatedGateImpl == address(0)) {
            revert ZeroImplementationAddress();
        }
        CURATED_GATE_IMPL = curatedGateImpl;
    }

    /// @inheritdoc ICuratedGateFactory
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance) {
        instance = address(
            new OssifiableProxy({
                implementation_: CURATED_GATE_IMPL,
                admin_: admin,
                data_: new bytes(0)
            })
        );

        CuratedGate(instance).initialize(curveId, treeRoot, treeCid, admin);

        emit CuratedGateCreated(instance);
    }
}
