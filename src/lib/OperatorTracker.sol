// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { TransientUintUintMap, TransientUintUintMapLib } from "./TransientUintUintMapLib.sol";

library OperatorTracker {
    // keccak256(abi.encode(uint256(keccak256("OPERATORS_CREATED_IN_TX_MAP_TSLOT")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant OPERATORS_CREATED_IN_TX_MAP_TSLOT =
        0x1b07bc0838fdc4254cbabb5dd0c94d936f872c6758547168d513d8ad1dc3a500;

    function recordCreator(uint256 nodeOperatorId) internal {
        map().set(nodeOperatorId, uint256(uint160(msg.sender)));
    }

    function forgetCreator(uint256 nodeOperatorId) internal {
        map().set(nodeOperatorId, 0);
    }

    function getCreator(uint256 nodeOperatorId) internal view returns (address) {
        return address(uint160(map().get(nodeOperatorId)));
    }

    function map() private pure returns (TransientUintUintMap) {
        return TransientUintUintMapLib.load(OPERATORS_CREATED_IN_TX_MAP_TSLOT);
    }
}
