// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { CuratedDeployParams } from "../../../script/curated/DeployBase.s.sol";
import { NodeOperator } from "../../../src/interfaces/IBaseModule.sol";
import { OssifiableProxy } from "../../../src/lib/proxy/OssifiableProxy.sol";

contract CuratedV2UpgradeTest is Test, DeploymentFixtures {
    uint256 internal forkIdBeforeUpgrade;
    uint256 internal forkIdAfterUpgrade;
    CuratedDeployParams internal deployParams;

    function setUp() public {
        Env memory env = envVars();
        forkIdAfterUpgrade = vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
        if (moduleType != ModuleType.Curated) vm.skip(true, "Curated deployment required");

        uint256 votePrevBlock = vm.envUint("VOTE_PREV_BLOCK");
        assertNotEq(votePrevBlock, 0, "VOTE_PREV_BLOCK not set");
        forkIdBeforeUpgrade = vm.createFork(env.RPC_URL, votePrevBlock);

        updateCuratedDeployParams(deployParams, env.DEPLOY_CONFIG);
    }

    function test_curatedModuleChanges() public {
        vm.selectFork(forkIdBeforeUpgrade);
        assertEq(module.getInitializedVersion(), 1);
        uint256 nonceBefore = module.getNonce();
        address implementationBefore = OssifiableProxy(payable(address(module))).proxy__getImplementation();
        address adminBefore = OssifiableProxy(payable(address(module))).proxy__getAdmin();

        vm.selectFork(forkIdAfterUpgrade);
        assertEq(module.getInitializedVersion(), 2);
        assertEq(module.getNonce(), nonceBefore + 1);
        assertNotEq(implementationBefore, address(curatedModuleImpl));
        assertEq(OssifiableProxy(payable(address(module))).proxy__getImplementation(), address(curatedModuleImpl));
        assertEq(OssifiableProxy(payable(address(module))).proxy__getAdmin(), adminBefore);
    }

    function test_topUpAllocationMigration() public {
        uint256 count = module.getNodeOperatorsCount();
        for (uint256 noId; noId < count; ++noId) {
            vm.selectFork(forkIdBeforeUpgrade);
            NodeOperator memory no = module.getNodeOperator(noId);

            vm.selectFork(forkIdAfterUpgrade);
            assertEq(curatedModule.isTopUpAllocationEnabled(noId), no.totalDepositedKeys > no.totalWithdrawnKeys);
        }
    }

    function test_topUpAllocationRole() public {
        bytes32 role = curatedModule.ENABLE_TOP_UP_ALLOCATION_ROLE();
        vm.selectFork(forkIdBeforeUpgrade);
        assertEq(module.getRoleMemberCount(role), 0);

        vm.selectFork(forkIdAfterUpgrade);
        assertNotEq(deployParams.topUpAllocationEnabler, address(0));
        assertEq(module.getRoleMemberCount(role), 1);
        assertTrue(module.hasRole(role, deployParams.topUpAllocationEnabler));
    }

    function test_curatedModuleState() public {
        vm.selectFork(forkIdBeforeUpgrade);
        uint256 countBefore = module.getNodeOperatorsCount();
        uint256 stakeBefore = module.getTotalModuleStake();
        (uint256 exitedBefore, uint256 depositedBefore, uint256 depositableBefore) = module.getStakingModuleSummary();

        vm.selectFork(forkIdAfterUpgrade);
        assertEq(module.getNodeOperatorsCount(), countBefore);
        assertEq(module.getTotalModuleStake(), stakeBefore);
        (uint256 exitedAfter, uint256 depositedAfter, uint256 depositableAfter) = module.getStakingModuleSummary();
        assertEq(exitedAfter, exitedBefore);
        assertEq(depositedAfter, depositedBefore);
        assertEq(depositableAfter, depositableBefore);

        for (uint256 noId; noId < countBefore; ++noId) {
            vm.selectFork(forkIdBeforeUpgrade);
            bytes memory noBefore = abi.encode(module.getNodeOperator(noId));
            uint256 balanceBefore = module.getNodeOperatorBalance(noId);

            vm.selectFork(forkIdAfterUpgrade);
            assertEq(abi.encode(module.getNodeOperator(noId)), noBefore);
            assertEq(module.getNodeOperatorBalance(noId), balanceBefore);
        }
    }
}
