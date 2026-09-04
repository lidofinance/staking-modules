// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BaseTest } from "./_Base.t.sol";

// Bond claims are restricted until all the slashed validators are reported as withdrawn and the losses are compensated.
contract BondClaimRestrictionTest is BaseTest {
    uint256 internal constant KEYS_COUNT = 16;
    uint256 internal constant REQUIRED_BOND = 32 ether; // 2 ether per key
    uint256 internal constant EXCESS_BOND = 8 ether;

    bytes32[] internal proof;

    function setUp() public override {
        super.setUp();

        proof = new bytes32[](1);
        mock_getNodeOperatorManagementProperties(user, user, false);
        _operator({ ongoing: KEYS_COUNT, withdrawn: 0 });
        _deposit({ bond: REQUIRED_BOND + EXCESS_BOND });
    }

    function test_isBondClaimRestricted() public assertInvariants {
        assertFalse(accounting.isBondClaimRestricted(0));

        mock_getNodeOperatorUnresolvedSlashedValidators(1);
        assertTrue(accounting.isBondClaimRestricted(0));
    }

    function test_getClaimableBondShares_notRestricted() public assertInvariants {
        assertApproxEqAbs(
            accounting.getClaimableBondShares(0),
            stETH.getSharesByPooledEth(EXCESS_BOND),
            1 wei,
            "excess bond should be claimable without unresolved slashings"
        );
    }

    function test_getClaimableBondShares_zeroWhenRestricted() public assertInvariants {
        mock_getNodeOperatorUnresolvedSlashedValidators(1);

        assertEq(accounting.getClaimableBondShares(0), 0, "nothing should be claimable while restricted");
    }

    function test_getClaimableRewardsAndBondShares_zeroWhenRestricted() public assertInvariants {
        uint256 feeShares = _fundRewards({ fee: 0.1 ether });
        mock_getNodeOperatorUnresolvedSlashedValidators(1);

        assertEq(
            accounting.getClaimableRewardsAndBondShares(0, feeShares, proof),
            0,
            "neither rewards nor bond should be claimable while restricted"
        );
    }

    function test_claimRewardsStETH_claimsNothingButPullsRewardsWhenRestricted() public assertInvariants {
        uint256 feeShares = _fundRewards({ fee: 0.1 ether });
        mock_getNodeOperatorUnresolvedSlashedValidators(1);

        uint256 bondSharesBefore = accounting.getBondShares(0);

        vm.prank(user);
        uint256 claimedShares = accounting.claimRewardsStETH(0, UINT256_MAX, feeShares, proof);

        assertEq(claimedShares, 0, "nothing should be claimed while restricted");
        assertEq(accounting.getBondShares(0), bondSharesBefore + feeShares, "rewards should be pulled to the bond");
        assertEq(stETH.sharesOf(user), 0, "nothing should be transferred to the Node Operator");
    }

    function test_claimRewardsStETH_claimableOnceSlashedValidatorWithdrawalReported() public assertInvariants {
        mock_getNodeOperatorUnresolvedSlashedValidators(1);
        assertEq(accounting.getClaimableBondShares(0), 0);

        // The withdrawal report of the slashed validator resolves the slashing.
        mock_getNodeOperatorUnresolvedSlashedValidators(0);

        vm.prank(user);
        uint256 claimedShares = accounting.claimRewardsStETH(0, UINT256_MAX, 0, proof);

        assertApproxEqAbs(claimedShares, stETH.getSharesByPooledEth(EXCESS_BOND), 1 wei, "excess bond claimed");
    }

    function test_claimableStaysZeroUntilLossesCompensated() public assertInvariants {
        mock_getNodeOperatorUnresolvedSlashedValidators(1);

        // The losses exceed the bond, so the uncovered part becomes the bond debt.
        uint256 uncoveredLosses = 1 ether;
        _penalize({ amount: accounting.getBond(0) + uncoveredLosses });
        assertApproxEqAbs(accounting.getBondDebt(0), uncoveredLosses, 1 wei, "uncovered losses become the bond debt");

        // The withdrawal report lifts the restriction, but the losses are not compensated yet.
        mock_getNodeOperatorUnresolvedSlashedValidators(0);
        assertEq(accounting.getClaimableBondShares(0), 0, "nothing to claim until the debt is compensated");

        // A partial compensation is fully spent on the debt.
        _deposit({ bond: uncoveredLosses / 2 });
        assertApproxEqAbs(accounting.getBondDebt(0), uncoveredLosses / 2, 2 wei, "debt should be partially covered");
        assertEq(accounting.getClaimableBondShares(0), 0, "nothing to claim until the debt is compensated");

        _deposit({ bond: uncoveredLosses / 2 + REQUIRED_BOND + EXCESS_BOND });
        assertEq(accounting.getBondDebt(0), 0, "debt should be fully covered");
        // Tolerance accounts for the repeated ETH/shares conversions above.
        assertApproxEqAbs(
            accounting.getClaimableBondShares(0),
            stETH.getSharesByPooledEth(EXCESS_BOND),
            4 wei,
            "excess bond should be claimable once the losses are compensated"
        );
    }

    function test_claimRewardsWstETH_claimsNothingWhenRestricted() public assertInvariants {
        mock_getNodeOperatorUnresolvedSlashedValidators(1);
        uint256 bondSharesBefore = accounting.getBondShares(0);

        vm.prank(user);
        uint256 claimedWstETH = accounting.claimRewardsWstETH(0, UINT256_MAX, 0, proof);

        assertEq(claimedWstETH, 0, "nothing should be claimed while restricted");
        assertEq(accounting.getBondShares(0), bondSharesBefore, "bond should be intact");
    }

    function test_claimRewardsUnstETH_claimsNothingWhenRestricted() public assertInvariants {
        mock_getNodeOperatorUnresolvedSlashedValidators(1);
        uint256 bondSharesBefore = accounting.getBondShares(0);

        vm.prank(user);
        uint256 requestId = accounting.claimRewardsUnstETH(0, UINT256_MAX, 0, proof);

        assertEq(requestId, 0, "nothing should be claimed while restricted");
        assertEq(accounting.getBondShares(0), bondSharesBefore, "bond should be intact");
    }

    function _fundRewards(uint256 fee) internal returns (uint256 shares) {
        vm.deal(address(feeDistributor), fee);
        vm.prank(address(feeDistributor));
        shares = stETH.submit{ value: fee }(address(0));
    }

    function _penalize(uint256 amount) internal {
        vm.prank(address(stakingModule));
        accounting.penalize(0, amount);
    }
}
