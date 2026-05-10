// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Script } from "forge-std/Script.sol";
import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { DeploymentFixtures } from "test/helpers/Fixtures.sol";
import { OssifiableProxy } from "../../src/lib/proxy/OssifiableProxy.sol";

contract ForkHelpersCommon is Script, DeploymentFixtures {
    function _setUp() internal {
        initializeFromDeployment();
    }

    function _prepareAdmin(address contractAddress) internal returns (address admin) {
        AccessControlEnumerableUpgradeable contractInstance = AccessControlEnumerableUpgradeable(contractAddress);
        admin = payable(contractInstance.getRoleMember(contractInstance.DEFAULT_ADMIN_ROLE(), 0));
        _setBalance(admin);
    }

    function _prepareProxyAdmin(address proxyAddress) internal returns (address admin) {
        OssifiableProxy proxy = OssifiableProxy(payable(proxyAddress));
        admin = payable(proxy.proxy__getAdmin());
        _setBalance(admin);
    }

    function _setBalance(address account) internal {
        _setBalance(account, 100 ether);
    }

    function _setBalance(address account, uint256 expectedBalance) internal {
        if (account.balance < expectedBalance) {
            vm.rpc(
                "anvil_setBalance",
                string.concat('["', vm.toString(account), '", "', vm.toString(bytes32(expectedBalance)), '"]')
            );
            vm.deal(account, expectedBalance);
        }
    }

    function _warp(uint256 ts) internal {
        vm.rpc("evm_setNextBlockTimestamp", string.concat("[", vm.toString(ts), "]"));
        vm.rpc("evm_mine", "[]");
        vm.warp(ts);
    }
}
