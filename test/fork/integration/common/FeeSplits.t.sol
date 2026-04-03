// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { IFeeSplits } from "src/interfaces/IFeeSplits.sol";

import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract FeeSplitsTestBase is ModuleTypeBase {
    address internal user;
    address internal stranger;
    address internal nodeOperator;
    uint256 internal defaultNoId;
    uint256 internal accountingSharesSurplus;

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

    function setUp() public {
        _setUpModule();
        accountingSharesSurplus = lido.sharesOf(address(accounting)) - accounting.totalBondShares();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        user = nextAddress("User");
        stranger = nextAddress("stranger");
        nodeOperator = nextAddress("NodeOperator");

        uint256 keysCount = 5;
        defaultNoId = integrationHelpers.addNodeOperator(nodeOperator, keysCount);
    }

    function _simulateRewards(uint256 amount) internal returns (uint256 shares, bytes32[] memory proof) {
        vm.startPrank(user);
        vm.deal(user, amount);
        shares = lido.submit{ value: amount }(address(0));
        lido.transferShares(address(feeDistributor), shares);
        vm.stopPrank();

        uint256 previousDistributedShares = feeDistributor.distributedShares(defaultNoId);
        uint256 distributedInReport = shares;
        uint256 cumulativeFeeShares = previousDistributedShares + distributedInReport;
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, cumulativeFeeShares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32 root = tree.root();
        if (root == feeDistributor.treeRoot()) {
            if (cumulativeFeeShares == previousDistributedShares) {
                revert("Zero report shares");
            }
            unchecked {
                --cumulativeFeeShares;
                --distributedInReport;
            }
            tree = new MerkleTree();
            tree.pushLeaf(abi.encode(defaultNoId, cumulativeFeeShares));
            tree.pushLeaf(abi.encode(type(uint64).max, 0));
            root = tree.root();
        }
        proof = tree.getProof(0);
        shares = cumulativeFeeShares;
        uint256 refSlot = 154;

        vm.prank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(root, someCIDv0(), someCIDv0(), distributedInReport, 0, refSlot);
    }

    function _setFeeSplits(IFeeSplits.FeeSplit[] memory splits) internal {
        IFeeSplits.FeeSplit[] memory callSplits = splits;
        vm.prank(nodeOperator);
        accounting.updateFeeSplits(defaultNoId, callSplits, 0, new bytes32[](0));
    }

    function _reportPenaltyToConsumeClaimable(uint256 extraShares, bytes32 key, string memory reason) internal {
        uint256 claimableShares = accounting.getClaimableBondShares(defaultNoId);
        uint256 penaltyAmount = lido.getPooledEthByShares(claimableShares + extraShares) + 1 ether;
        module.reportGeneralDelayedPenalty(defaultNoId, key, penaltyAmount, reason);
    }

    function test_pullAndSplitFeeRewards() public assertInvariants {
        address recipient = nextAddress("SplitRecipient");
        uint256 splitShare = 5000; // 50%

        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: recipient, share: splitShare });
        _setFeeSplits(splits);

        uint256 amount = 1 ether;
        (uint256 shares, bytes32[] memory proof) = _simulateRewards(amount);

        uint256 recipientSharesBefore = lido.sharesOf(recipient);
        uint256 accountingBondBefore = accounting.getBondShares(defaultNoId);

        accounting.pullAndSplitFeeRewards(defaultNoId, shares, proof);

        uint256 recipientSharesAfter = lido.sharesOf(recipient);
        uint256 pendingAfter = accounting.getPendingSharesToSplit(defaultNoId);

        uint256 expectedRecipientShares = (shares * splitShare) / 10_000;
        assertEq(
            recipientSharesAfter - recipientSharesBefore,
            expectedRecipientShares,
            "Recipient should receive correct share"
        );
        assertEq(pendingAfter, 0, "Pending shares should be 0 after distribution");

        uint256 accountingBondAfter = accounting.getBondShares(defaultNoId);
        // Bond increased by distributed shares minus the transferred split shares
        uint256 transferredShares = recipientSharesAfter - recipientSharesBefore;
        assertEq(
            accountingBondAfter,
            accountingBondBefore + shares - transferredShares,
            "Bond should increase by rewards minus split transfers"
        );
    }

    function test_claimRewardsStETH_withSplits() public assertInvariants {
        address recipient = nextAddress("SplitRecipient");
        uint256 splitShare = 5000; // 50%

        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: recipient, share: splitShare });
        _setFeeSplits(splits);

        uint256 amount = 1 ether;
        (uint256 shares, bytes32[] memory proof) = _simulateRewards(amount);

        uint256 recipientSharesBefore = lido.sharesOf(recipient);
        uint256 noSharesBefore = lido.sharesOf(nodeOperator);

        vm.prank(nodeOperator);
        accounting.claimRewardsStETH(defaultNoId, type(uint256).max, shares, proof);

        uint256 recipientSharesAfter = lido.sharesOf(recipient);
        uint256 noSharesAfter = lido.sharesOf(nodeOperator);

        uint256 expectedRecipientShares = (shares * splitShare) / 10_000;
        assertEq(
            recipientSharesAfter - recipientSharesBefore,
            expectedRecipientShares,
            "Recipient should receive correct split via claim path"
        );
        assertTrue(noSharesAfter > noSharesBefore, "NO should receive remaining excess via claim");
        assertEq(accounting.getPendingSharesToSplit(defaultNoId), 0, "Pending shares should be 0 after claim");
    }

    function test_updateFeeSplits_blockedWhilePending_unblockAndUpdate() public assertInvariants {
        address recipient = nextAddress("SplitRecipient");
        uint256 splitShare = 5000;

        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: recipient, share: splitShare });
        _setFeeSplits(splits);

        uint256 amount = 1 ether;
        (uint256 shares, bytes32[] memory proof) = _simulateRewards(amount);

        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        _reportPenaltyToConsumeClaimable(shares, bytes32(abi.encode(1)), "block update while pending");

        accounting.pullAndSplitFeeRewards(defaultNoId, shares, proof);
        uint256 pending = accounting.getPendingSharesToSplit(defaultNoId);
        assertTrue(pending > 0, "Pending shares should exist");

        // Rewards are already pulled, so update must be blocked by pending shares.
        address newRecipient = nextAddress("NewRecipient");
        IFeeSplits.FeeSplit[] memory newSplits = new IFeeSplits.FeeSplit[](1);
        newSplits[0] = IFeeSplits.FeeSplit({ recipient: newRecipient, share: 3000 });

        vm.prank(nodeOperator);
        vm.expectRevert(IFeeSplits.PendingSharesExist.selector);
        accounting.updateFeeSplits(defaultNoId, newSplits, shares, proof);

        (uint256 current, uint256 required) = accounting.getBondSummaryShares(defaultNoId);
        uint256 topUpShares = pending + 1;
        if (required > current) {
            topUpShares += required - current;
        }

        uint256 topUp = lido.getPooledEthByShares(topUpShares) + 1 ether;
        vm.deal(nodeOperator, topUp);
        vm.prank(nodeOperator);
        accounting.depositETH{ value: topUp }(defaultNoId);

        accounting.pullAndSplitFeeRewards(defaultNoId, 0, new bytes32[](0));
        assertEq(accounting.getPendingSharesToSplit(defaultNoId), 0, "Pending shares should be zero after split");

        // Now update should succeed
        vm.prank(nodeOperator);
        accounting.updateFeeSplits(defaultNoId, newSplits, shares, proof);

        IFeeSplits.FeeSplit[] memory stored = accounting.getFeeSplits(defaultNoId);
        assertEq(stored.length, 1, "Should have 1 split");
        assertEq(stored[0].recipient, newRecipient, "Recipient should be updated");
        assertEq(stored[0].share, 3000, "Share should be updated");
    }

    function test_splitUsesAllocationDate_andSurvivesPenaltyUntilLaterClaim() public assertInvariants {
        address recipient = nextAddress("SplitRecipient");
        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: recipient, share: 5000 });
        _setFeeSplits(splits);

        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));

        (uint256 shares1, bytes32[] memory proof1) = _simulateRewards(5 ether);
        _reportPenaltyToConsumeClaimable(shares1, bytes32(abi.encode(1)), "consume claimable before allocation");

        uint256 recipientBefore = lido.sharesOf(recipient);
        accounting.pullAndSplitFeeRewards(defaultNoId, shares1, proof1);
        uint256 pending1 = accounting.getPendingSharesToSplit(defaultNoId);
        assertTrue(pending1 > 0, "Pending shares should be created at allocation");
        assertEq(
            lido.sharesOf(recipient),
            recipientBefore,
            "Recipient should not receive shares while claimable is zero"
        );

        module.reportGeneralDelayedPenalty(defaultNoId, bytes32(abi.encode(2)), 1 ether, "test penalty");
        assertEq(
            accounting.getClaimableBondShares(defaultNoId),
            0,
            "Penalty should keep current claimable shares at zero"
        );
        assertEq(
            accounting.getPendingSharesToSplit(defaultNoId),
            pending1,
            "Penalty must not reduce pending split amount"
        );

        accounting.pullAndSplitFeeRewards(defaultNoId, shares1, proof1);
        assertEq(
            accounting.getPendingSharesToSplit(defaultNoId),
            pending1,
            "Pending should stay unchanged when no claimable shares exist"
        );
        assertEq(
            lido.sharesOf(recipient),
            recipientBefore,
            "Recipient should still not receive shares while claimable is zero"
        );

        (uint256 current, uint256 required) = accounting.getBondSummaryShares(defaultNoId);
        uint256 topUpShares = pending1 + 1;
        if (required > current) {
            topUpShares += required - current;
        }

        uint256 topUp = lido.getPooledEthByShares(topUpShares) + 1 ether;
        vm.deal(nodeOperator, topUp);
        vm.prank(nodeOperator);
        accounting.depositETH{ value: topUp }(defaultNoId);

        uint256 pendingBeforeClaim = accounting.getPendingSharesToSplit(defaultNoId);
        vm.prank(nodeOperator);
        accounting.claimRewardsStETH(defaultNoId, type(uint256).max, shares1, proof1);

        assertTrue(
            lido.sharesOf(recipient) > recipientBefore,
            "Pending rewards should be split later during claim operations"
        );
        assertLt(
            accounting.getPendingSharesToSplit(defaultNoId),
            pendingBeforeClaim,
            "Pending shares should decrease after later split"
        );
    }

    function test_removeFeeSplits() public assertInvariants {
        address recipient = nextAddress("SplitRecipient");
        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: recipient, share: 5000 });
        _setFeeSplits(splits);

        assertTrue(accounting.hasSplits(defaultNoId), "Should have splits");

        // With active splits, updateFeeSplits requires a valid proof path.
        // Pull rewards first so cumulative shares can be reused to prove zero undistributed delta.
        (uint256 initialShares, bytes32[] memory initialProof) = _simulateRewards(1 ether);
        accounting.pullAndSplitFeeRewards(defaultNoId, initialShares, initialProof);

        // Remove splits by setting empty array
        IFeeSplits.FeeSplit[] memory emptySplits = new IFeeSplits.FeeSplit[](0);
        vm.prank(nodeOperator);
        accounting.updateFeeSplits(defaultNoId, emptySplits, initialShares, initialProof);

        IFeeSplits.FeeSplit[] memory stored = accounting.getFeeSplits(defaultNoId);
        assertEq(stored.length, 0, "Splits should be removed");
        assertFalse(accounting.hasSplits(defaultNoId), "hasSplits should be false");

        // Simulate new rewards and claim — all goes to NO
        uint256 amount = 1 ether;
        (uint256 shares, bytes32[] memory proof) = _simulateRewards(amount);

        uint256 recipientSharesBefore = lido.sharesOf(recipient);
        uint256 noSharesBefore = lido.sharesOf(nodeOperator);

        vm.prank(nodeOperator);
        accounting.claimRewardsStETH(defaultNoId, type(uint256).max, shares, proof);

        assertEq(
            lido.sharesOf(recipient),
            recipientSharesBefore,
            "Recipient should not receive any shares after splits removed"
        );
        assertTrue(lido.sharesOf(nodeOperator) > noSharesBefore, "NO should receive all rewards");
    }
}

contract FeeSplitsTestCSM is FeeSplitsTestBase, CSMIntegrationBase {}

contract FeeSplitsTestCSM0x02 is FeeSplitsTestBase, CSM0x02IntegrationBase {}

contract FeeSplitsTestCurated is FeeSplitsTestBase, CuratedIntegrationBase {}
