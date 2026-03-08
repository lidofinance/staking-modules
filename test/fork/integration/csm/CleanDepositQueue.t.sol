// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ICSModule } from "src/interfaces/ICSModule.sol";
import { NodeOperator } from "src/interfaces/IBaseModule.sol";

import { CSMIntegrationBase } from "../common/ModuleTypeBase.sol";

contract CleanDepositQueueTestCSM is CSMIntegrationBase {
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal initialKeysCount = 5;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        assertModuleEnqueuedCount(module);
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(lido, address(accounting), locator.burner());
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        _setUpModule();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        nodeOperator = nextAddress("NodeOperator");
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, initialKeysCount);
    }

    function test_cleanDepositQueue_afterKeyRemoval() public assertInvariants {
        ICSModule csm = ICSModule(address(module));

        NodeOperator memory noBefore = module.getNodeOperator(defaultNoId);
        uint256 enqueuedBefore = noBefore.enqueuedCount;
        assertTrue(enqueuedBefore > 0, "NO should have enqueued keys");

        // Remove all non-deposited keys to make queue entries stale
        uint256 keysToRemove = initialKeysCount;
        vm.prank(nodeOperator);
        module.removeKeys(defaultNoId, 0, keysToRemove);

        NodeOperator memory noAfterRemoval = module.getNodeOperator(defaultNoId);
        assertEq(noAfterRemoval.depositableValidatorsCount, 0, "Depositable count should be 0 after removing all keys");
        assertTrue(noAfterRemoval.enqueuedCount > 0, "NO should have stale enqueued keys before cleanup");

        // Clean the queue — stale entries should be removed
        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertTrue(removed > 0, "Should remove stale batches");

        NodeOperator memory noAfterClean = module.getNodeOperator(defaultNoId);
        assertEq(noAfterClean.enqueuedCount, 0, "Enqueued count should be 0 after cleanup");
    }

    function test_cleanDepositQueue_multipleStaleBatches() public assertInvariants {
        ICSModule csm = ICSModule(address(module));

        // Add a second NO with keys
        address nodeOperator2 = nextAddress("NodeOperator2");
        uint256 noId2 = integrationHelpers.addNodeOperator(nodeOperator2, 3);

        // Remove all keys from both NOs
        vm.prank(nodeOperator);
        module.removeKeys(defaultNoId, 0, initialKeysCount);

        vm.prank(nodeOperator2);
        module.removeKeys(noId2, 0, 3);

        NodeOperator memory no1AfterRemoval = module.getNodeOperator(defaultNoId);
        NodeOperator memory no2AfterRemoval = module.getNodeOperator(noId2);
        assertTrue(no1AfterRemoval.enqueuedCount > 0, "NO1 should have stale enqueued keys before cleanup");
        assertTrue(no2AfterRemoval.enqueuedCount > 0, "NO2 should have stale enqueued keys before cleanup");

        // Clean the queue
        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertTrue(removed > 1, "Should remove multiple stale batches");

        NodeOperator memory no1 = module.getNodeOperator(defaultNoId);
        NodeOperator memory no2 = module.getNodeOperator(noId2);
        assertEq(no1.enqueuedCount, 0, "NO1 enqueued should be 0");
        assertEq(no2.enqueuedCount, 0, "NO2 enqueued should be 0");
    }

    function test_cleanDepositQueue_noop_whenNoStale() public assertInvariants {
        ICSModule csm = ICSModule(address(module));

        // Live forks can already contain stale batches from other operators.
        // First cleanup establishes a deterministic baseline for this test.
        csm.cleanDepositQueue(type(uint256).max);

        // Second cleanup should be a noop.
        (uint256 removed, ) = csm.cleanDepositQueue(type(uint256).max);
        assertEq(removed, 0, "Nothing should be removed from clean queue");
    }
}
