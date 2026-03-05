// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { DeployParams } from "script/csm/DeployBase.s.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IParametersRegistry } from "src/interfaces/IParametersRegistry.sol";
import { OssifiableProxy } from "src/lib/proxy/OssifiableProxy.sol";
import { VettedGate } from "src/VettedGate.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";

contract DeploymentBaseTest is Test, Utilities, DeploymentFixtures {
    bytes32 internal constant START_REFERRAL_SEASON_ROLE = keccak256("START_REFERRAL_SEASON_ROLE");
    bytes32 internal constant END_REFERRAL_SEASON_ROLE = keccak256("END_REFERRAL_SEASON_ROLE");

    DeployParams internal deployParams;
    uint256 adminsCount;

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Community) vm.skip(true, "Current deployment is not Community module type");
        deployParams = parseDeployParams(env.DEPLOY_CONFIG);
        adminsCount = block.chainid == 1 ? 1 : 2;
    }
}

contract ModuleDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(module.getInitializedVersion(), 3);
        assertEq(module.getNodeOperatorDepositInfoToUpdateCount(), 0);
    }

    function test_unusedStorageSlots_onlyFull() public {
        bytes32 slot1 = vm.load(address(module), bytes32(uint256(1)));
        assertEq(slot1, bytes32(0), "assert __freeSlot1 is empty");
    }

    function test_roles_onlyFull() public view {
        assertEq(module.getRoleMemberCount(module.CREATE_NODE_OPERATOR_ROLE()), 2);
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(vettedGate)));
        assertTrue(module.hasRole(module.CREATE_NODE_OPERATOR_ROLE(), address(permissionlessGate)));
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        module.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: 0 });

        OssifiableProxy proxy = OssifiableProxy(payable(address(module)));

        assertEq(proxy.proxy__getImplementation(), address(moduleImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        ICSModule moduleImpl = ICSModule(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        moduleImpl.initialize({ admin: deployParams.aragonAgent, topUpQueueLimit: 0 });
    }
}

contract AccountingDeploymentTest is DeploymentBaseTest {
    function test_roles_onlyFull() public view {
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), deployParams.setResetBondCurveAddress));
        assertTrue(accounting.hasRole(accounting.SET_BOND_CURVE_ROLE(), address(vettedGate)));
        assertEq(accounting.getRoleMemberCount(accounting.SET_BOND_CURVE_ROLE()), 2);
    }
}

contract ParametersRegistryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertEq(parametersRegistry.defaultKeyRemovalCharge(), deployParams.defaultKeyRemovalCharge);
        assertEq(
            parametersRegistry.defaultGeneralDelayedPenaltyAdditionalFine(),
            deployParams.defaultGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(parametersRegistry.defaultKeysLimit(), deployParams.defaultKeysLimit);
        assertEq(parametersRegistry.defaultRewardShare(), deployParams.defaultRewardShareBP);
        assertEq(parametersRegistry.defaultPerformanceLeeway(), deployParams.defaultAvgPerfLeewayBP);
        (uint256 strikesLifetime, uint256 strikesThreshold) = parametersRegistry.defaultStrikesParams();
        assertEq(strikesLifetime, deployParams.defaultStrikesLifetimeFrames);
        assertEq(strikesThreshold, deployParams.defaultStrikesThreshold);

        (uint256 priority, uint256 maxDeposits) = parametersRegistry.defaultQueueConfig();
        assertEq(priority, deployParams.defaultQueuePriority);
        assertEq(maxDeposits, deployParams.defaultQueueMaxDeposits);

        assertEq(parametersRegistry.defaultBadPerformancePenalty(), deployParams.defaultBadPerformancePenalty);

        (uint256 attestationsWeight, uint256 blocksWeight, uint256 syncWeight) = parametersRegistry
            .defaultPerformanceCoefficients();
        assertEq(attestationsWeight, deployParams.defaultAttestationsWeight);
        assertEq(blocksWeight, deployParams.defaultBlocksWeight);
        assertEq(syncWeight, deployParams.defaultSyncWeight);
        assertEq(parametersRegistry.defaultAllowedExitDelay(), deployParams.defaultAllowedExitDelay);
        assertEq(parametersRegistry.defaultExitDelayFee(), deployParams.defaultExitDelayFee);
        assertEq(parametersRegistry.defaultMaxElWithdrawalRequestFee(), deployParams.defaultMaxElWithdrawalRequestFee);
        assertEq(parametersRegistry.getInitializedVersion(), 3);

        // Params for Identified Community Staker type
        uint256 identifiedCommunityStakersGateCurveId = vettedGate.curveId();
        assertEq(
            parametersRegistry.getKeyRemovalCharge(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateKeyRemovalCharge
        );
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(
            parametersRegistry.getKeysLimit(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateKeysLimit
        );

        IParametersRegistry.KeyNumberValueInterval[] memory rewardShareData = parametersRegistry.getRewardShareData(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(rewardShareData.length, deployParams.identifiedCommunityStakersGateRewardShareData.length);
        for (uint256 i = 0; i < rewardShareData.length; i++) {
            assertEq(rewardShareData[i].minKeyNumber, deployParams.identifiedCommunityStakersGateRewardShareData[i][0]);
            assertEq(rewardShareData[i].value, deployParams.identifiedCommunityStakersGateRewardShareData[i][1]);
        }
        IParametersRegistry.KeyNumberValueInterval[] memory performanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(identifiedCommunityStakersGateCurveId);
        assertEq(performanceLeewayData.length, deployParams.identifiedCommunityStakersGateAvgPerfLeewayData.length);
        for (uint256 i = 0; i < performanceLeewayData.length; i++) {
            assertEq(
                performanceLeewayData[i].minKeyNumber,
                deployParams.identifiedCommunityStakersGateAvgPerfLeewayData[i][0]
            );
            assertEq(
                performanceLeewayData[i].value,
                deployParams.identifiedCommunityStakersGateAvgPerfLeewayData[i][1]
            );
        }

        (uint256 lifetime, uint256 threshold) = parametersRegistry.getStrikesParams(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(lifetime, deployParams.identifiedCommunityStakersGateStrikesLifetimeFrames);
        assertEq(threshold, deployParams.identifiedCommunityStakersGateStrikesThreshold);

        (uint256 icsPriority, uint256 icsMaxDeposits) = parametersRegistry.getQueueConfig(
            identifiedCommunityStakersGateCurveId
        );
        assertEq(icsPriority, deployParams.identifiedCommunityStakersGateQueuePriority);
        assertEq(icsMaxDeposits, deployParams.identifiedCommunityStakersGateQueueMaxDeposits);

        assertEq(
            parametersRegistry.getBadPerformancePenalty(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateBadPerformancePenalty
        );
        (uint256 icsAttestationsWeight, uint256 icsBlocksWeight, uint256 icsSyncWeight) = parametersRegistry
            .getPerformanceCoefficients(identifiedCommunityStakersGateCurveId);
        assertEq(icsAttestationsWeight, deployParams.identifiedCommunityStakersGateAttestationsWeight);
        assertEq(icsBlocksWeight, deployParams.identifiedCommunityStakersGateBlocksWeight);
        assertEq(icsSyncWeight, deployParams.identifiedCommunityStakersGateSyncWeight);

        assertEq(
            parametersRegistry.getAllowedExitDelay(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateAllowedExitDelay
        );
        assertEq(
            parametersRegistry.getExitDelayFee(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateExitDelayFee
        );
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(identifiedCommunityStakersGateCurveId),
            deployParams.identifiedCommunityStakersGateMaxElWithdrawalRequestFee
        );
        // Params for Legacy EA type
        uint256 legacyEaBondCurveId = identifiedCommunityStakersGateCurveId - 1;
        assertEq(parametersRegistry.getKeyRemovalCharge(legacyEaBondCurveId), deployParams.defaultKeyRemovalCharge);
        assertEq(
            parametersRegistry.getGeneralDelayedPenaltyAdditionalFine(legacyEaBondCurveId),
            deployParams.defaultGeneralDelayedPenaltyAdditionalFine
        );
        assertEq(parametersRegistry.getKeysLimit(legacyEaBondCurveId), deployParams.defaultKeysLimit);

        IParametersRegistry.KeyNumberValueInterval[] memory legacyEaRewardShareData = parametersRegistry
            .getRewardShareData(legacyEaBondCurveId);
        assertEq(legacyEaRewardShareData.length, 1);
        assertEq(legacyEaRewardShareData[0].minKeyNumber, 1);
        assertEq(legacyEaRewardShareData[0].value, deployParams.defaultRewardShareBP);
        IParametersRegistry.KeyNumberValueInterval[] memory legacyEaPerformanceLeewayData = parametersRegistry
            .getPerformanceLeewayData(legacyEaBondCurveId);
        assertEq(legacyEaPerformanceLeewayData.length, 1);
        assertEq(legacyEaPerformanceLeewayData[0].minKeyNumber, 1);
        assertEq(legacyEaPerformanceLeewayData[0].value, deployParams.defaultAvgPerfLeewayBP);

        (uint256 legacyEaLifetime, uint256 legacyEaThreshold) = parametersRegistry.getStrikesParams(
            legacyEaBondCurveId
        );
        assertEq(legacyEaLifetime, deployParams.defaultStrikesLifetimeFrames);
        assertEq(legacyEaThreshold, deployParams.defaultStrikesThreshold);

        (uint256 legacyEaPriority, uint256 legacyEaMaxDeposits) = parametersRegistry.getQueueConfig(
            legacyEaBondCurveId
        );
        assertEq(legacyEaPriority, deployParams.defaultQueuePriority);
        assertEq(legacyEaMaxDeposits, deployParams.defaultQueueMaxDeposits);

        assertEq(
            parametersRegistry.getBadPerformancePenalty(legacyEaBondCurveId),
            deployParams.defaultBadPerformancePenalty
        );
        (
            uint256 legacyEaAttestationsWeight,
            uint256 legacyEaBlocksWeight,
            uint256 legacyEaSyncWeight
        ) = parametersRegistry.getPerformanceCoefficients(legacyEaBondCurveId);
        assertEq(legacyEaAttestationsWeight, deployParams.defaultAttestationsWeight);
        assertEq(legacyEaBlocksWeight, deployParams.defaultBlocksWeight);
        assertEq(legacyEaSyncWeight, deployParams.defaultSyncWeight);

        assertEq(parametersRegistry.getAllowedExitDelay(legacyEaBondCurveId), deployParams.defaultAllowedExitDelay);
        assertEq(parametersRegistry.getExitDelayFee(legacyEaBondCurveId), deployParams.defaultExitDelayFee);
        assertEq(
            parametersRegistry.getMaxElWithdrawalRequestFee(legacyEaBondCurveId),
            deployParams.defaultMaxElWithdrawalRequestFee
        );
    }
}

contract VettedGateDeploymentTest is DeploymentBaseTest {
    function test_state() public view {
        assertFalse(vettedGate.isPaused());
        assertEq(vettedGate.treeRoot(), deployParams.identifiedCommunityStakersGateTreeRoot);
        assertEq(vettedGate.treeCid(), deployParams.identifiedCommunityStakersGateTreeCid);

        assertTrue(vettedGate.curveId() == deployParams.identifiedCommunityStakersGateCurveId);
        assertEq(vettedGate.getInitializedVersion(), 1);
    }

    function test_immutables() public view {
        assertEq(address(vettedGateImpl.MODULE()), address(module));
        assertEq(address(vettedGateImpl.ACCOUNTING()), address(accounting));
    }

    function test_roles_onlyFull() public view {
        assertTrue(vettedGate.hasRole(vettedGate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent));
        assertEq(oracle.getRoleMemberCount(oracle.DEFAULT_ADMIN_ROLE()), adminsCount);

        assertTrue(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), address(gateSeal)));
        assertTrue(vettedGate.hasRole(vettedGate.PAUSE_ROLE(), deployParams.resealManager));
        assertEq(vettedGate.getRoleMemberCount(vettedGate.PAUSE_ROLE()), 2);

        assertTrue(vettedGate.hasRole(vettedGate.RESUME_ROLE(), deployParams.resealManager));
        assertEq(vettedGate.getRoleMemberCount(vettedGate.RESUME_ROLE()), 1);

        assertEq(vettedGate.getRoleMemberCount(vettedGate.RECOVERER_ROLE()), 0);

        assertTrue(vettedGate.hasRole(vettedGate.SET_TREE_ROLE(), deployParams.easyTrackEVMScriptExecutor));
        assertEq(vettedGate.getRoleMemberCount(vettedGate.SET_TREE_ROLE()), 1);

        // Legacy referral program roles are not used in the new VettedGate.
        assertEq(vettedGate.getRoleMemberCount(START_REFERRAL_SEASON_ROLE), 0);
        assertEq(vettedGate.getRoleMemberCount(END_REFERRAL_SEASON_ROLE), 0);
    }

    function test_proxy_onlyFull() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vettedGate.initialize({
            curveId: 1,
            treeRoot: deployParams.identifiedCommunityStakersGateTreeRoot,
            treeCid: deployParams.identifiedCommunityStakersGateTreeCid,
            admin: deployParams.aragonAgent
        });

        OssifiableProxy proxy = OssifiableProxy(payable(address(vettedGate)));

        assertEq(proxy.proxy__getImplementation(), address(vettedGateImpl));
        assertEq(proxy.proxy__getAdmin(), address(deployParams.proxyAdmin));
        assertFalse(proxy.proxy__getIsOssified());

        VettedGate vettedGateImpl = VettedGate(proxy.proxy__getImplementation());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vettedGateImpl.initialize({
            curveId: 1,
            treeRoot: deployParams.identifiedCommunityStakersGateTreeRoot,
            treeCid: deployParams.identifiedCommunityStakersGateTreeCid,
            admin: deployParams.aragonAgent
        });
    }
}

contract VettedGateFactoryDeploymentTest is DeploymentBaseTest {
    function test_state_onlyFull() public view {
        assertTrue(address(vettedGateFactory) != address(0), "vetted gate factory missing");

        address vettedGateImplementation = OssifiableProxy(payable(address(vettedGate))).proxy__getImplementation();
        assertEq(vettedGateFactory.GATE_IMPL(), vettedGateImplementation, "vetted gate factory impl mismatch");
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
        assertEq(sealables.length, 6, "sealables length");
        assertEq(sealables[0], address(module), "module mismatch");
        assertEq(sealables[1], address(accounting), "accounting mismatch");
        assertEq(sealables[2], address(oracle), "oracle mismatch");
        assertEq(sealables[3], address(verifier), "verifier mismatch");
        assertEq(sealables[4], address(vettedGate), "vetted gate mismatch");
        assertEq(sealables[5], address(ejector), "ejector mismatch");
    }
}

contract PermissionlessGateDeploymentTest is DeploymentBaseTest {
    function test_immutables() public view {
        assertEq(address(permissionlessGate.MODULE()), address(module));
        assertEq(permissionlessGate.CURVE_ID(), accounting.DEFAULT_BOND_CURVE_ID());
    }

    function test_roles() public view {
        assertTrue(permissionlessGate.hasRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), deployParams.aragonAgent));
        assertEq(permissionlessGate.getRoleMemberCount(permissionlessGate.DEFAULT_ADMIN_ROLE()), adminsCount);
        if (deployParams.secondAdminAddress != address(0)) {
            assertTrue(
                permissionlessGate.hasRole(permissionlessGate.DEFAULT_ADMIN_ROLE(), deployParams.secondAdminAddress)
            );
        }
        assertEq(permissionlessGate.getRoleMemberCount(permissionlessGate.RECOVERER_ROLE()), 0);
    }
}
