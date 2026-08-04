// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CuratedDeployParams, CuratedGateConfig, GateCurveParams } from "script/curated/DeployBase.s.sol";
import { CuratedGate } from "src/CuratedGate.sol";
import { IERC20LockBoostProvider } from "src/interfaces/IERC20LockBoostProvider.sol";
import { ICuratedModule } from "src/interfaces/ICuratedModule.sol";
import { BoostStep } from "src/interfaces/IAdditionalBondRegistry.sol";
import { StrikeThreshold } from "src/interfaces/INodeOperatorStrikes.sol";
import { FeeModifier } from "src/interfaces/ICustomFeeRegistry.sol";
import { IMetaRegistry } from "src/interfaces/IMetaRegistry.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { ProxySlotUtils } from "../../helpers/ProxySlotUtils.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    CuratedDeployParams internal deployParams;
    CuratedGateConfig[] internal deployGateConfigs;
    uint256 internal adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) vm.skip(true, "Current deployment is not Curated module type");
        adminsCount = block.chainid == 1 ? 1 : 2;
        string memory config = vm.readFile(env.DEPLOY_CONFIG);
        // mutates storage variable
        updateCuratedDeployParams(deployParams, env.DEPLOY_CONFIG);
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
        assertEq(
            module.getRoleMemberCount(curatedModule.OPERATOR_ADDRESSES_ADMIN_ROLE()),
            0,
            "unexpected operator addresses admin role members"
        );
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        curatedModule.initialize({ admin: deployParams.aragonAgent });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ICuratedModule(address(moduleImpl)).initialize({ admin: deployParams.aragonAgent });
    }

    function test_proxy_onlyFull() public view {
        OssifiableProxy proxy = OssifiableProxy(payable(address(curatedModule)));
        assertEq(proxy.proxy__getImplementation(), address(moduleImpl), "curated module proxy getter impl");
        assertEq(
            ProxySlotUtils.getImplementation(address(curatedModule)),
            address(moduleImpl),
            "curated module proxy slot impl"
        );
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin), "curated module proxy getter admin");
        assertEq(
            ProxySlotUtils.getAdmin(address(curatedModule)),
            address(deployParams.proxyAdmin),
            "curated module proxy slot admin"
        );
        assertFalse(proxy.proxy__getIsOssified(), "curated module proxy ossified");
    }
}

contract MetaRegistryDeploymentTest is DeploymentBaseTest {
    function _assertWeightBoostProvider(
        address expectedProvider,
        IMetaRegistry.WeightBoostProviderMode expectedMode
    ) internal view {
        uint256 providerId = metaRegistry.getWeightBoostProviderId(expectedProvider);
        assertNotEq(providerId, 0, "weight boost provider not registered");

        IMetaRegistry.WeightBoostProviderEntry memory entry = metaRegistry.getWeightBoostProvider(providerId);
        assertEq(address(entry.provider), expectedProvider, "unexpected weight boost provider");
        assertEq(uint256(entry.mode), uint256(expectedMode), "unexpected weight boost provider mode");
        assertTrue(entry.enabled, "weight boost provider disabled");
    }

    function test_state_onlyFull() public view {
        assertEq(metaRegistry.getInitializedVersion(), 1);
        assertEq(metaRegistry.getOperatorGroupsCount(), 0);

        IMetaRegistry.OperatorGroup memory groupInfo = metaRegistry.getOperatorGroup(metaRegistry.NO_GROUP_ID());
        assertEq(groupInfo.subNodeOperators.length, 0);
        assertEq(groupInfo.externalOperators.length, 0);
    }

    function test_roles_onlyFull() public view {
        _checkAdminRole(address(metaRegistry), deployParams.aragonAgent, deployParams.secondAdminAddress);

        bytes32 setterRole = metaRegistry.SET_OPERATOR_INFO_ROLE();
        uint256 gatesCount = curatedGates.length;
        assertEq(metaRegistry.getRoleMemberCount(setterRole), gatesCount + 1, "unexpected setter role members count"); // +1 for setOperatorInfoManager
        for (uint256 i = 0; i < gatesCount; ++i) {
            assertTrue(metaRegistry.hasRole(setterRole, curatedGates[i]), "gate missing metaRegistry setter role");
        }
        assertTrue(
            metaRegistry.hasRole(setterRole, deployParams.setOperatorInfoManager),
            "missing setOperatorInfoManager role"
        );

        assertTrue(
            metaRegistry.hasRole(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE(), deployParams.easyTrackEVMScriptExecutor),
            "missing easyTrackEVMScriptExecutor manage operator groups role"
        );

        assertEq(
            metaRegistry.getRoleMemberCount(metaRegistry.MANAGE_OPERATOR_GROUPS_ROLE()),
            1,
            "unexpected manage operator groups role members count"
        );

        assertEq(
            metaRegistry.getRoleMemberCount(metaRegistry.SET_BOND_CURVE_WEIGHT_ROLE()),
            0,
            "unexpected set bond curve weight role members count"
        );
    }

    function test_weightBoostProviders_onlyFull() public view {
        assertEq(metaRegistry.getWeightBoostProvidersCount(), 4, "unexpected weight boost providers count");
        _assertWeightBoostProvider(
            address(additionalBondRegistry),
            IMetaRegistry.WeightBoostProviderMode.PerNodeOperator
        );
        _assertWeightBoostProvider(address(nodeOperatorStrikes), IMetaRegistry.WeightBoostProviderMode.PerNodeOperator);
        _assertWeightBoostProvider(address(ldoLockBoostProvider), IMetaRegistry.WeightBoostProviderMode.MaxPerGroup);
        _assertWeightBoostProvider(address(customFeeRegistry), IMetaRegistry.WeightBoostProviderMode.PerNodeOperator);
    }
}

contract AdditionalBondRegistryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        BoostStep[] memory boostSteps = additionalBondRegistry.getBoostSteps();
        uint256[2][] memory expected = deployParams.additionalBondRegistryConfig.boostSteps;
        assertEq(boostSteps.length, expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(boostSteps[i].minCurveMultiplier, expected[i][0]);
            assertEq(boostSteps[i].weightMultiplier, expected[i][1]);
        }
    }

    function test_immutables_onlyFull() public view {
        assertEq(address(additionalBondRegistry.MODULE()), address(curatedModule), "additional bond registry module");
        assertEq(
            address(additionalBondRegistry.ACCOUNTING()),
            address(accounting),
            "additional bond registry accounting"
        );
        assertEq(
            address(additionalBondRegistry.META_REGISTRY()),
            address(metaRegistry),
            "additional bond registry meta registry"
        );
        assertEq(
            additionalBondRegistry.CURVE_MULTIPLIER_REDUCTION_COOLDOWN(),
            deployParams.additionalBondRegistryConfig.curveMultiplierCooldown,
            "additional bond registry cooldown"
        );
        assertEq(
            additionalBondRegistry.MAX_CURVE_MULTIPLIER(),
            90_000,
            "additional bond registry max curve multiplier"
        );
        assertEq(
            additionalBondRegistry.MAX_WEIGHT_MULTIPLIER(),
            90_000,
            "additional bond registry max weight multiplier"
        );
    }

    function test_roles_onlyFull() public view {
        _checkAdminRole(address(additionalBondRegistry), deployParams.aragonAgent, deployParams.secondAdminAddress);

        // AdditionalBondRegistry must be able to update the operator curve multiplier in Accounting.
        assertTrue(
            accounting.hasRole(accounting.SET_BOND_CURVE_MULTIPLIER_ROLE(), address(additionalBondRegistry)),
            "additional bond registry missing accounting set curve multiplier role"
        );
    }

    function test_wiring_onlyFull() public view {
        assertEq(
            address(metaRegistry.ADDITIONAL_BOND_REGISTRY()),
            address(additionalBondRegistry),
            "meta registry additional bond registry wiring"
        );
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        additionalBondRegistry.initialize(deployParams.aragonAgent, new BoostStep[](0));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        additionalBondRegistryImpl.initialize(deployParams.aragonAgent, new BoostStep[](0));
    }

    function test_proxy_onlyFull() public view {
        OssifiableProxy proxy = OssifiableProxy(payable(address(additionalBondRegistry)));
        assertEq(
            proxy.proxy__getImplementation(),
            address(additionalBondRegistryImpl),
            "additional bond registry proxy getter impl"
        );
        assertEq(
            ProxySlotUtils.getImplementation(address(additionalBondRegistry)),
            address(additionalBondRegistryImpl),
            "additional bond registry proxy slot impl"
        );
        assertEq(
            proxy.proxy__getAdmin(),
            address(deployParams.proxyAdmin),
            "additional bond registry proxy getter admin"
        );
        assertEq(
            ProxySlotUtils.getAdmin(address(additionalBondRegistry)),
            address(deployParams.proxyAdmin),
            "additional bond registry proxy slot admin"
        );
        assertFalse(proxy.proxy__getIsOssified(), "additional bond registry proxy ossified");
    }
}

contract NodeOperatorStrikesDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        StrikeThreshold[] memory thresholds = nodeOperatorStrikes.getStrikeThresholds();
        StrikeThreshold[] storage expected = deployParams.strikesThresholds;
        assertEq(thresholds.length, expected.length);
        for (uint256 i; i < expected.length; ++i) {
            assertEq(thresholds[i].minCount, expected[i].minCount);
            assertEq(thresholds[i].reductionBP, expected[i].reductionBP);
        }
    }

    function test_immutables_onlyFull() public view {
        assertEq(address(nodeOperatorStrikes.MODULE()), address(curatedModule), "node operator strikes module");
        assertEq(address(nodeOperatorStrikes.META_REGISTRY()), address(metaRegistry), "node operator strikes registry");
    }

    function test_roles_onlyFull() public view {
        _checkAdminRole(address(nodeOperatorStrikes), deployParams.aragonAgent, deployParams.secondAdminAddress);

        bytes32 committeeRole = nodeOperatorStrikes.STRIKES_COMMITTEE_ROLE();
        assertEq(nodeOperatorStrikes.getRoleMemberCount(committeeRole), 1);
        assertTrue(nodeOperatorStrikes.hasRole(committeeRole, deployParams.strikesCommittee));
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nodeOperatorStrikes.initialize(deployParams.aragonAgent, new StrikeThreshold[](0));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nodeOperatorStrikesImpl.initialize(deployParams.aragonAgent, new StrikeThreshold[](0));
    }

    function test_proxy_onlyFull() public view {
        OssifiableProxy proxy = OssifiableProxy(payable(address(nodeOperatorStrikes)));
        assertEq(proxy.proxy__getImplementation(), address(nodeOperatorStrikesImpl), "strikes proxy getter impl");
        assertEq(
            ProxySlotUtils.getImplementation(address(nodeOperatorStrikes)),
            address(nodeOperatorStrikesImpl),
            "strikes proxy slot impl"
        );
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin), "strikes proxy getter admin");
        assertEq(
            ProxySlotUtils.getAdmin(address(nodeOperatorStrikes)),
            address(deployParams.proxyAdmin),
            "strikes proxy slot admin"
        );
        assertFalse(proxy.proxy__getIsOssified(), "strikes proxy ossified");
    }
}

contract LDOLockBoostProviderDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(ldoLockBoostProvider.getInitializedVersion(), 1);
        assertEq(
            ldoLockBoostProvider.getLockPeriod(),
            deployParams.ldoLockBoostProviderConfig.lockPeriod,
            "LDO lock provider lock period"
        );

        IERC20LockBoostProvider.LockBoostStep[] memory actualSteps = ldoLockBoostProvider.getLockBoostSteps();
        uint256 stepsCount = deployParams.ldoLockBoostProviderConfig.lockBoostSteps.length;
        assertEq(actualSteps.length, stepsCount, "LDO lock boost steps count");
        for (uint256 i; i < stepsCount; ++i) {
            assertEq(
                actualSteps[i].minAmount,
                deployParams.ldoLockBoostProviderConfig.lockBoostSteps[i].minAmount,
                "LDO lock boost step min amount"
            );
            assertEq(
                actualSteps[i].weightBoostBP,
                deployParams.ldoLockBoostProviderConfig.lockBoostSteps[i].weightBoostBP,
                "LDO lock boost step weight boost"
            );
        }
    }

    function test_immutables_onlyFull() public view {
        assertEq(address(ldoLockBoostProvider.MODULE()), address(curatedModule), "LDO lock provider module");
        assertEq(
            address(ldoLockBoostProvider.META_REGISTRY()),
            address(metaRegistry),
            "LDO lock provider meta registry"
        );
        assertEq(
            ldoLockBoostProvider.TOKEN(),
            deployParams.ldoLockBoostProviderConfig.token,
            "LDO lock provider token"
        );
        assertEq(
            address(ldoLockBoostProvider.VAULT_BEACON()),
            address(ldoLockVaultBeacon),
            "LDO lock provider vault beacon"
        );
        assertEq(
            ldoLockBoostProvider.MIN_LOCK_PERIOD(),
            deployParams.ldoLockBoostProviderConfig.minLockPeriod,
            "LDO lock provider min lock period"
        );
        assertEq(ldoLockBoostProvider.MAX_LOCK_PERIOD(), 365 days, "LDO lock provider max lock period");
    }

    function test_roles_onlyFull() public view {
        _checkAdminRole(address(ldoLockBoostProvider), deployParams.aragonAgent, deployParams.secondAdminAddress);
    }

    function test_vaultBeacon_onlyFull() public view {
        assertGt(address(ldoLockVaultImpl).code.length, 0, "LDO lock vault impl code");
        assertGt(address(ldoLockVaultBeacon).code.length, 0, "LDO lock vault beacon code");
        assertEq(ldoLockVaultBeacon.implementation(), address(ldoLockVaultImpl), "LDO lock vault beacon impl");
        assertEq(ldoLockVaultBeacon.owner(), deployParams.aragonAgent, "LDO lock vault beacon owner");
    }

    function test_vaultImplementation_onlyFull() public view {
        assertEq(ldoLockVaultImpl.nodeOperatorId(), 0, "LDO lock vault impl node operator ID");
        assertEq(ldoLockVaultImpl.TOKEN(), deployParams.ldoLockBoostProviderConfig.token, "LDO lock vault impl token");
        assertEq(ldoLockVaultImpl.PROVIDER(), address(ldoLockBoostProvider), "LDO lock vault impl provider");
        assertEq(address(ldoLockVaultImpl.MODULE()), address(curatedModule), "LDO lock vault impl module");
        assertEq(
            ldoLockVaultImpl.VOTING_CONTRACT(),
            deployParams.ldoLockBoostProviderConfig.votingContract,
            "LDO lock vault impl voting"
        );
        assertEq(
            ldoLockVaultImpl.snapshotDelegation(),
            deployParams.ldoLockBoostProviderConfig.snapshotDelegation,
            "LDO lock vault impl snapshot delegation"
        );
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ldoLockBoostProvider.initialize(deployParams.aragonAgent, deployParams.ldoLockBoostProviderConfig.lockPeriod);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ldoLockBoostProviderImpl.initialize(
            deployParams.aragonAgent,
            deployParams.ldoLockBoostProviderConfig.lockPeriod
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ldoLockVaultImpl.initialize(0);
    }

    function test_proxy_onlyFull() public view {
        OssifiableProxy proxy = OssifiableProxy(payable(address(ldoLockBoostProvider)));
        assertEq(
            proxy.proxy__getImplementation(),
            address(ldoLockBoostProviderImpl),
            "LDO lock provider proxy getter impl"
        );
        assertEq(
            ProxySlotUtils.getImplementation(address(ldoLockBoostProvider)),
            address(ldoLockBoostProviderImpl),
            "LDO lock provider proxy slot impl"
        );
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin), "LDO lock provider proxy getter admin");
        assertEq(
            ProxySlotUtils.getAdmin(address(ldoLockBoostProvider)),
            address(deployParams.proxyAdmin),
            "LDO lock provider proxy slot admin"
        );
        assertFalse(proxy.proxy__getIsOssified(), "LDO lock provider proxy ossified");
    }
}

contract CustomFeeRegistryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(customFeeRegistry.getDefaultMinFee(), deployParams.customFeeRegistryConfig.defaultMinFee);
        assertEq(customFeeRegistry.getFeeIncreaseCooldown(), deployParams.customFeeRegistryConfig.feeIncreaseCooldown);

        for (uint256 i; i < deployParams.customFeeRegistryConfig.feeModifiers.length; ++i) {
            FeeModifier memory actual = customFeeRegistry.getFeeModifier(
                deployParams.customFeeRegistryConfig.feeModifiers[i].curveId
            );
            assertEq(actual.value, deployParams.customFeeRegistryConfig.feeModifiers[i].value);
            assertEq(actual.negative, deployParams.customFeeRegistryConfig.feeModifiers[i].negative);
        }

        uint256 defaultFee = customFeeRegistry.DEFAULT_MAX_FEE();
        for (uint256 curveId; curveId < accounting.getCurvesCount(); ++curveId) {
            FeeModifier memory feeModifier = customFeeRegistry.getFeeModifier(curveId);
            uint256 effectiveFee = feeModifier.negative
                ? defaultFee - feeModifier.value
                : defaultFee + feeModifier.value;
            assertEq(effectiveFee, curveId == 0 ? 6_250 : 8_750, "unexpected initial effective fee");
        }
    }

    function test_immutables_onlyFull() public view {
        assertEq(address(customFeeRegistry.MODULE()), address(curatedModule), "custom fee registry module");
        assertEq(address(customFeeRegistry.ACCOUNTING()), address(accounting), "custom fee registry accounting");
        assertEq(
            address(customFeeRegistry.META_REGISTRY()),
            address(metaRegistry),
            "custom fee registry meta registry"
        );
        assertEq(customFeeRegistry.FEE_STEP(), 250, "custom fee step");
        assertEq(customFeeRegistry.DEFAULT_MAX_FEE(), 8_750, "custom fee default max");
        assertEq(customFeeRegistry.WEIGHT_BOOST_PER_STEP(), 400, "custom fee weight boost per step");
        assertEq(customFeeRegistry.MAX_FEE_INCREASE_COOLDOWN(), type(uint32).max, "custom fee max increase cooldown");
    }

    function test_roles_onlyFull() public view {
        _checkAdminRole(address(customFeeRegistry), deployParams.aragonAgent, deployParams.secondAdminAddress);
    }

    function test_initialization_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        customFeeRegistry.initialize(deployParams.aragonAgent, 2_500, 15 days);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        customFeeRegistryImpl.initialize(deployParams.aragonAgent, 2_500, 15 days);
    }

    function test_proxy_onlyFull() public view {
        OssifiableProxy proxy = OssifiableProxy(payable(address(customFeeRegistry)));
        assertEq(proxy.proxy__getImplementation(), address(customFeeRegistryImpl), "custom fee proxy getter impl");
        assertEq(
            ProxySlotUtils.getImplementation(address(customFeeRegistry)),
            address(customFeeRegistryImpl),
            "custom fee proxy slot impl"
        );
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin), "custom fee proxy getter admin");
        assertEq(
            ProxySlotUtils.getAdmin(address(customFeeRegistry)),
            address(deployParams.proxyAdmin),
            "custom fee proxy slot admin"
        );
        assertFalse(proxy.proxy__getIsOssified(), "custom fee proxy ossified");
    }
}

contract CuratedGatesDeploymentTest is DeploymentBaseTest {
    function _expectedCurveId(uint256 gateIndex) internal view returns (uint256 curveId) {
        uint256 nextCustomCurveId = 1;
        uint256 gatesCount = deployParams.curatedGates.length;

        for (uint256 i = 0; i < gatesCount; ++i) {
            bool hasCustomCurve = deployParams.curatedGates[i].bondCurve.length != 0;
            uint256 currentCurveId = hasCustomCurve ? nextCustomCurveId : accounting.DEFAULT_BOND_CURVE_ID();
            if (i == gateIndex) return currentCurveId;
            if (hasCustomCurve) ++nextCustomCurveId;
        }

        revert("invalid gate index");
    }

    function _assertCreateRoleOrderMatchesConfig() internal view {
        bytes32 role = module.CREATE_NODE_OPERATOR_ROLE();
        address[] memory members = module.getRoleMembers(role);
        assertEq(members.length, deployParams.curatedGates.length, "unexpected create role members count");

        for (uint256 i = 0; i < members.length; ++i) {
            assertEq(members[i], curatedGates[i], "create role order mismatch");

            CuratedGate gate = CuratedGate(members[i]);
            CuratedGateConfig storage cfg = deployParams.curatedGates[i];
            assertEq(gate.treeRoot(), cfg.treeRoot, "unexpected gate root");
            assertEq(gate.treeCid(), cfg.treeCid, "unexpected gate cid");
            assertEq(gate.name(), cfg.name, "unexpected gate name");
            assertEq(gate.curveId(), _expectedCurveId(i), "unexpected gate curve");
        }
    }

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
            assertEq(gate.name(), deployParams.curatedGates[i].name);
            assertEq(gate.curveId(), _expectedCurveId(i));
        }
    }

    function test_curveParameters() public view {
        uint256 gatesCount = curatedGates.length;
        assertGt(gatesCount, 0, "no curated gates deployed");
        assertEq(accounting.getCurvesCount(), gatesCount, "unexpected total curves count"); // +1 for the default curve
        for (uint256 i = 0; i < gatesCount; ++i) {
            CuratedGate gate = CuratedGate(curatedGates[i]);
            uint256 curveId = gate.curveId();

            GateCurveParams memory params = deployParams.curatedGates[i].params;
            assertEq(parametersRegistry.getKeyRemovalCharge(curveId), deployParams.defaultKeyRemovalCharge);

            if (params.generalDelayedPenaltyAdditionalFine.isValue) {
                assertEq(
                    parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(curveId),
                    params.generalDelayedPenaltyAdditionalFine.value
                );
            } else {
                assertEq(
                    parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(curveId),
                    deployParams.defaultGeneralDelayedPenaltyAdditionalFine
                );
            }

            if (params.keysLimit.isValue) {
                assertEq(parametersRegistry.getKeysLimit(curveId), params.keysLimit.value);
            } else {
                assertEq(parametersRegistry.getKeysLimit(curveId), deployParams.defaultKeysLimit);
            }

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
            if (params.strikesLifetimeFrames.isValue || params.strikesThreshold.isValue) {
                assertEq(strikesLifetime, params.strikesLifetimeFrames.value);
                assertEq(strikesThreshold, params.strikesThreshold.value);
            } else {
                assertEq(strikesLifetime, deployParams.defaultStrikesLifetimeFrames);
                assertEq(strikesThreshold, deployParams.defaultStrikesThreshold);
            }

            (uint256 queuePriority, uint256 queueMaxDeposits) = parametersRegistry.getQueueConfig(curveId);
            assertEq(queuePriority, deployParams.defaultQueuePriority);
            assertEq(queueMaxDeposits, deployParams.defaultQueueMaxDeposits);

            if (params.badPerformancePenalty.isValue) {
                assertEq(parametersRegistry.getBadPerformancePenalty(curveId), params.badPerformancePenalty.value);
            } else {
                assertEq(
                    parametersRegistry.getBadPerformancePenalty(curveId),
                    deployParams.defaultBadPerformancePenalty
                );
            }

            (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
                .getPerformanceCoefficients(curveId);
            if (params.attestationsWeight.isValue || params.blocksWeight.isValue || params.syncWeight.isValue) {
                assertEq(attestationsWeight, params.attestationsWeight.value);
                assertEq(blocksWeight, params.blocksWeight.value);
                assertEq(syncWeight, params.syncWeight.value);
            } else {
                assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
                assertEq(blocksWeight, deployParams.defaultBlocksWeight);
                assertEq(syncWeight, deployParams.defaultSyncWeight);
            }

            if (params.allowedExitDelay.isValue) {
                assertEq(parametersRegistry.getAllowedExitDelay(curveId), params.allowedExitDelay.value);
            } else {
                assertEq(parametersRegistry.getAllowedExitDelay(curveId), deployParams.defaultAllowedExitDelay);
            }

            if (params.exitDelayFee.isValue) {
                assertEq(parametersRegistry.getExitDelayFee(curveId), params.exitDelayFee.value);
            } else {
                assertEq(parametersRegistry.getExitDelayFee(curveId), deployParams.defaultExitDelayFee);
            }

            if (params.maxElWithdrawalRequestFee.isValue) {
                assertEq(
                    parametersRegistry.getMaxElWithdrawalRequestFee(curveId),
                    params.maxElWithdrawalRequestFee.value
                );
            } else {
                assertEq(
                    parametersRegistry.getMaxElWithdrawalRequestFee(curveId),
                    deployParams.defaultMaxElWithdrawalRequestFee
                );
            }

            if (params.metaRegistryBondCurveWeight.isValue) {
                assertEq(metaRegistry.getBondCurveWeight(curveId), params.metaRegistryBondCurveWeight.value);
            }
        }
    }

    function test_proxy() public view {
        uint256 gatesCount = curatedGates.length;
        address implementation = address(curatedGateImpl);
        assertTrue(implementation != address(0), "factory implementation zero");
        for (uint256 i = 0; i < gatesCount; ++i) {
            OssifiableProxy proxy = OssifiableProxy(payable(curatedGates[i]));
            assertEq(proxy.proxy__getImplementation(), implementation, "curated gate proxy getter impl");
            assertEq(ProxySlotUtils.getImplementation(curatedGates[i]), implementation, "curated gate proxy slot impl");
            assertEq(proxy.proxy__getAdmin(), deployParams.proxyAdmin, "curated gate proxy getter admin");
            assertEq(
                ProxySlotUtils.getAdmin(curatedGates[i]),
                deployParams.proxyAdmin,
                "curated gate proxy slot admin"
            );
            assertFalse(proxy.proxy__getIsOssified(), "curated gate proxy ossified");
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
                _checkAdminRole(address(gate), deployParams.aragonAgent, deployParams.secondAdminAddress);

                // Operational roles
                assertTrue(
                    gate.hasRole(gate.SET_TREE_ROLE(), deployParams.easyTrackEVMScriptExecutor),
                    "missing set tree role"
                );
                assertEq(gate.getRoleMemberCount(gate.SET_TREE_ROLE()), 1, "unexpected set tree role members count");

                assertTrue(gate.hasRole(gate.PAUSE_ROLE(), deployParams.curatedGatePauseManager), "missing pause role");
                assertEq(gate.getRoleMemberCount(gate.PAUSE_ROLE()), 1, "unexpected pause role members count");

                assertEq(gate.getRoleMemberCount(gate.RESUME_ROLE()), 0, "unexpected resume role members count");
                assertEq(gate.getRoleMemberCount(gate.RECOVERER_ROLE()), 0, "unexpected recoverer role members count");

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

    function test_roleWiringMatchesConfiguredGates_onlyFull() public view {
        _assertCreateRoleOrderMatchesConfig();
        uint256 gatesCount = curatedGates.length;

        bytes32 metaSetterRole = metaRegistry.SET_OPERATOR_INFO_ROLE();
        uint256 metaMembersCount = metaRegistry.getRoleMemberCount(metaSetterRole);
        assertEq(metaMembersCount, gatesCount + 1, "unexpected meta setter role members count");

        uint256 defaultCurveId = accounting.DEFAULT_BOND_CURVE_ID();
        bytes32 setBondCurveRole = accounting.SET_BOND_CURVE_ROLE();
        uint256 expectedSetBondCurveMembers;
        for (uint256 i = 0; i < gatesCount; ++i) {
            address gateAddress = curatedGates[i];
            CuratedGate gate = CuratedGate(gateAddress);

            assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), gateAddress), "missing create role");
            assertTrue(metaRegistry.hasRole(metaSetterRole, gateAddress), "missing meta setter role");

            bool hasCustomCurve = gate.curveId() != defaultCurveId;
            assertEq(
                accounting.hasRole(setBondCurveRole, gateAddress),
                hasCustomCurve,
                "unexpected set bond curve role"
            );
            if (hasCustomCurve) ++expectedSetBondCurveMembers;
        }

        assertTrue(
            metaRegistry.hasRole(metaSetterRole, deployParams.setOperatorInfoManager),
            "missing setOperatorInfoManager role"
        );
        assertEq(accounting.getRoleMemberCount(setBondCurveRole), expectedSetBondCurveMembers, "set bond curve roles");
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

contract CircuitBreakerDeploymentTest is DeploymentBaseTest {
    function test_configuration_afterVote() public {
        address pauser = circuitBreaker.getPauser(address(module));
        assertEq(pauser, deployParams.circuitBreakerPauser, "pauser");
    }

    function test_pausables_afterVote() public {
        assertEq(circuitBreaker.getPauser(address(module)), deployParams.circuitBreakerPauser, "module pauser");
        assertEq(circuitBreaker.getPauser(address(accounting)), deployParams.circuitBreakerPauser, "accounting pauser");
        assertEq(circuitBreaker.getPauser(address(oracle)), deployParams.circuitBreakerPauser, "oracle pauser");
        assertEq(circuitBreaker.getPauser(address(verifier)), deployParams.circuitBreakerPauser, "verifier pauser");
        assertEq(circuitBreaker.getPauser(address(ejector)), deployParams.circuitBreakerPauser, "ejector pauser");
    }

    function test_roles() public {
        assertTrue(
            curatedModule.hasRole(curatedModule.PAUSE_ROLE(), address(circuitBreaker)),
            "curated module pause role"
        );
        assertTrue(accounting.hasRole(accounting.PAUSE_ROLE(), address(circuitBreaker)), "accounting pause role");
        assertTrue(oracle.hasRole(oracle.PAUSE_ROLE(), address(circuitBreaker)), "oracle pause role");
        assertTrue(verifier.hasRole(verifier.PAUSE_ROLE(), address(circuitBreaker)), "verifier pause role");
        assertTrue(ejector.hasRole(ejector.PAUSE_ROLE(), address(circuitBreaker)), "ejector pause role");
    }
}
