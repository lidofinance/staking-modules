// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Script } from "forge-std/Script.sol";

import { IAccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

import { DeploymentFixtures } from "test/helpers/Fixtures.sol";
import { ForkHelpersCommon } from "./Common.sol";
import { Utilities } from "../../test/helpers/Utilities.sol";

contract Roles is Script, DeploymentFixtures, ForkHelpersCommon, Utilities {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function grantRole(
        bytes32 role,
        IAccessControlEnumerable where,
        address who
    ) external {
        address admin = where.getRoleMember(DEFAULT_ADMIN_ROLE, 0);
        vm.startBroadcast(admin);
        where.grantRole(role, who);
        vm.stopBroadcast();
    }
}
