// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { PermitHelper } from "../../helpers/Permit.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { MerkleTree } from "../../helpers/MerkleTree.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";

contract ClaimRewardsTest is
    Test,
    Utilities,
    PermitHelper,
    DeploymentFixtures,
    InvariantAsserts
{
    address internal user;
    address internal stranger;
    address internal nodeOperator;
    uint256 internal defaultNoId;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        uint256 noCount = module.getNodeOperatorsCount();
        assertModuleKeys(module);
        assertModuleEnqueuedCount(module);
        assertModuleUnusedStorageSlots(module);
        assertAccountingTotalBondShares(noCount, lido, accounting);
        assertAccountingBurnerApproval(
            lido,
            address(accounting),
            locator.burner()
        );
        assertAccountingUnusedStorageSlots(accounting);
        assertFeeDistributorClaimableShares(lido, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        user = nextAddress("User");
        stranger = nextAddress("stranger");
        nodeOperator = nextAddress("NodeOperator");

        uint256 keysCount = 5;
        (bytes memory keys, bytes memory signatures) = keysSignatures(
            keysCount
        );
        uint256 amount = accounting.getBondAmountByKeysCount(keysCount, 0);
        vm.deal(nodeOperator, amount);

        vm.prank(nodeOperator);
        defaultNoId = permissionlessGate.addNodeOperatorETH{ value: amount }({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            referrer: address(0)
        });
    }

    function test_claimExcessBondStETH() public assertInvariants {
        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);

        accounting.depositETH{ value: amount }(defaultNoId);
        vm.stopPrank();

        uint256 noSharesBefore = lido.sharesOf(nodeOperator);
        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesBefore = accounting.getBondShares(
            defaultNoId
        );

        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );

        uint256 excessBondShares = current > required ? current - required : 0;
        assertTrue(excessBondShares > 0, "Excess bond should be > 0");

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsStETH_excessBond");
        uint256 claimedShares = accounting.claimRewardsStETH(
            defaultNoId,
            type(uint256).max,
            0,
            new bytes32[](0)
        );
        vm.stopSnapshotGas();

        uint256 noSharesAfter = lido.sharesOf(nodeOperator);
        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesAfter = accounting.getBondShares(
            defaultNoId
        );
        uint256 accountingTotalBondSharesAfter = accounting.totalBondShares();

        assertEq(
            claimedShares,
            excessBondShares,
            "Claimed shares should be equal to excess bond"
        );
        assertEq(
            noSharesAfter,
            noSharesBefore + excessBondShares,
            "Node Operator stETH shares should be increased by excess bond"
        );
        assertEq(
            accountingNOBondSharesAfter,
            accountingNOBondSharesBefore -
                (accountingSharesBefore - accountingSharesAfter),
            "NO bond shares should be decreased by real transferred shares"
        );
        assertEq(
            accountingTotalBondSharesAfter,
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }

    function test_claimExcessBondWstETH() public assertInvariants {
        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);

        accounting.depositETH{ value: amount }(defaultNoId);
        vm.stopPrank();

        uint256 balanceBefore = wstETH.balanceOf(nodeOperator);
        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesBefore = accounting.getBondShares(
            defaultNoId
        );

        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );

        uint256 excessBondShares = current > required ? current - required : 0;
        assertTrue(excessBondShares > 0, "Excess bond should be > 0");

        uint256 excessBondWstETH = wstETH.getWstETHByStETH(
            lido.getPooledEthByShares(excessBondShares)
        );

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsWstETH_excessBond");
        uint256 claimedWstETH = accounting.claimRewardsWstETH(
            defaultNoId,
            type(uint256).max,
            0,
            new bytes32[](0)
        );
        vm.stopSnapshotGas();

        uint256 balanceAfter = wstETH.balanceOf(nodeOperator);
        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesAfter = accounting.getBondShares(
            defaultNoId
        );
        uint256 accountingTotalBondSharesAfter = accounting.totalBondShares();

        assertEq(
            claimedWstETH,
            excessBondWstETH,
            "Claimed WstETH should be equal to excess bond WstETH"
        );
        assertEq(
            balanceAfter,
            balanceBefore + excessBondWstETH,
            "Node Operator wstETH balance should be increased by excess bond"
        );
        assertEq(
            accountingNOBondSharesAfter,
            accountingNOBondSharesBefore -
                (accountingSharesBefore - accountingSharesAfter),
            "NO bond shares should be decreased by real transferred shares"
        );
        assertEq(
            accountingTotalBondSharesAfter,
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }

    function test_requestExcessBondETH() public assertInvariants {
        IWithdrawalQueue wq = IWithdrawalQueue(locator.withdrawalQueue());
        uint256[] memory requestsIdsBefore = wq.getWithdrawalRequests(
            nodeOperator
        );
        assertEq(
            requestsIdsBefore.length,
            0,
            "should be no wd requests for the Node Operator"
        );

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);

        accounting.depositETH{ value: amount }(defaultNoId);
        vm.stopPrank();

        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesBefore = accounting.getBondShares(
            defaultNoId
        );

        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );

        uint256 excessBondShares = current > required ? current - required : 0;
        assertTrue(excessBondShares > 0, "Excess bond should be > 0");

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsUnstETH_excessBond");
        uint256 claimedRequestId = accounting.claimRewardsUnstETH(
            defaultNoId,
            type(uint256).max,
            0,
            new bytes32[](0)
        );
        vm.stopSnapshotGas();

        uint256[] memory requestsIdsAfter = wq.getWithdrawalRequests(
            nodeOperator
        );
        assertEq(
            requestsIdsAfter.length,
            1,
            "should be 1 wd request for the Node Operator"
        );

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = wq
            .getWithdrawalStatus(requestsIdsAfter);

        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));
        uint256 accountingNOBondSharesAfter = accounting.getBondShares(
            defaultNoId
        );
        uint256 accountingTotalBondSharesAfter = accounting.totalBondShares();

        assertEq(
            claimedRequestId,
            requestsIdsAfter[0],
            "Claimed request should be equal to found request"
        );
        assertEq(
            statuses[0].amountOfStETH,
            lido.getPooledEthByShares(excessBondShares),
            "Withdrawal request should be equal to excess bond"
        );
        assertEq(
            accountingNOBondSharesAfter,
            accountingNOBondSharesBefore -
                (accountingSharesBefore - accountingSharesAfter),
            "NO bond shares should be decreased by real transferred shares"
        );
        assertEq(
            accountingTotalBondSharesAfter,
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }

    function test_claimRewardsStETH() public assertInvariants {
        uint256 noSharesBefore = lido.sharesOf(nodeOperator);
        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));
        uint256 amount = 1 ether;

        // Supply funds to feeDistributor
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.transferShares(address(feeDistributor), shares);
        vm.stopPrank();

        // Prepare and submit report data
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();
        uint256 refSlot = 154;

        vm.prank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsStETH_proof");
        uint256 claimedShares = accounting.claimRewardsStETH(
            defaultNoId,
            type(uint256).max,
            shares,
            proof
        );
        vm.stopSnapshotGas();

        uint256 noSharesAfter = lido.sharesOf(nodeOperator);
        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));

        assertEq(
            claimedShares,
            shares,
            "Claimed shares should be equal to distributed shares"
        );
        assertEq(
            noSharesAfter,
            noSharesBefore +
                (accountingSharesBefore + shares - accountingSharesAfter),
            "Node Operator stETH shares should be increased by real shares"
        );
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );
        assertEq(current, required, "NO bond shares should be equal required");
        assertEq(
            accounting.totalBondShares(),
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }

    function test_claimRewardsWstETH() public assertInvariants {
        uint256 balanceBefore = wstETH.balanceOf(nodeOperator);
        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));
        uint256 amount = 1 ether;

        // Supply funds to feeDistributor
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.transferShares(address(feeDistributor), shares);
        vm.stopPrank();

        uint256 distributedWstETHAmount = wstETH.getWstETHByStETH(
            lido.getPooledEthByShares(shares)
        );

        // Prepare and submit report data
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();
        uint256 refSlot = 154;

        vm.prank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsWstETH_proof");
        uint256 claimedWstETHAmount = accounting.claimRewardsWstETH(
            defaultNoId,
            type(uint256).max,
            shares,
            proof
        );
        vm.stopSnapshotGas();

        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));

        assertEq(claimedWstETHAmount, distributedWstETHAmount);
        assertEq(
            wstETH.balanceOf(nodeOperator),
            balanceBefore +
                (accountingSharesBefore + shares - accountingSharesAfter),
            "Node Operator wstETH balance should be increased by real rewards"
        );
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );
        // Approx due to wstETH claim mechanics shares -> stETH -> wstETH
        assertApproxEqAbs(
            current,
            required,
            2 wei,
            "NO bond shares should be equal required"
        );
        assertEq(
            accounting.totalBondShares(),
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }

    function test_requestRewardsETH() public assertInvariants {
        IWithdrawalQueue wq = IWithdrawalQueue(locator.withdrawalQueue());
        uint256[] memory requestsIdsBefore = wq.getWithdrawalRequests(
            nodeOperator
        );
        assertEq(
            requestsIdsBefore.length,
            0,
            "should be no wd requests for the Node Operator"
        );

        uint256 amount = 1 ether;

        // Supply funds to feeDistributor
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.transferShares(address(feeDistributor), shares);
        vm.stopPrank();

        // Prepare and submit report data
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();
        uint256 refSlot = 154;

        vm.prank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        uint256 accountingSharesBefore = lido.sharesOf(address(accounting));

        vm.prank(nodeOperator);
        vm.startSnapshotGas("Accounting.claimRewardsUnstETH_proof");
        uint256 claimedRequestId = accounting.claimRewardsUnstETH(
            defaultNoId,
            type(uint256).max,
            shares,
            proof
        );
        vm.stopSnapshotGas();

        uint256[] memory requestsIdsAfter = wq.getWithdrawalRequests(
            nodeOperator
        );
        assertEq(
            requestsIdsAfter.length,
            1,
            "should be 1 wd request for the Node Operator"
        );

        IWithdrawalQueue.WithdrawalRequestStatus[] memory statuses = wq
            .getWithdrawalStatus(requestsIdsAfter);

        assertEq(
            claimedRequestId,
            requestsIdsAfter[0],
            "Claimed request should be equal to found request"
        );
        uint256 accountingSharesAfter = lido.sharesOf(address(accounting));
        assertApproxEqAbs(
            statuses[0].amountOfStETH,
            lido.getPooledEthByShares(
                (accountingSharesBefore + shares) - accountingSharesAfter
            ),
            2 wei,
            "Withdrawal request should be equal to real rewards"
        );
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            defaultNoId
        );
        // Approx due to unstETH claim mechanics shares -> stETH -> unstETH
        assertApproxEqAbs(
            current,
            required,
            2 wei,
            "NO bond shares should be equal required"
        );
        assertEq(
            accounting.totalBondShares(),
            accountingSharesAfter,
            "Total bond shares should be equal to real shares"
        );
    }
}
