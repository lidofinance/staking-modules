// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { Utilities } from "../../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../../helpers/Fixtures.sol";
import { NodeOperator } from "../../../../src/interfaces/ICSModule.sol";
import { QueueLib, Batch } from "../../../../src/lib/QueueLib.sol";
import { InvariantAsserts } from "../../../helpers/InvariantAsserts.sol";
import { DeployParams } from "../../../../script/DeployBase.s.sol";

contract InvariantsBase is
    Test,
    Utilities,
    DeploymentFixtures,
    InvariantAsserts
{
    uint256 adminsCount;
    DeployParams internal deployParams;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        deployParams = parseDeployParams(env.DEPLOY_CONFIG);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

using QueueLib for QueueLib.Queue;

contract CSModuleInvariants is InvariantsBase {
    function test_keys() public noGasMetering {
        assertModuleKeys(csm);
    }

    function test_enqueuedCount() public noGasMetering {
        assertModuleEnqueuedCount(csm);
    }

    function test_unusedStorageSlots() public noGasMetering {
        assertModuleUnusedStorageSlots(csm);
    }

    function test_roles() public view {
        assertEq(
            csm.getRoleMemberCount(csm.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            csm.hasRole(csm.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent),
            "default admin address"
        );

        assertEq(csm.getRoleMemberCount(csm.PAUSE_ROLE()), 2, "pause");
        assertTrue(
            csm.hasRole(csm.PAUSE_ROLE(), address(gateSeal)),
            "pause address"
        );
        assertTrue(
            csm.hasRole(csm.PAUSE_ROLE(), deployParams.resealManager),
            "pause address"
        );

        assertEq(csm.getRoleMemberCount(csm.RESUME_ROLE()), 1, "resume");
        assertTrue(
            csm.hasRole(csm.RESUME_ROLE(), deployParams.resealManager),
            "resume address"
        );

        assertEq(
            csm.getRoleMemberCount(csm.STAKING_ROUTER_ROLE()),
            1,
            "staking router"
        );
        assertTrue(
            csm.hasRole(
                csm.STAKING_ROUTER_ROLE(),
                address(locator.stakingRouter())
            ),
            "staking router address"
        );

        assertEq(
            csm.getRoleMemberCount(csm.REPORT_GENERAL_DELAYED_PENALTY_ROLE()),
            1,
            "report general delayed penalty"
        );
        assertTrue(
            csm.hasRole(
                csm.REPORT_GENERAL_DELAYED_PENALTY_ROLE(),
                deployParams.generalDelayedPenaltyReporter
            ),
            "report general delayed penalty address"
        );

        assertEq(
            csm.getRoleMemberCount(csm.SETTLE_GENERAL_DELAYED_PENALTY_ROLE()),
            1,
            "settle general delayed penalty"
        );
        assertTrue(
            csm.hasRole(
                csm.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(),
                deployParams.easyTrackEVMScriptExecutor
            ),
            "settle general delayed penalty address"
        );

        assertEq(csm.getRoleMemberCount(csm.VERIFIER_ROLE()), 1, "verifier");
        assertEq(
            csm.getRoleMember(csm.VERIFIER_ROLE(), 0),
            address(verifier),
            "verifier address"
        );

        assertEq(
            csm.getRoleMemberCount(csm.CREATE_NODE_OPERATOR_ROLE()),
            2,
            "create node operator"
        );
        assertTrue(
            csm.hasRole(
                csm.CREATE_NODE_OPERATOR_ROLE(),
                address(permissionlessGate)
            ),
            "create node operator address"
        );
        assertTrue(
            csm.hasRole(csm.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate)),
            "create node operator address"
        );

        assertEq(csm.getRoleMemberCount(csm.RECOVERER_ROLE()), 0, "recoverer");
    }
}

contract CSAccountingInvariants is InvariantsBase {
    function test_sharesAccounting() public noGasMetering {
        uint256 noCount = csm.getNodeOperatorsCount();
        assertAccountingTotalBondShares(noCount, lido, accounting);
    }

    function test_burnerApproval() public {
        assertAccountingBurnerApproval(
            lido,
            address(accounting),
            locator.burner()
        );
    }

    function test_unusedStorageSlots() public noGasMetering {
        assertAccountingUnusedStorageSlots(accounting);
    }

    function test_roles() public view {
        assertEq(
            accounting.getRoleMemberCount(accounting.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            accounting.hasRole(
                accounting.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );

        assertEq(
            accounting.getRoleMemberCount(accounting.PAUSE_ROLE()),
            2,
            "pause"
        );
        assertTrue(
            accounting.hasRole(accounting.PAUSE_ROLE(), address(gateSeal)),
            "pause address"
        );
        assertTrue(
            accounting.hasRole(
                accounting.PAUSE_ROLE(),
                deployParams.resealManager
            ),
            "pause address"
        );

        assertEq(
            accounting.getRoleMemberCount(accounting.RESUME_ROLE()),
            1,
            "resume"
        );
        assertTrue(
            accounting.hasRole(
                accounting.RESUME_ROLE(),
                deployParams.resealManager
            ),
            "resume address"
        );

        assertEq(
            accounting.getRoleMemberCount(accounting.MANAGE_BOND_CURVES_ROLE()),
            0,
            "manage bond curves"
        );
        assertEq(
            accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()),
            2,
            "set bond curve"
        );
        assertTrue(
            accounting.hasRole(
                accounting.SET_BOND_CURVE_ROLE(),
                deployParams.setResetBondCurveAddress
            ),
            "set bond curve address"
        );
        assertTrue(
            accounting.hasRole(
                accounting.SET_BOND_CURVE_ROLE(),
                address(vettedGate)
            ),
            "set bond curve address"
        );

        assertEq(
            accounting.getRoleMemberCount(accounting.RECOVERER_ROLE()),
            0,
            "recoverer"
        );
    }
}

contract CSFeeDistributorInvariants is InvariantsBase {
    function test_claimableShares() public {
        assertFeeDistributorClaimableShares(lido, feeDistributor);
    }

    function test_tree() public {
        assertFeeDistributorTree(feeDistributor);
    }

    function test_roles() public view {
        assertEq(
            feeDistributor.getRoleMemberCount(
                feeDistributor.DEFAULT_ADMIN_ROLE()
            ),
            adminsCount,
            "default admin"
        );
        assertTrue(
            feeDistributor.hasRole(
                feeDistributor.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );
        assertEq(
            feeDistributor.getRoleMemberCount(feeDistributor.RECOVERER_ROLE()),
            0,
            "recoverer"
        );
    }
}

contract CSFeeOracleInvariant is InvariantsBase {
    function test_unusedStorageSlots() public noGasMetering {
        assertFeeOracleUnusedStorageSlots(oracle);
    }

    function test_roles() public view {
        assertEq(
            oracle.getRoleMemberCount(oracle.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            oracle.hasRole(
                oracle.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );

        assertEq(
            oracle.getRoleMemberCount(oracle.SUBMIT_DATA_ROLE()),
            0,
            "submit data"
        );

        assertEq(oracle.getRoleMemberCount(oracle.PAUSE_ROLE()), 2, "pause");
        assertTrue(
            oracle.hasRole(oracle.PAUSE_ROLE(), address(gateSeal)),
            "pause address"
        );
        assertTrue(
            oracle.hasRole(oracle.PAUSE_ROLE(), deployParams.resealManager),
            "pause address"
        );

        assertEq(oracle.getRoleMemberCount(oracle.RESUME_ROLE()), 1, "resume");
        assertTrue(
            oracle.hasRole(oracle.RESUME_ROLE(), deployParams.resealManager),
            "resume address"
        );

        assertEq(
            oracle.getRoleMemberCount(oracle.RECOVERER_ROLE()),
            0,
            "recoverer"
        );
        assertEq(
            oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_CONTRACT_ROLE()),
            0,
            "manage_consensus_contract"
        );
        assertEq(
            oracle.getRoleMemberCount(oracle.MANAGE_CONSENSUS_VERSION_ROLE()),
            0,
            "manage_consensus_version"
        );
    }
}

contract HashConsensusInvariant is InvariantsBase {
    function test_roles() public view {
        assertEq(
            oracle.getRoleMemberCount(oracle.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            oracle.hasRole(
                oracle.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );
    }
}

contract VerifierInvariant is InvariantsBase {
    function test_roles() public view {
        assertEq(
            verifier.getRoleMemberCount(verifier.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            verifier.hasRole(
                verifier.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );

        assertEq(
            verifier.getRoleMemberCount(verifier.PAUSE_ROLE()),
            2,
            "pause"
        );
        assertTrue(
            verifier.hasRole(verifier.PAUSE_ROLE(), address(gateSeal)),
            "pause address"
        );
        assertTrue(
            verifier.hasRole(verifier.PAUSE_ROLE(), deployParams.resealManager),
            "pause address"
        );

        assertEq(
            verifier.getRoleMemberCount(verifier.RESUME_ROLE()),
            1,
            "resume"
        );
        assertTrue(
            verifier.hasRole(
                verifier.RESUME_ROLE(),
                deployParams.resealManager
            ),
            "resume address"
        );
    }
}

contract EjectorInvariant is InvariantsBase {
    function test_roles() public view {
        assertEq(
            ejector.getRoleMemberCount(ejector.DEFAULT_ADMIN_ROLE()),
            adminsCount,
            "default admin"
        );
        assertTrue(
            ejector.hasRole(
                ejector.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            ),
            "default admin address"
        );

        assertEq(verifier.getRoleMemberCount(ejector.PAUSE_ROLE()), 2, "pause");
        assertTrue(
            ejector.hasRole(ejector.PAUSE_ROLE(), address(gateSeal)),
            "pause address"
        );
        assertTrue(
            ejector.hasRole(ejector.PAUSE_ROLE(), deployParams.resealManager),
            "pause address"
        );

        assertEq(
            ejector.getRoleMemberCount(ejector.RESUME_ROLE()),
            1,
            "resume"
        );
        assertTrue(
            ejector.hasRole(ejector.RESUME_ROLE(), deployParams.resealManager),
            "resume address"
        );

        assertEq(
            ejector.getRoleMemberCount(ejector.RECOVERER_ROLE()),
            0,
            "recoverer"
        );
    }
}
