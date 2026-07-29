// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

library ProxySlotUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getImplementation(address proxyAddress) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxyAddress, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function getAdmin(address proxyAddress) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxyAddress, ERC1967Utils.ADMIN_SLOT))));
    }
}
