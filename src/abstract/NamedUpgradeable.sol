// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { INamedUpgradeable } from "../interfaces/INamedUpgradeable.sol";

abstract contract NamedUpgradeable is INamedUpgradeable {
    uint256 internal constant MAX_NAME_LENGTH = 256;

    /// @custom:storage-location erc7201:NamedUpgradeable
    struct NamedUpgradeableStorage {
        string name;
    }

    // keccak256(abi.encode(uint256(keccak256("NamedUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NAMED_UPGRADEABLE_STORAGE_LOCATION =
        0xf31ae013a5af13f77f257862ecd68bd4c15a1f200f6be2d419997a40372cfa00;

    /// @inheritdoc INamedUpgradeable
    function name() public view returns (string memory) {
        return _getNamedUpgradeableStorage().name;
    }

    function _setName(string calldata name_) internal {
        if (bytes(name_).length == 0) revert InvalidName();
        if (bytes(name_).length > MAX_NAME_LENGTH) revert InvalidName();

        NamedUpgradeableStorage storage $ = _getNamedUpgradeableStorage();
        if (Strings.equal(name_, $.name)) revert InvalidName();

        $.name = name_;

        emit NameSet(name_);
    }

    function _getNamedUpgradeableStorage() private pure returns (NamedUpgradeableStorage storage $) {
        assembly {
            $.slot := NAMED_UPGRADEABLE_STORAGE_LOCATION
        }
    }
}
