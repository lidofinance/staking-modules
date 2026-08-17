// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CommunityInvariantsBase } from "../common/InvariantsBase.sol";
import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";

contract CommunityInvariantsCSM0x02 is CommunityInvariantsBase, CSM0x02IntegrationBase {
    function test_moduleRoles() public view {
        _checkCommonModuleRoles();

        bytes32 createRole = module.CREATE_NODE_OPERATOR_ROLE();
        assertEq(module.getRoleMemberCount(createRole), 1, "create node operator");

        bytes32 rewindRole = module.REWIND_TOP_UP_QUEUE_ROLE();
        assertEq(module.getRoleMemberCount(rewindRole), 1, "rewind top-up queue");
        assertTrue(module.hasRole(rewindRole, deployParams.setResetBondCurveAddress), "rewind role address");
    }

    function test_accountingRoles() public view {
        _checkCommonAccountingRoles();

        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 1, "set bond curve");
    }
}
