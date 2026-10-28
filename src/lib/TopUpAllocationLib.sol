// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

library TopUpAllocationLib {
    bytes32 private constant TOP_UP_ALLOCATION_ENABLED_POSITION =
        keccak256("lido.CuratedModule.topUpAllocationEnabled");

    error TopUpAllocationStateUnchanged();

    function setState(uint256 nodeOperatorId, bool enabled) internal {
        mapping(uint256 => bool) storage enabledByOperator = _enabledByOperator();
        if (enabledByOperator[nodeOperatorId] == enabled) revert TopUpAllocationStateUnchanged();
        enabledByOperator[nodeOperatorId] = enabled;
    }

    function isEnabled(uint256 nodeOperatorId) internal view returns (bool) {
        return _enabledByOperator()[nodeOperatorId];
    }

    function _enabledByOperator() private pure returns (mapping(uint256 => bool) storage m) {
        bytes32 position = TOP_UP_ALLOCATION_ENABLED_POSITION;
        assembly ("memory-safe") {
            // Anchor the mapping at the fixed position; entries land at keccak256(abi.encode(id, position)).
            m.slot := position
        }
    }
}
