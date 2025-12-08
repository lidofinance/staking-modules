// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { CuratedGate } from "../../../src/CuratedGate.sol";
import { OssifiableProxy } from "../../../src/lib/proxy/OssifiableProxy.sol";
import { CuratedDeployParams, CuratedGateConfig } from "../../../script/curated/DeployBase.s.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    CuratedDeployParams internal deployParams;
    CuratedGateConfig[] internal deployGateConfigs;
    uint256 adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) {
            vm.skip(true);
        }
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        // mutates storage variable
        updateCuratedDeployParams(deployParams, env.DEPLOY_CONFIG);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        uint256 gatesCount = curatedGates.length;
        assertEq(module.getRoleMemberCount(role), gatesCount);

        for (uint256 i = 0; i < gatesCount; ++i) {
            assertTrue(
                module.hasRole(role, curatedGates[i]),
                "gate missing module role"
            );
        }
    }
}

contract OperatorsDataDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        assertEq(
            operatorsData.getRoleMemberCount(
                operatorsData.DEFAULT_ADMIN_ROLE()
            ),
            adminsCount
        );
        assertTrue(
            operatorsData.hasRole(
                operatorsData.DEFAULT_ADMIN_ROLE(),
                deployParams.aragonAgent
            )
        );

        bytes32 setterRole = operatorsData.SETTER_ROLE();
        uint256 gatesCount = curatedGates.length;
        assertEq(operatorsData.getRoleMemberCount(setterRole), gatesCount);
        for (uint256 i = 0; i < gatesCount; ++i) {
            assertTrue(
                operatorsData.hasRole(setterRole, curatedGates[i]),
                "gate missing operatorsData setter role"
            );
        }
    }
}

contract CuratedGatesDeploymentTest is DeploymentBaseTest {
    function test_immutables() public view {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates deployed");

        for (uint256 i = 0; i < gatesCount; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);

            assertEq(address(gate.MODULE()), address(module));
            assertEq(address(gate.ACCOUNTING()), address(accounting));
            assertEq(address(gate.OPERATORS_DATA()), address(operatorsData));
            assertEq(gate.MODULE_ID(), deployParams.stakingModuleId);
        }
    }

    function test_state() public view {
        uint256 gatesCount = curatedGates.length;
        for (uint256 i = 0; i < gatesCount; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            assertEq(gate.getInitializedVersion(), 1);
            assertFalse(gate.isPaused());

            assertEq(gate.treeRoot(), deployParams.curatedGates[i].treeRoot);
            assertEq(gate.treeCid(), deployParams.curatedGates[i].treeCid);
            // TODO bad assert. needs to be fixed when decided on curves
            assertEq(gate.curveId(), i + 1);
        }
    }

    function test_proxy() public view {
        uint256 gatesCount = curatedGates.length;
        address implementation = curatedGateFactory.CURATED_GATE_IMPL();
        assertTrue(implementation != address(0), "factory implementation zero");
        for (uint256 i = 0; i < gatesCount; ++i) {
            OssifiableProxy proxy = OssifiableProxy(payable(curatedGates[i]));
            assertEq(
                proxy.proxy__getImplementation(),
                implementation,
                "gate implementation mismatch"
            );
            assertEq(
                proxy.proxy__getAdmin(),
                deployParams.proxyAdmin,
                "gate proxy admin mismatch"
            );
        }
    }

    function test_roles() public view {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates deployed");

        for (uint256 i = 0; i < gatesCount; ++i) {
            {
                CuratedGate gate = CuratedGate(curatedGates[i]);
                assertEq(
                    gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()),
                    adminsCount
                );
                assertTrue(
                    gate.hasRole(
                        gate.DEFAULT_ADMIN_ROLE(),
                        deployParams.aragonAgent
                    ),
                    "missing aragon admin"
                );

                // Operational roles
                assertTrue(
                    gate.hasRole(gate.PAUSE_ROLE(), deployParams.resealManager),
                    "missing pause role"
                );
                assertTrue(
                    gate.hasRole(
                        gate.RESUME_ROLE(),
                        deployParams.resealManager
                    ),
                    "missing resume role"
                );
                assertTrue(
                    gate.hasRole(
                        gate.SET_TREE_ROLE(),
                        deployParams.easyTrackEVMScriptExecutor
                    ),
                    "missing set tree role"
                );
                assertTrue(
                    gate.hasRole(gate.PAUSE_ROLE(), address(gateSeal)),
                    "missing gate seal pause role"
                );
            }
        }
    }
}

contract GateSealDeploymentTest is DeploymentBaseTest {
    function test_configuration() public view {
        assertTrue(address(gateSeal) != address(0), "gate seal missing");
        address committee = gateSeal.get_sealing_committee();
        assertEq(committee, deployParams.sealingCommittee, "committee");
        assertEq(
            gateSeal.get_seal_duration_seconds(),
            deployParams.sealDuration,
            "seal duration"
        );
        assertEq(
            gateSeal.get_expiry_timestamp(),
            deployParams.sealExpiryTimestamp,
            "expiry"
        );
    }

    function test_sealables() public view {
        address[] memory sealables = gateSeal.get_sealables();
        uint256 expectedSealables = 5 + curatedGates.length;
        assertEq(sealables.length, expectedSealables, "sealables length");
        assertEq(sealables[0], address(module), "module mismatch");
        assertEq(sealables[1], address(accounting), "accounting mismatch");
        assertEq(sealables[2], address(oracle), "oracle mismatch");
        assertEq(sealables[3], address(verifier), "verifier mismatch");
        assertEq(sealables[4], address(ejector), "ejector mismatch");
        for (uint256 i = 0; i < curatedGates.length; ++i) {
            assertEq(sealables[5 + i], curatedGates[i], "gate mismatch");
        }
    }

    function test_roles() public view {
        assertTrue(
            curatedModule.hasRole(
                curatedModule.PAUSE_ROLE(),
                address(gateSeal)
            ),
            "curated module pause role"
        );
        assertTrue(
            accounting.hasRole(accounting.PAUSE_ROLE(), address(gateSeal)),
            "accounting pause role"
        );
        assertTrue(
            oracle.hasRole(oracle.PAUSE_ROLE(), address(gateSeal)),
            "oracle pause role"
        );
        assertTrue(
            verifier.hasRole(verifier.PAUSE_ROLE(), address(gateSeal)),
            "verifier pause role"
        );
        assertTrue(
            ejector.hasRole(ejector.PAUSE_ROLE(), address(gateSeal)),
            "ejector pause role"
        );
        for (uint256 i = 0; i < curatedGates.length; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            assertTrue(
                gate.hasRole(gate.PAUSE_ROLE(), address(gateSeal)),
                "gate pause role"
            );
        }
    }
}
