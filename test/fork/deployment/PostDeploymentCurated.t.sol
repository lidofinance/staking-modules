// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CuratedDeployParams, CuratedGateConfig, GateCurveParams } from "script/curated/DeployBase.s.sol";
import { CuratedGate } from "src/CuratedGate.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    CuratedDeployParams internal deployParams;
    CuratedGateConfig[] internal deployGateConfigs;
    uint256 adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) vm.skip(true);
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        // mutates storage variable
        updateCuratedDeployParams(deployParams, env.DEPLOY_CONFIG);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(module.getInitializedVersion(), 1);
    }

    function test_roles_onlyFull() public view {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        uint256 gatesCount = curatedGates.length;
        assertEq(module.getRoleMemberCount(role), gatesCount);

        for (uint256 i = 0; i < gatesCount; ++i) {
            assertTrue(module.hasRole(role, curatedGates[i]), "gate missing module role");
        }
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        curatedModule.initialize({ admin: deployParams.aragonAgent });

        OssifiableProxy proxy = OssifiableProxy(payable(address(curatedModule)));

        assertEq(proxy.proxy__getImplementation(), address(moduleImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        ICuratedModule moduleImpl = ICuratedModule(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        moduleImpl.initialize({ admin: deployParams.aragonAgent });
    }
}

contract MetaRegistryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(metaRegistry.getOperatorGroupsCount(), 1);

        IMetaRegistry.OperatorGroup memory groupInfo = metaRegistry.getOperatorGroup(metaRegistry.NO_GROUP_ID());
        assertEq(groupInfo.subNodeOperators.length, 0);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_roles_onlyFull() public view {
        assertEq(metaRegistry.getRoleMemberCount(metaRegistry.DEFAULT_ADMIN_ROLE()), adminsCount);
        assertTrue(metaRegistry.hasRole(metaRegistry.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent));

        bytes32 setterRole = metaRegistry.SET_OPERATOR_INFO_ROLE();
        uint256 gatesCount = curatedGates.length;
        assertEq(metaRegistry.getRoleMemberCount(setterRole), gatesCount);
        for (uint256 i = 0; i < gatesCount; ++i) {
            assertTrue(metaRegistry.hasRole(setterRole, curatedGates[i]), "gate missing metaRegistry setter role");
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
            assertEq(address(gate.META_REGISTRY()), address(metaRegistry));
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

    function test_curveParameters() public view {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates deployed");
        for (uint256 i = 0; i < gatesCount; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            uint256 curveId = gate.curveId();

            GateCurveParams memory params = deployParams.curatedGates[i].params;

            assertEq(parametersRegistry.getKeyRemovalCharge(curveId), params.keyRemovalCharge);
            assertEq(
                parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(curveId),
                params.generalDelayedPenaltyAdditionalFine
            );
            assertEq(parametersRegistry.getKeysLimit(curveId), params.keysLimit);

            IParametersRegistry.KeyNumberValueInterval[] memory avgPerfLeewayData = parametersRegistry
                .getPerformanceLeewayData(curveId);
            if (params.avgPerfLeewayData.length == 0) {
                assertEq(avgPerfLeewayData.length, 1);
                assertEq(avgPerfLeewayData[0].minKeyNumber, 1);
                assertEq(avgPerfLeewayData[0].value, deployParams.defaultAvgPerfLeewayBP);
            } else {
                assertEq(avgPerfLeewayData.length, params.avgPerfLeewayData.length);
                for (uint256 j = 0; j < avgPerfLeewayData.length; ++j) {
                    assertEq(avgPerfLeewayData[j].minKeyNumber, params.avgPerfLeewayData[j][0]);
                    assertEq(avgPerfLeewayData[j].value, params.avgPerfLeewayData[j][1]);
                }
            }

            IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
                curveId
            );
            if (params.rewardShareData.length == 0) {
                assertEq(rewardShareData.length, 1);
                assertEq(rewardShareData[0].minKeyNumber, 1);
                assertEq(rewardShareData[0].value, deployParams.defaultRewardShareBP);
            } else {
                assertEq(rewardShareData.length, params.rewardShareData.length);
                for (uint256 j = 0; j < rewardShareData.length; ++j) {
                    assertEq(rewardShareData[j].minKeyNumber, params.rewardShareData[j][0]);
                    assertEq(rewardShareData[j].value, params.rewardShareData[j][1]);
                }
            }

            (uint256 strikesLifetime, uint256 strikesThreshold) = parametersRegistry.getStrikesParams(curveId);
            if (params.strikesThreshold == 0) {
                assertEq(strikesLifetime, deployParams.defaultStrikesLifetimeFrames);
                assertEq(strikesThreshold, deployParams.defaultStrikesThreshold);
            } else {
                assertEq(strikesLifetime, params.strikesLifetimeFrames);
                assertEq(strikesThreshold, params.strikesThreshold);
            }

            (uint256 queuePriority, uint256 queueMaxDeposits) = parametersRegistry.getQueueConfig(curveId);
            if (params.queueMaxDeposits == 0) {
                assertEq(queuePriority, deployParams.defaultQueuePriority);
                assertEq(queueMaxDeposits, deployParams.defaultQueueMaxDeposits);
            } else {
                assertEq(queuePriority, params.queuePriority);
                assertEq(queueMaxDeposits, params.queueMaxDeposits);
            }

            assertEq(parametersRegistry.getBadPerformancePenalty(curveId), params.badPerformancePenalty);

            (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
                .getPerformanceCoefficients(curveId);
            if (params.attestationsWeight == 0 && params.blocksWeight == 0 && params.syncWeight == 0) {
                assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
                assertEq(blocksWeight, deployParams.defaultBlocksWeight);
                assertEq(syncWeight, deployParams.defaultSyncWeight);
            } else {
                assertEq(attestationsWeight, params.attestationsWeight);
                assertEq(blocksWeight, params.blocksWeight);
                assertEq(syncWeight, params.syncWeight);
            }

            assertEq(parametersRegistry.getAllowedExitDelay(curveId), params.allowedExitDelay);
            assertEq(parametersRegistry.getExitDelayFee(curveId), params.exitDelayFee);
            assertEq(parametersRegistry.getMaxElWithdrawalRequestFee(curveId), params.maxElWithdrawalRequestFee);

            // FIXME: add MetaRegistry-level assertions here to replace
            // the removed deposit-allocation-weight checks.
        }
    }

    function test_proxy() public view {
        uint256 gatesCount = curatedGates.length;
        address implementation = address(curatedGateImpl);
        assertTrue(implementation != address(0), "factory implementation zero");
        for (uint256 i = 0; i < gatesCount; ++i) {
            OssifiableProxy proxy = OssifiableProxy(payable(curatedGates[i]));
            assertEq(proxy.proxy__getImplementation(), implementation, "gate implementation mismatch");
            assertEq(proxy.proxy__getAdmin(), deployParams.proxyAdmin, "gate proxy admin mismatch");
        }
    }

    function test_roles() public view {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates deployed");
        bytes32 setBondCurveRole = accounting.SET_BOND_CURVE_ROLE();
        uint256 defaultCurveId = accounting.DEFAULT_BOND_CURVE_ID();
        uint256 setBondCurveRoleMembers;

        for (uint256 i = 0; i < gatesCount; ++i) {
            {
                CuratedGate gate = CuratedGate(curatedGates[i]);
                assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), adminsCount);
                assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent), "missing aragon admin");

                // Operational roles
                assertTrue(gate.hasRole(gate.PAUSE_ROLE(), deployParams.resealManager), "missing pause role");
                assertTrue(gate.hasRole(gate.RESUME_ROLE(), deployParams.resealManager), "missing resume role");
                assertTrue(
                    gate.hasRole(gate.SET_TREE_ROLE(), deployParams.easyTrackEVMScriptExecutor),
                    "missing set tree role"
                );
                assertTrue(gate.hasRole(gate.PAUSE_ROLE(), address(gateSeal)), "missing gate seal pause role");

                bool hasCustomCurve = gate.curveId() != defaultCurveId;
                assertEq(
                    accounting.hasRole(setBondCurveRole, address(gate)),
                    hasCustomCurve,
                    "unexpected set bond curve role"
                );
                if (hasCustomCurve) setBondCurveRoleMembers += 1;
            }
        }

        assertEq(accounting.getRoleMemberCount(setBondCurveRole), setBondCurveRoleMembers, "set bond curve roles");
    }
}

contract CuratedGateFactoryDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        assertTrue(address(curatedGateFactory) != address(0), "curated gate factory missing");

        address implementation = address(curatedGateImpl);
        assertTrue(implementation != address(0), "curated gate impl missing");
        assertEq(curatedGateFactory.GATE_IMPL(), implementation, "curated gate factory impl mismatch");
    }
}

contract GateSealDeploymentTest is DeploymentBaseTest {
    function test_configuration() public view {
        assertTrue(address(gateSeal) != address(0), "gate seal missing");
        address committee = gateSeal.get_sealing_committee();
        assertEq(committee, deployParams.sealingCommittee, "committee");
        assertEq(gateSeal.get_seal_duration_seconds(), deployParams.sealDuration, "seal duration");
        assertEq(gateSeal.get_expiry_timestamp(), deployParams.sealExpiryTimestamp, "expiry");
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
        assertTrue(curatedModule.hasRole(curatedModule.PAUSE_ROLE(), address(gateSeal)), "curated module pause role");
        assertTrue(accounting.hasRole(accounting.PAUSE_ROLE(), address(gateSeal)), "accounting pause role");
        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), address(gateSeal)), "oracle pause role");
        assertTrue(verifier.hasRole(verifier.PAUSE_ROLE(), address(gateSeal)), "verifier pause role");
        assertTrue(ejector.hasRole(ejector.PAUSE_ROLE(), address(gateSeal)), "ejector pause role");
        for (uint256 i = 0; i < curatedGates.length; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            assertTrue(gate.hasRole(gate.PAUSE_ROLE(), address(gateSeal)), "gate pause role");
        }
    }
}
