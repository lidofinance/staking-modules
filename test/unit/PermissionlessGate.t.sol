// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { PermissionlessGate } from "src/PermissionlessGate.sol";
import { IPermissionlessGate } from "src/interfaces/IPermissionlessGate.sol";
import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { Utilities } from "../helpers/Utilities.sol";

contract PermissionlessGateTest is Test, Utilities {
    PermissionlessGate public gate;
    CSMMock public csm;

    constructor() {
        csm = new CSMMock();
        gate = new PermissionlessGate(address(csm), address(this));
    }

    function test_constructor() public view {
        assertEq(gate.CURVE_ID(), csm.ACCOUNTING().DEFAULT_BOND_CURVE_ID());
        assertEq(address(gate.MODULE()), address(csm));
    }

    function test_constructor_revertWhen_zeroModuleAddress() public {
        vm.expectRevert(IPermissionlessGate.ZeroModuleAddress.selector);
        new PermissionlessGate(address(0), address(this));
    }

    function test_constructor_revertWhen_zeroAdminAddress() public {
        vm.expectRevert(IPermissionlessGate.ZeroAdminAddress.selector);
        new PermissionlessGate(address(csm), address(0));
    }

    function test_recovererRole() public {
        bytes32 role = gate.RECOVERER_ROLE();
        gate.grantRole(role, address(1337));

        vm.prank(address(1337));
        gate.recoverEther();
    }

    function test_addNodeOperatorETH() public {
        uint256 keysCount = 1;

        gate.addNodeOperatorETH({
            keysCount: keysCount,
            publicKeys: randomBytes(48 * keysCount),
            signatures: randomBytes(96 * keysCount),
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
    }

    function test_addNodeOperatorStETH() public {
        uint256 keysCount = 1;
        gate.addNodeOperatorStETH(
            keysCount,
            randomBytes(48 * keysCount),
            randomBytes(96 * keysCount),
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            address(0)
        );
    }

    function test_addNodeOperatorWstETH() public {
        uint256 keysCount = 1;
        gate.addNodeOperatorWstETH(
            keysCount,
            randomBytes(48 * keysCount),
            randomBytes(96 * keysCount),
            NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            IAccounting.PermitInput({
                value: 0,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            }),
            address(0)
        );
    }
}
