// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ModuleTypeBase } from "./ModuleTypeBase.sol";

abstract contract CommunityInvariantsBase is ModuleTypeBase {
    uint256 internal adminsCount;
    CommonDeployParams internal deployParams;

    function setUp() public virtual {
        Env memory env = envVars();
        _setUpModule();
        deployParams = parseCommonDeployParams(vm.readFile(env.DEPLOY_CONFIG));
        adminsCount = block.chainid == 1 ? 1 : 2;
    }

    function test_moduleKeys() public noGasMetering {
        assertModuleKeys(module);
    }

    function test_moduleEnqueuedCount() public noGasMetering {
        _assertModuleEnqueuedCount();
    }

    function _checkCommonModuleRoles() internal view {
        assertEq(module.getRoleMemberCount(module.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(module.hasRole(module.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "default admin address");

        _checkPauseRole(address(module), deployParams.resealManager, address(circuitBreaker));

        assertEq(module.getRoleMemberCount(module.RESUME_ROLE()), 1, "resume");
        assertTrue(module.hasRole(module.RESUME_ROLE(), deployParams.resealManager), "resume address");

        assertEq(module.getRoleMemberCount(module.STAKING_ROUTER_ROLE()), 1, "staking router");
        assertTrue(
            module.hasRole(module.STAKING_ROUTER_ROLE(), address(locator.stakingRouter())),
            "staking router address"
        );

        assertEq(
            module.getRoleMemberCount(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE()),
            1,
            "report general delayed penalty"
        );
        assertTrue(
            module.hasRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.generalDelayedPenaltyReporter),
            "report general delayed penalty address"
        );

        assertEq(
            module.getRoleMemberCount(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE()),
            1,
            "settle general delayed penalty"
        );
        assertTrue(
            module.hasRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), deployParams.easyTrackEVMScriptExecutor),
            "settle general delayed penalty address"
        );

        assertEq(module.getRoleMemberCount(module.VERIFIER_ROLE()), 1, "verifier");
        assertEq(module.getRoleMember(module.VERIFIER_ROLE(), 0), address(verifier), "verifier address");

        bytes32 createRole = module.CREATE_NODE_OPERATOR_ROLE();
        assertTrue(module.hasRole(createRole, address(permissionlessGate)), "permissionless gate create role");

        assertEq(module.getRoleMemberCount(module.RECOVERER_ROLE()), 0, "recoverer");
    }

    function test_accountingShares() public noGasMetering {
        uint256 noCount = module.getNodeOperatorsCount();
        assertAccountingTotalBondShares(noCount, lido, accounting);
    }

    function test_accountingBurnerApproval() public {
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
    }

    function test_accountingUnusedStorageSlots() public noGasMetering {
        assertAccountingUnusedStorageSlots(accounting);
    }

    function _checkCommonAccountingRoles() internal view {
        assertEq(accounting.getRoleMemberCount(accounting.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(
            accounting.hasRole(accounting.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent),
            "default admin address"
        );

        _checkPauseRole(address(accounting), deployParams.resealManager, address(circuitBreaker));

        assertEq(accounting.getRoleMemberCount(accounting.RESUME_ROLE()), 1, "resume");
        assertTrue(accounting.hasRole(accounting.RESUME_ROLE(), deployParams.resealManager), "resume address");

        assertEq(accounting.getRoleMemberCount(accounting.MANAGE_BOND_CURVES_ROLE()), 0, "manage bond curves");

        bytes32 setCurveRole = accounting.SET_BOND_CURVE_ROLE();
        assertTrue(accounting.hasRole(setCurveRole, deployParams.setResetBondCurveAddress), "set bond curve address");

        assertEq(accounting.getRoleMemberCount(accounting.RECOVERER_ROLE()), 0, "recoverer");
    }

    function test_feeDistributorClaimableShares() public {
        assertFeeDistributorClaimableShares(lido, feeDistributor);
    }

    function test_feeDistributorTree() public {
        assertFeeDistributorTree(feeDistributor);
    }

    function test_feeDistributorRoles() public view {
        assertEq(feeDistributor.getRoleMemberCount(feeDistributor.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(
            feeDistributor.hasRole(feeDistributor.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent),
            "default admin address"
        );
        assertEq(feeDistributor.getRoleMemberCount(feeDistributor.RECOVERER_ROLE()), 0, "recoverer");
    }

    function test_feeOracleUnusedStorageSlots() public noGasMetering {
        assertFeeOracleUnusedStorageSlots(oracle);
    }

    function test_feeOracleRoles() public view {
        assertEq(oracle.getRoleMemberCount(oracle.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "default admin address");
        assertEq(oracle.getRoleMemberCount(oracle.SUBMIT_DATA_ROLE()), 0, "submit data");

        _checkPauseRole(address(oracle), deployParams.resealManager, address(circuitBreaker));

        assertEq(oracle.getRoleMemberCount(oracle.RESUME_ROLE()), 1, "resume");
        assertTrue(oracle.hasRole(oracle.RESUME_ROLE(), deployParams.resealManager), "resume address");
        assertEq(oracle.getRoleMemberCount(oracle.RECOVERER_ROLE()), 0, "recoverer");
        assertEq(oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_CONTRACT_ROLE()), 0, "manage consensus contract");
        assertEq(oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_VERSION_ROLE()), 0, "manage consensus version");
    }

    function test_hashConsensusRoles() public view {
        assertEq(hashConsensus.getRoleMemberCount(hashConsensus.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(
            hashConsensus.hasRole(hashConsensus.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent),
            "default admin address"
        );
    }

    function test_verifierRoles() public view {
        assertEq(verifier.getRoleMemberCount(verifier.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(verifier.hasRole(verifier.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "default admin address");

        _checkPauseRole(address(verifier), deployParams.resealManager, address(circuitBreaker));

        assertEq(verifier.getRoleMemberCount(verifier.RESUME_ROLE()), 1, "resume");
        assertTrue(verifier.hasRole(verifier.RESUME_ROLE(), deployParams.resealManager), "resume address");
    }

    function test_ejectorRoles() public view {
        assertEq(ejector.getRoleMemberCount(ejector.DEFAULT_ADMIN_ROLE()), adminsCount, "default admin");
        assertTrue(ejector.hasRole(ejector.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "default admin address");

        _checkPauseRole(address(ejector), deployParams.resealManager, address(circuitBreaker));

        assertEq(ejector.getRoleMemberCount(ejector.RESUME_ROLE()), 1, "resume");
        assertTrue(ejector.hasRole(ejector.RESUME_ROLE(), deployParams.resealManager), "resume address");
        assertEq(ejector.getRoleMemberCount(ejector.RECOVERER_ROLE()), 0, "recoverer");
    }
}
