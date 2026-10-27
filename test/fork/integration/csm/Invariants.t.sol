// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CommunityInvariantsBase } from "../common/InvariantsBase.sol";
import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract CommunityInvariantsCSM is CommunityInvariantsBase, CSMIntegrationBase {
    function test_moduleRoles() public view {
        _checkCommonModuleRoles();

        bytes32 createRole = module.CREATE_NODE_OPERATOR_ROLE();
        assertEq(module.getRoleMemberCount(createRole), 3, "create node operator");
        assertTrue(module.hasRole(createRole, address(permissionlessGate)), "permissionless gate create role");
        assertTrue(module.hasRole(createRole, address(vettedGate)), "vetted gate create role");
        assertTrue(module.hasRole(createRole, address(identifiedDVTClusterGate)), "IDVTC gate create role");
    }

    function test_accountingRoles() public view {
        _checkCommonAccountingRoles();

        bytes32 setCurveRole = accounting.SET_BOND_CURVE_ROLE();
        assertEq(accounting.getRoleMemberCount(setCurveRole), 3, "set bond curve");
        assertTrue(accounting.hasRole(setCurveRole, deployParams.setResetBondCurveAddress), "set bond curve address");
        assertTrue(accounting.hasRole(setCurveRole, address(vettedGate)), "vetted gate set curve role");
        assertTrue(accounting.hasRole(setCurveRole, address(identifiedDVTClusterGate)), "IDVTC gate set curve role");
    }
}
