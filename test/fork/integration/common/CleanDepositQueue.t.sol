// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICSModule } from "src/interfaces/ICSModule.sol";
import { NodeOperator } from "src/interfaces/IBaseModule.sol";

import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase } from "./ModuleTypeBase.sol";

abstract contract CleanDepositQueueTestBase is ModuleTypeBase {
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 5;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        _assertModuleEnqueuedCount();
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public virtual {
        _setUpModule();

        address moduleAdmin = module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0);
        bytes32 moduleAdminRole = module.DEFAULT_ADMIN_ROLE();
        vm.prank(moduleAdmin);
        module.grantRole(moduleAdminRole, address(this));

        handleStakingLimit();
        handleBunkerMode();

        nodeOperator = nextAddress("NodeOperator");
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
    }

    function test_cleanDepositQueue_afterKeyRemoval() public assertInvariants {
        ICSModule csm = ICSModule(address(module));

        NodeOperator memory noBefore = module.getNodeOperator(defaultNoId);
        assertGt(noBefore.enqueuedCount, 0, "NO should have enqueued keys");

        vm.prank(nodeOperator);
        module.removeKeys(defaultNoId, 0, initialKeysCount);

        NodeOperator memory noAfterRemoval = module.getNodeOperator(defaultNoId);
        assertEq(noAfterRemoval.depositableValidatorsCount, 0, "depositable count should be 0 after removing keys");
        assertGt(noAfterRemoval.enqueuedCount, 0, "NO should have stale enqueued keys before cleanup");

        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertGt(removed, 0, "should remove stale batches");

        NodeOperator memory noAfterClean = module.getNodeOperator(defaultNoId);
        assertEq(noAfterClean.enqueuedCount, 0, "enqueued count should be 0 after cleanup");
    }

    function test_cleanDepositQueue_multipleStaleBatches() public assertInvariants {
        ICSModule csm = ICSModule(address(module));
        address nodeOperator2 = nextAddress("NodeOperator2");
        uint256 noId2 = integrationHelpers.addNodeOperator(nodeOperator2, 3);

        vm.prank(nodeOperator);
        module.removeKeys(defaultNoId, 0, initialKeysCount);

        vm.prank(nodeOperator2);
        module.removeKeys(noId2, 0, 3);

        NodeOperator memory no1AfterRemoval = module.getNodeOperator(defaultNoId);
        NodeOperator memory no2AfterRemoval = module.getNodeOperator(noId2);
        assertGt(no1AfterRemoval.enqueuedCount, 0, "NO1 should have stale enqueued keys before cleanup");
        assertGt(no2AfterRemoval.enqueuedCount, 0, "NO2 should have stale enqueued keys before cleanup");

        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertGt(removed, 1, "should remove multiple stale batches");

        NodeOperator memory no1 = module.getNodeOperator(defaultNoId);
        NodeOperator memory no2 = module.getNodeOperator(noId2);
        assertEq(no1.enqueuedCount, 0, "NO1 enqueued should be 0");
        assertEq(no2.enqueuedCount, 0, "NO2 enqueued should be 0");
    }

    function test_cleanDepositQueue_noop_whenNoStale() public assertInvariants {
        ICSModule csm = ICSModule(address(module));
        csm.cleanDepositQueue(type(uint256).max);

        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertEq(removed, 0, "nothing should be removed from clean queue");
    }
}

contract CleanDepositQueueTestCSM is CleanDepositQueueTestBase, CSMIntegrationBase {}

contract CleanDepositQueueTestCSM0x02 is CleanDepositQueueTestBase, CSM0x02IntegrationBase {}
