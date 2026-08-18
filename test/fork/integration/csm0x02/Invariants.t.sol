// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { DeployCSM0x02Params } from "script/csm0x02/DeployCSM0x02Base.s.sol";

import { CommunityInvariantsBase } from "../common/InvariantsBase.sol";
import { CSM0x02IntegrationBase } from "../common/ModuleTypeBase.sol";

contract CommunityInvariantsCSM0x02 is CommunityInvariantsBase, CSM0x02IntegrationBase {
    address internal rewindTopUpQueueRoleHolder;

    function setUp() public override {
        super.setUp();

        Env memory env = envVars();
        DeployCSM0x02Params memory params = parseDeployParams0x02(env.DEPLOY_CONFIG);
        rewindTopUpQueueRoleHolder = params.rewindTopUpQueueRoleHolder;
    }

    function test_moduleRoles() public view {
        _checkCommonModuleRoles();

        bytes32 createRole = module.CREATE_NODE_OPERATOR_ROLE();
        assertEq(module.getRoleMemberCount(createRole), 1, "create node operator");
        assertTrue(module.hasRole(createRole, address(permissionlessGate)), "permissionless gate create role");

        bytes32 rewindRole = module.REWIND_TOP_UP_QUEUE_ROLE();
        assertEq(module.getRoleMemberCount(rewindRole), 1, "rewind top-up queue");
        assertTrue(module.hasRole(rewindRole, rewindTopUpQueueRoleHolder), "rewind role address");
    }

    function test_accountingRoles() public view {
        _checkCommonAccountingRoles();

        bytes32 setCurveRole = accounting.SET_BOND_CURVE_ROLE();
        assertEq(accounting.getRoleMemberCount(setCurveRole), 1, "set bond curve");
        assertTrue(accounting.hasRole(setCurveRole, deployParams.setResetBondCurveAddress), "set bond curve address");
    }
}
