// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { PermitHelper } from "../../../helpers/Permit.sol";
import { ModuleTypeBase, CSMIntegrationBase, CSM0x02IntegrationBase, CuratedIntegrationBase } from "./ModuleTypeBase.sol";

abstract contract AccountingExtrasTestBase is ModuleTypeBase, PermitHelper {
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
        accountingSharesSurplus = lido.sharesOf(address(accounting)) - accounting.totalBondShares();

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.DEFAULT_ADMIN_ROLE(), address(this));
        module.grantRole(module.REPORT_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        module.grantRole(module.SETTLE_GENERAL_DELAYED_PENALTY_ROLE(), address(this));
        vm.stopPrank();

        vm.startPrank(accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0));
        accounting.grantRole(accounting.DEFAULT_ADMIN_ROLE(), address(this));
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

        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(defaultNoId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        proof = tree.getProof(0);
        bytes32 root = tree.root();
        uint256 refSlot = 154;

        vm.prank(feeDistributor.ORACLE());
        feeDistributor.processOracleReport(root, someCIDv0(), someCIDv0(), shares, 0, refSlot);
    }

    function test_customClaimerCanClaimRewards() public assertInvariants {
        address claimer = nextAddress("Claimer");

        vm.prank(nodeOperator);
        accounting.setCustomRewardsClaimer(defaultNoId, claimer);

        // Deposit excess bond
        uint256 amount = 1 ether;
        vm.deal(user, amount);
        vm.prank(user);
        accounting.depositETH{ value: amount }(defaultNoId);

        uint256 noSharesBefore = lido.sharesOf(nodeOperator);

        // Claimer triggers claim; rewards go to NO reward address
        vm.prank(claimer);
        uint256 claimedShares = accounting.claimRewardsStETH(defaultNoId, type(uint256).max, 0, new bytes32[](0));

        assertTrue(claimedShares > 0, "Should claim excess bond shares");
        assertTrue(lido.sharesOf(nodeOperator) > noSharesBefore, "Rewards should go to NO reward address");
    }

    function test_bondDebt_createdOnUncompensatedPenalty() public assertInvariants {
        (uint256 bondBefore, ) = accounting.getBondSummaryShares(defaultNoId);
        uint256 bondEthBefore = accounting.getBond(defaultNoId);

        // Penalty larger than current bond to create debt
        uint256 penaltyAmount = bondEthBefore + 1 ether;
        uint256 additionalFine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(
            accounting.getBondCurveId(defaultNoId)
        );

        module.reportGeneralDelayedPenalty(
            defaultNoId,
            bytes32(abi.encode(1)),
            penaltyAmount - additionalFine,
            "Large penalty"
        );

        module.settleGeneralDelayedPenalty(UintArr(defaultNoId), UintArr(type(uint256).max));

        uint256 debt = accounting.getBondDebt(defaultNoId);
        assertTrue(debt > 0, "Bond debt should be created");

        (uint256 bondAfter, ) = accounting.getBondSummaryShares(defaultNoId);
        assertEq(bondAfter, 0, "Bond shares should be fully consumed");
    }

    function test_bondDebt_coveredByNewDeposit() public assertInvariants {
        uint256 bondEthBefore = accounting.getBond(defaultNoId);

        // Create debt via large penalty
        uint256 penaltyAmount = bondEthBefore + 1 ether;
        uint256 additionalFine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(
            accounting.getBondCurveId(defaultNoId)
        );

        module.reportGeneralDelayedPenalty(
            defaultNoId,
            bytes32(abi.encode(1)),
            penaltyAmount - additionalFine,
            "Large penalty"
        );

        module.settleGeneralDelayedPenalty(UintArr(defaultNoId), UintArr(type(uint256).max));

        uint256 debtBefore = accounting.getBondDebt(defaultNoId);
        assertTrue(debtBefore > 0, "Debt should exist before deposit");

        // New deposit should cover debt
        uint256 depositAmount = debtBefore + 1 ether;
        vm.deal(user, depositAmount);
        vm.prank(user);
        accounting.depositETH{ value: depositAmount }(defaultNoId);

        uint256 debtAfter = accounting.getBondDebt(defaultNoId);
        assertEq(debtAfter, 0, "Debt should be fully covered by deposit");
    }

    function test_bondDebt_coveredByRewardsDistribution() public assertInvariants {
        uint256 bondEthBefore = accounting.getBond(defaultNoId);

        // Create debt via large penalty
        uint256 penaltyAmount = bondEthBefore + 0.5 ether;
        uint256 additionalFine = module.PARAMETERS_REGISTRY().getGeneralDelayedPenaltyAdditionalFine(
            accounting.getBondCurveId(defaultNoId)
        );

        module.reportGeneralDelayedPenalty(
            defaultNoId,
            bytes32(abi.encode(1)),
            penaltyAmount - additionalFine,
            "Large penalty"
        );

        module.settleGeneralDelayedPenalty(UintArr(defaultNoId), UintArr(type(uint256).max));

        uint256 debtBefore = accounting.getBondDebt(defaultNoId);
        assertTrue(debtBefore > 0, "Debt should exist before rewards");

        // Simulate rewards larger than debt
        uint256 rewardAmount = debtBefore + 1 ether;
        (uint256 shares, bytes32[] memory proof) = _simulateRewards(rewardAmount);

        // Claim triggers reward pull which credits bond shares, covering debt
        vm.prank(nodeOperator);
        accounting.claimRewardsStETH(defaultNoId, 0, shares, proof);

        uint256 debtAfter = accounting.getBondDebt(defaultNoId);
        assertEq(debtAfter, 0, "Debt should be covered by distributed rewards");
    }
}

contract AccountingExtrasTestCSM is AccountingExtrasTestBase, CSMIntegrationBase {}

contract AccountingExtrasTestCSM0x02 is AccountingExtrasTestBase, CSM0x02IntegrationBase {}

contract AccountingExtrasTestCurated is AccountingExtrasTestBase, CuratedIntegrationBase {}
