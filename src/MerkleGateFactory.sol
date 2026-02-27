// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OssifiableProxy } from "./lib/proxy/OssifiableProxy.sol";
import { IMerkleGate } from "./interfaces/IMerkleGate.sol";
import { IMerkleGateFactory } from "./interfaces/IMerkleGateFactory.sol";

contract MerkleGateFactory is IMerkleGateFactory {
    address public immutable GATE_IMPL;

    constructor(address gateImpl) {
        if (gateImpl == address(0)) revert ZeroImplementationAddress();
        GATE_IMPL = gateImpl;
    }

    /// @inheritdoc IMerkleGateFactory
    function create(
        uint256 curveId,
        bytes32 treeRoot,
        string calldata treeCid,
        address admin
    ) external returns (address instance) {
        instance = address(new OssifiableProxy({ implementation_: GATE_IMPL, data_: "", admin_: admin }));
        IMerkleGate(instance).initialize(curveId, treeRoot, treeCid, admin);

        emit MerkleGateCreated(instance, admin, curveId);
    }
}
