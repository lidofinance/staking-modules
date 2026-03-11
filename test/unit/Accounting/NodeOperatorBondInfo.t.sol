// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BaseTest } from "./_Base.t.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IFeeSplits } from "src/interfaces/IFeeSplits.sol";

contract NodeOperatorBondInfoTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorManagementProperties(user, user, false);
    }

    function test_allZeros() public view {
        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertEq(info.currentBond, 0, "currentBond should be 0");
        assertEq(info.requiredBond, 0, "requiredBond should be 0");
        assertEq(info.lockedBond, 0, "lockedBond should be 0");
        assertEq(info.bondDebt, 0, "bondDebt should be 0");
        assertEq(info.pendingSharesToSplit, 0, "pendingSharesToSplit should be 0");

        _assertConsistency(0);
    }

    function test_nonZeroCurrent() public assertInvariants {
        uint256 bond = 10 ether;
        _deposit({ bond: bond });

        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertApproxEqAbs(info.currentBond, bond, 1 wei, "currentBond should be approximately bond");
        assertEq(info.requiredBond, 0, "requiredBond should be 0");
        assertEq(info.lockedBond, 0, "lockedBond should be 0");
        assertEq(info.bondDebt, 0, "bondDebt should be 0");
        assertEq(info.pendingSharesToSplit, 0, "pendingSharesToSplit should be 0");

        _assertConsistency(0);
    }

    function test_nonZeroLockedBond() public assertInvariants {
        uint256 locked = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, locked);

        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertEq(info.currentBond, 0, "currentBond should be 0");
        assertEq(info.requiredBond, locked, "requiredBond should equal locked bond");
        assertEq(info.lockedBond, locked, "lockedBond should match locked");
        assertEq(info.bondDebt, 0, "bondDebt should be 0");
        assertEq(info.pendingSharesToSplit, 0, "pendingSharesToSplit should be 0");

        _assertConsistency(0);
    }

    function test_nonZeroBondDebt() public assertInvariants {
        uint256 debt = 2 ether;
        vm.prank(address(stakingModule));
        accounting.penalize(0, debt);

        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertEq(info.currentBond, 0, "currentBond should be 0");
        assertEq(info.requiredBond, debt, "requiredBond should be equal to debt when currentBond is 0");
        assertEq(info.lockedBond, 0, "lockedBond should be 0");
        assertEq(info.bondDebt, debt, "bondDebt should match debt");
        assertEq(info.pendingSharesToSplit, 0, "pendingSharesToSplit should be 0");

        _assertConsistency(0);
    }

    function test_nonZeroPendingSharesToSplit() public assertInvariants {
        // Set up fee splits
        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: address(1), share: 5000 });
        vm.prank(user);
        accounting.updateFeeSplits(0, splits, 0, new bytes32[](0));

        // Set up keys so required bond > 0
        mock_getNodeOperatorNonWithdrawnKeys(1);

        // Mint fee shares and distribute (no bond deposited, so claimable = 0, pending stays)
        uint256 feeShares = 154;
        stETH.mintShares(address(feeDistributor), feeShares);
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertEq(
            info.currentBond,
            stETH.getPooledEthByShares(feeShares),
            "currentBond should be stETH.getPooledEthByShares(feeShares)"
        );
        assertEq(info.requiredBond, 2 ether, "requiredBond should match required bond");
        assertEq(info.lockedBond, 0, "lockedBond should be 0");
        assertEq(info.bondDebt, 0, "bondDebt should be 0");
        assertEq(info.pendingSharesToSplit, feeShares, "pendingSharesToSplit should match feeShares");

        _assertConsistency(0);
    }

    function test_allNonZero() public assertInvariants {
        // Deposit bond
        uint256 bond = 5 ether;
        _deposit({ bond: bond });

        // Lock some bond
        uint256 locked = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, locked);

        // Set up fee splits
        IFeeSplits.FeeSplit[] memory splits = new IFeeSplits.FeeSplit[](1);
        splits[0] = IFeeSplits.FeeSplit({ recipient: address(1), share: 5000 });
        vm.prank(user);
        accounting.updateFeeSplits(0, splits, 0, new bytes32[](0));

        // Set up keys so required bond > current (no claimable → pending stays)
        mock_getNodeOperatorNonWithdrawnKeys(10);

        // Distribute rewards
        uint256 feeShares = 154;
        stETH.mintShares(address(feeDistributor), feeShares);
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        // Penalize to create debt
        uint256 currentBond = accounting.getBond(0);
        uint256 debt = 0.5 ether;
        uint256 penalty = currentBond + debt;
        vm.prank(address(stakingModule));
        accounting.penalize(0, penalty);

        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(0);

        assertEq(info.currentBond, 0, "currentBond should be 0");
        assertApproxEqAbs(
            info.requiredBond,
            20 ether + locked + debt,
            1 wei,
            "requiredBond should be approximately 20 ether + locked + debt"
        );
        assertEq(info.lockedBond, locked, "lockedBond should match locked");
        assertApproxEqAbs(info.bondDebt, debt, 2 wei, "bondDebt should be approximately debt");
        assertEq(info.pendingSharesToSplit, feeShares, "pendingSharesToSplit should match feeShares");

        _assertConsistency(0);
    }

    function _assertConsistency(uint256 noId) internal view {
        IAccounting.NodeOperatorBondInfo memory info = accounting.getNodeOperatorBondInfo(noId);
        (uint256 currentBond, uint256 requiredBond) = accounting.getBondSummary(noId);

        assertEq(info.currentBond, currentBond);
        assertEq(info.requiredBond, requiredBond);
        assertEq(info.lockedBond, accounting.getLockedBond(noId));
        assertEq(info.bondDebt, accounting.getBondDebt(noId));
        assertEq(info.pendingSharesToSplit, accounting.getPendingSharesToSplit(noId));
    }
}
