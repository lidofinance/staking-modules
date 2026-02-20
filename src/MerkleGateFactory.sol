// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { OssifiableProxy } from "./lib/proxy/OssifiableProxy.sol";
import { IMerkleGateFactory } from "./interfaces/IMerkleGateFactory.sol";

contract MerkleGateFactory is IMerkleGateFactory {
    address public immutable GATE_IMPL;

    constructor(address gateImpl) {
        if (gateImpl == address(0)) revert ZeroImplementationAddress();
        GATE_IMPL = gateImpl;
    }

    /// @inheritdoc IMerkleGateFactory
    function create(bytes calldata initCalldata, address admin) external returns (address instance) {
        instance = address(new OssifiableProxy({ implementation_: GATE_IMPL, data_: initCalldata, admin_: admin }));

        emit MerkleGateCreated(instance, GATE_IMPL, admin);
    }
}
