// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";

contract PermissionlessCreateNodeOperator0x02Test is CSM0x02IntegrationBase {
    function setUp() public {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();
    }

    function test_createNodeOperatorETH_setsCurveAndBond() public {
        uint256 keysCount = 2;
        (bytes memory keys, bytes memory signatures) = keysSignatures(keysCount);

        uint256 amount = accounting.getBondAmountByKeysCount(keysCount, permissionlessGate.CURVE_ID());

        address nodeOperator = nextAddress("NodeOperator");
        vm.deal(nodeOperator, amount);

        uint256 preTotalShares = accounting.totalBondShares();
        uint256 shares = lido.getSharesByPooledEth(amount);

        vm.prank(nodeOperator);
        uint256 noId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });

        assertEq(accounting.getBondCurveId(noId), permissionlessGate.CURVE_ID(), "bond curve mismatch");
        assertEq(accounting.getBondShares(noId), shares, "bond shares mismatch");
        assertEq(accounting.totalBondShares(), preTotalShares + shares, "total bond shares mismatch");
    }
}
