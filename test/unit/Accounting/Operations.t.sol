// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Accounting } from "src/Accounting.sol";
import { IBurner } from "src/interfaces/IBurner.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { IFeeSplits, FeeSplits } from "src/lib/FeeSplits.sol";

import { ERC20Testable } from "../../helpers/ERCTestable.sol";

import { BaseTest } from "./_Base.t.sol";

// Combined operational tests: asset recovery, fees, penalties, scenarios

contract AssetRecovererTest is BaseTest {
    address recoverer;

    function setUp() public override {
        super.setUp();

        recoverer = nextAddress("RECOVERER");

        vm.startPrank(admin);
        accounting.grantRole(accounting.RECOVERER_ROLE(), recoverer);
        vm.stopPrank();
    }

    function test_recovererRole() public {
        bytes32 role = accounting.RECOVERER_ROLE();
        vm.prank(admin);
        accounting.grantRole(role, address(1337));

        vm.prank(address(1337));
        accounting.recoverEther();
    }

    function test_recovererRole_RevertWhen_Unauthorized() public {
        expectRoleRevert(stranger, accounting.RECOVERER_ROLE());
        vm.prank(stranger);
        accounting.recoverEther();
    }

    function test_recoverEtherHappyPath() public assertInvariants {
        uint256 amount = 42 ether;
        vm.deal(address(accounting), amount);

        vm.expectEmit(address(accounting));
        emit IAssetRecovererLib.EtherRecovered(recoverer, amount);

        vm.prank(recoverer);
        accounting.recoverEther();

        assertEq(address(accounting).balance, 0);
        assertEq(address(recoverer).balance, amount);
    }

    function test_recoverERC20HappyPath() public assertInvariants {
        ERC20Testable token = new ERC20Testable();
        token.mint(address(accounting), 1000);

        vm.prank(recoverer);
        vm.expectEmit(address(accounting));
        emit IAssetRecovererLib.ERC20Recovered(address(token), recoverer, 1000);
        accounting.recoverERC20(address(token), 1000);

        assertEq(token.balanceOf(address(accounting)), 0);
        assertEq(token.balanceOf(recoverer), 1000);
    }

    function test_recoverERC20_RevertWhen_Unauthorized() public {
        ERC20Testable token = new ERC20Testable();
        token.mint(address(accounting), 1000);

        expectRoleRevert(stranger, accounting.RECOVERER_ROLE());
        vm.prank(stranger);
        accounting.recoverERC20(address(token), 1000);
    }

    function test_recoverERC20_RevertWhen_StETH() public {
        vm.prank(recoverer);
        vm.expectRevert(IAssetRecovererLib.NotAllowedToRecover.selector);
        accounting.recoverERC20(address(stETH), 1000);
    }

    function test_recoverStETHShares() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.deal(address(stakingModule), 2 ether);
        vm.startPrank(address(stakingModule));
        stETH.submit{ value: 2 ether }(address(0));
        accounting.depositStETH(
            address(stakingModule),
            0,
            1 ether,
            IAccounting.PermitInput({
                value: 1 ether,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );
        vm.stopPrank();

        uint256 sharesBefore = stETH.sharesOf(address(accounting));
        uint256 sharesToRecover = stETH.getSharesByPooledEth(0.3 ether);
        stETH.mintShares(address(accounting), sharesToRecover);

        vm.prank(recoverer);
        vm.expectEmit(address(accounting));
        emit IAssetRecovererLib.StETHSharesRecovered(
            recoverer,
            sharesToRecover
        );
        accounting.recoverStETHShares();

        assertEq(stETH.sharesOf(address(accounting)), sharesBefore);
        assertEq(stETH.sharesOf(recoverer), sharesToRecover);
    }

    function test_recoverStETHShares_RevertWhen_Unauthorized() public {
        expectRoleRevert(stranger, accounting.RECOVERER_ROLE());
        vm.prank(stranger);
        accounting.recoverStETHShares();
    }
}

contract ChargeFeeTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
        vm.deal(address(stakingModule), 32 ether);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, 0);
    }

    function test_chargeFee() public assertInvariants {
        uint256 bond = accounting.getBond(0);
        uint256 amountToCharge = bond / 2; // charge half of the bond
        uint256 shares = stETH.getSharesByPooledEth(amountToCharge);
        uint256 bondSharesBefore = accounting.getBondShares(0);

        vm.prank(address(stakingModule));
        bool fullyCharged = accounting.chargeFee(0, amountToCharge);
        uint256 bondSharesAfter = accounting.getBondShares(0);

        assertEq(
            bondSharesAfter,
            bondSharesBefore - shares,
            "bond shares should be decreased by penalty"
        );
        assertEq(accounting.totalBondShares(), bondSharesAfter);
        assertTrue(fullyCharged, "should be fully charged");
    }

    function test_chargeFee_onInsufficientBond() public assertInvariants {
        uint256 bond = accounting.getBond(0);
        uint256 amountToCharge = bond + 1 ether; // charge more than bond

        vm.prank(address(stakingModule));
        bool fullyCharged = accounting.chargeFee(0, amountToCharge);
        uint256 bondSharesAfter = accounting.getBondShares(0);

        assertEq(
            bondSharesAfter,
            0,
            "bond shares should be zero after charging more than bond"
        );
        assertEq(
            accounting.totalBondShares(),
            0,
            "total bond shares should be zero"
        );
        assertFalse(fullyCharged, "should no be fully charged");
    }

    function test_chargeFee_RevertWhen_SenderIsNotModule() public {
        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.chargeFee(0, 20);
    }
}

contract FeeSplitsTest is BaseTest {
    function test_setFeeSplits() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);

        vm.expectEmit(address(accounting));
        emit IFeeSplits.FeeSplitsSet(0, splits);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        IAccounting.FeeSplit[] memory actual = accounting.getFeeSplits(0);
        assertEq(actual.length, splits.length);
        for (uint256 i = 0; i < splits.length; i++) {
            assertEq(actual[i].recipient, splits[i].recipient);
            assertEq(actual[i].share, splits[i].share);
        }
    }

    function test_setFeeSplits_ZeroLength() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](0);
        mock_getNodeOperatorOwner(user);

        vm.expectEmit(address(accounting));
        emit IFeeSplits.FeeSplitsSet(0, splits);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        IAccounting.FeeSplit[] memory actual = accounting.getFeeSplits(0);
        assertEq(actual.length, 0);
    }

    function test_setFeeSplits_revertWhen_SenderIsNotEligible() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IAccounting.SenderIsNotEligible.selector);
        vm.prank(stranger);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);
    }

    function test_setFeeSplits_revertWhen_TooManySplits() public {
        uint256 length = FeeSplits.MAX_FEE_SPLITS + 1;
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](
            length
        );
        for (uint256 i = 0; i < splits.length; i++) {
            splits[i].recipient = nextAddress();
            splits[i].share = 1000;
        }
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IFeeSplits.TooManySplits.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);
    }

    function test_setFeeSplits_revertWhen_TooManySplitShares() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 8000
        });
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IFeeSplits.TooManySplitShares.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);
    }

    function test_setFeeSplits_revertWhen_ZeroSplitRecipient() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: address(0),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IFeeSplits.ZeroSplitRecipient.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);
    }

    function test_setFeeSplits_revertWhen_ZeroSplitShare() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({ recipient: address(2), share: 0 });
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IFeeSplits.ZeroSplitShare.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);
    }

    function test_setFeeSplits_revertWhen_PendingShares() public {
        IAccounting.FeeSplit[]
            memory initialSplits = new IAccounting.FeeSplit[](1);
        initialSplits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), initialSplits);

        uint256 feeShares = 1 ether;
        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        // Have some non-withdrawn keys that requires claimable shares to be > 0
        mock_getNodeOperatorNonWithdrawnKeys(1);

        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        // Now try to set new splits - should fail due to pending shares
        IAccounting.FeeSplit[] memory newSplits = new IAccounting.FeeSplit[](1);
        newSplits[0] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 3000
        });

        vm.expectRevert(IFeeSplits.PendingSharesExist.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), newSplits);
    }

    function test_setFeeSplits_revertWhen_UndistributedFees() public {
        uint256 feeShares = 1 ether;
        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorOwner(user);

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 5000
        });

        vm.expectRevert(IFeeSplits.UndistributedSharesExist.selector);
        vm.prank(user);
        accounting.setFeeSplits(0, feeShares, new bytes32[](0), splits);
    }

    function test_setFeeSplits_updateExistingSplits() public {
        IAccounting.FeeSplit[]
            memory initialSplits = new IAccounting.FeeSplit[](2);
        initialSplits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        initialSplits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 2000
        });
        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), initialSplits);

        IAccounting.FeeSplit[] memory current = accounting.getFeeSplits(0);
        assertEq(current.length, 2);
        assertEq(current[0].recipient, address(1));
        assertEq(current[0].share, 3000);

        IAccounting.FeeSplit[] memory newSplits = new IAccounting.FeeSplit[](1);
        newSplits[0] = IAccounting.FeeSplit({
            recipient: address(3),
            share: 4000
        });

        vm.expectEmit(address(accounting));
        emit IFeeSplits.FeeSplitsSet(0, newSplits);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), newSplits);

        IAccounting.FeeSplit[] memory updated = accounting.getFeeSplits(0);
        assertEq(updated.length, 1);
        assertEq(updated[0].recipient, address(3));
        assertEq(updated[0].share, 4000);
    }

    function test_setFeeSplits_removingSplits() public {
        IAccounting.FeeSplit[]
            memory initialSplits = new IAccounting.FeeSplit[](2);
        initialSplits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 3000
        });
        initialSplits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 2000
        });
        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), initialSplits);

        IAccounting.FeeSplit[] memory current = accounting.getFeeSplits(0);
        assertEq(current.length, 2);
        assertEq(current[0].recipient, address(1));
        assertEq(current[0].share, 3000);

        IAccounting.FeeSplit[] memory newSplits = new IAccounting.FeeSplit[](0);

        vm.expectEmit(address(accounting));
        emit IFeeSplits.FeeSplitsSet(0, newSplits);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), newSplits);

        IAccounting.FeeSplit[] memory updated = accounting.getFeeSplits(0);
        assertEq(updated.length, 0);
    }

    function test_setFeeSplits_maxTotalShare() public {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: address(1),
            share: 6000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: address(2),
            share: 4000
        });
        mock_getNodeOperatorOwner(user);

        vm.expectEmit(address(accounting));
        emit IFeeSplits.FeeSplitsSet(0, splits);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        IAccounting.FeeSplit[] memory actual = accounting.getFeeSplits(0);
        assertEq(actual.length, 2);
        assertEq(actual[0].share + actual[1].share, 10000);
    }
}

contract MiscTest is BaseTest {
    function test_getInitializedVersion() public view {
        assertEq(accounting.getInitializedVersion(), 3);
    }

    function test_totalBondShares() public assertInvariants {
        mock_getNodeOperatorsCount(2);
        vm.deal(address(stakingModule), 64 ether);
        vm.startPrank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, 0);
        accounting.depositETH{ value: 32 ether }(user, 1);
        vm.stopPrank();
        uint256 totalDepositedShares = stETH.getSharesByPooledEth(32 ether) +
            stETH.getSharesByPooledEth(32 ether);
        assertEq(accounting.totalBondShares(), totalDepositedShares);
    }

    function test_setChargePenaltyRecipient() public {
        vm.prank(admin);
        vm.expectEmit(address(accounting));
        emit IAccounting.ChargePenaltyRecipientSet(address(1337));
        accounting.setChargePenaltyRecipient(address(1337));
        assertEq(accounting.chargePenaltyRecipient(), address(1337));
    }

    function test_setChargePenaltyRecipient_RevertWhen_DoesNotHaveRole()
        public
    {
        expectRoleRevert(stranger, accounting.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        accounting.setChargePenaltyRecipient(address(1337));
    }

    function test_setChargePenaltyRecipient_RevertWhen_Zero() public {
        vm.expectRevert();
        vm.prank(admin);
        accounting.setChargePenaltyRecipient(address(0));
    }

    function test_setBondLockPeriod() public assertInvariants {
        uint256 period = accounting.MIN_BOND_LOCK_PERIOD() + 1;
        vm.prank(admin);
        accounting.setBondLockPeriod(period);
        uint256 actual = accounting.getBondLockPeriod();
        assertEq(actual, period);
    }

    function test_renewBurnerAllowance() public assertInvariants {
        vm.prank(address(accounting));
        stETH.approve(address(burner), 0);

        assertEq(stETH.allowance(address(accounting), address(burner)), 0);

        accounting.renewBurnerAllowance();

        assertEq(
            stETH.allowance(address(accounting), address(burner)),
            type(uint256).max
        );
    }

    function test_setCustomRewardsClaimer() public {
        mock_getNodeOperatorOwner(user);

        vm.expectEmit(address(accounting));
        emit IAccounting.CustomRewardsClaimerSet(0, address(1337));
        vm.prank(user);
        accounting.setCustomRewardsClaimer(0, address(1337));

        address claimer = accounting.getCustomRewardsClaimer(0);
        assertEq(claimer, address(1337));
    }

    function test_setCustomRewardsClaimer_RevertWhen_SameAddress() public {
        mock_getNodeOperatorOwner(user);

        vm.startPrank(user);
        accounting.setCustomRewardsClaimer(0, address(1337));

        vm.expectRevert(IAccounting.SameAddress.selector);
        accounting.setCustomRewardsClaimer(0, address(1337));
        vm.stopPrank();
    }

    function test_setCustomRewardsClaimer_RevertWhen_SenderIsNotEligible()
        public
    {
        mock_getNodeOperatorOwner(user);

        vm.expectRevert(IAccounting.SenderIsNotEligible.selector);
        vm.prank(stranger);
        accounting.setCustomRewardsClaimer(0, address(1337));
    }
}

contract NegativeRebaseTest is BaseTest {
    function test_negativeRebase_ValidatorBecomeUnbonded() public {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });

        // Record the initial ETH/share ratio
        uint256 totalPooledEtherBefore = stETH.totalPooledEther();
        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 bondETHBefore = accounting.getBond(0);

        // Simulate negative rebase: reduce totalPooledEther by 1%
        uint256 rebaseLoss = totalPooledEtherBefore / 100;
        vm.store(
            address(stETH),
            bytes32(uint256(0)), // totalPooledEther storage slot
            bytes32(totalPooledEtherBefore - rebaseLoss)
        );

        // Bond shares remain the same, but ETH value decreased
        assertEq(
            accounting.getBondShares(0),
            bondSharesBefore,
            "Bond shares should remain unchanged"
        );
        uint256 bondETHAfter = accounting.getBond(0);
        assertLt(
            bondETHAfter,
            bondETHBefore,
            "Bond ETH value should decrease after negative rebase"
        );

        // After 1% loss, 32 ETH becomes ~31.68 ETH, which covers 15 validators
        uint256 unbondedKeysAfter = accounting.getUnbondedKeysCountToEject(0);
        assertEq(
            unbondedKeysAfter,
            1,
            "Should have 1 unbonded validator after 1% negative rebase"
        );
    }

    function test_negativeRebase_SomeValidatorsBecomeUnbonded() public {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });

        // Simulate negative rebase: reduce totalPooledEther by 20%
        uint256 totalPooledEtherBefore = stETH.totalPooledEther();
        uint256 rebaseLoss = (totalPooledEtherBefore * 20) / 100;
        vm.store(
            address(stETH),
            bytes32(uint256(0)), // totalPooledEther storage slot
            bytes32(totalPooledEtherBefore - rebaseLoss)
        );

        // After 20% loss, 32 ETH becomes ~25.6 ETH, which covers only 12 validators
        uint256 unbondedKeysAfter = accounting.getUnbondedKeysCountToEject(0);
        assertEq(
            unbondedKeysAfter,
            4,
            "Should have 4 unbonded validators after 20% negative rebase"
        );
    }
}

contract PenalizeTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
        vm.deal(address(stakingModule), 32 ether);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, 0);
    }

    function test_penalize() public assertInvariants {
        uint256 bond = accounting.getBond(0);
        uint256 amountToBurn = bond / 2; // burn half of the bond
        uint256 shares = stETH.getSharesByPooledEth(amountToBurn);
        uint256 bondSharesBefore = accounting.getBondShares(0);

        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(
                IBurner.requestBurnShares.selector,
                address(accounting),
                shares
            )
        );

        vm.prank(address(stakingModule));
        bool fullyBurned = accounting.penalize(0, amountToBurn);
        uint256 bondSharesAfter = accounting.getBondShares(0);

        assertEq(
            bondSharesAfter,
            bondSharesBefore - shares,
            "bond shares should be decreased by penalty"
        );
        assertEq(accounting.totalBondShares(), bondSharesAfter);
        assertTrue(fullyBurned, "should be fully burned");
    }

    function test_penalize_onInsufficientBondWithLock()
        public
        assertInvariants
    {
        uint256 bond = accounting.getBond(0);
        uint256 bondShares = accounting.getBondShares(0);
        uint256 amountToBurn = bond + 1 ether; // burn more than bond

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether); // lock some bond
        uint256 bondLockBefore = accounting.getActualLockedBond(0);

        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(
                IBurner.requestBurnShares.selector,
                address(accounting),
                bondShares
            )
        );

        vm.prank(address(stakingModule));
        bool fullyBurned = accounting.penalize(0, amountToBurn);
        uint256 bondSharesAfter = accounting.getBondShares(0);
        Accounting.BondLockData memory bondLockAfter = accounting
            .getLockedBondInfo(0);

        assertEq(
            bondSharesAfter,
            0,
            "bond shares should be zero after burning more than bond"
        );
        assertEq(
            accounting.totalBondShares(),
            0,
            "total bond shares should be zero"
        );
        assertApproxEqAbs(bondLockAfter.amount, bondLockBefore + 1 ether, 1);
        assertEq(bondLockAfter.until, type(uint128).max);
        assertFalse(fullyBurned, "should no be fully burned");
    }

    function test_penalize_RevertWhen_SenderIsNotModule() public {
        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.penalize(0, 20);
    }

    function test_penalize_unburnedAmount_noExistingLock_createsInfiniteLock()
        public
        assertInvariants
    {
        uint256 bondBefore = accounting.getBond(0);
        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 amountToBurn = bondBefore + 1 ether;

        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(
                IBurner.requestBurnShares.selector,
                address(accounting),
                bondSharesBefore
            )
        );

        vm.prank(address(stakingModule));
        bool fullyBurned = accounting.penalize(0, amountToBurn);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(
            0
        );
        assertApproxEqAbs(lockAfter.amount, amountToBurn - bondBefore, 1);
        assertEq(lockAfter.until, type(uint128).max);
        assertFalse(fullyBurned);
    }

    function test_penalize_unburnedAmount_expiredLock_notAdded()
        public
        assertInvariants
    {
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);
        Accounting.BondLockData memory lockBefore = accounting
            .getLockedBondInfo(0);
        assertEq(accounting.getActualLockedBond(0), 1 ether);

        vm.warp(lockBefore.until);
        assertEq(accounting.getActualLockedBond(0), 0);

        uint256 bondBefore = accounting.getBond(0);
        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 amountToBurn = bondBefore + 1 ether;

        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(
                IBurner.requestBurnShares.selector,
                address(accounting),
                bondSharesBefore
            )
        );

        vm.prank(address(stakingModule));
        accounting.penalize(0, amountToBurn);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(
            0
        );
        assertApproxEqAbs(lockAfter.amount, amountToBurn - bondBefore, 1);
        assertEq(lockAfter.until, type(uint128).max);
    }

    function test_penalize_fullyBurned_keepsExistingLock()
        public
        assertInvariants
    {
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 2 ether);
        Accounting.BondLockData memory lockBefore = accounting
            .getLockedBondInfo(0);
        assertEq(accounting.getActualLockedBond(0), 2 ether);

        uint256 amountToBurn = accounting.getBond(0) / 2;

        vm.prank(address(stakingModule));
        bool fullyBurned = accounting.penalize(0, amountToBurn);
        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(
            0
        );

        assertTrue(fullyBurned);
        assertEq(lockAfter.amount, lockBefore.amount);
        assertEq(lockAfter.until, lockBefore.until);
    }
}

contract PullFeeRewardsTest is BaseTest {
    function test_pullFeeRewards() public assertInvariants {
        uint256 feeShares = 1 ether;
        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore + feeShares);
        assertEq(totalBondSharesAfter, totalBondSharesBefore + feeShares);
    }

    function test_pullFeeRewards_zeroAmount() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        accounting.pullAndSplitFeeRewards(0, 0, new bytes32[](1));

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore);
        assertEq(totalBondSharesAfter, totalBondSharesBefore);
    }

    function test_pullFeeRewards_RevertWhen_operatorDoesNotExist() public {
        mock_getNodeOperatorsCount(0);
        mock_getNodeOperatorNonWithdrawnKeys(0);
        vm.expectRevert(IAccounting.NodeOperatorDoesNotExist.selector);
        accounting.pullAndSplitFeeRewards(0, 0, new bytes32[](1));
    }

    function test_pullFeeRewards_withSplits() public assertInvariants {
        uint256 feeShares = 10 ether;

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        feeShares -= 8 ether; // remaining shares after splits

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore + feeShares);
        assertEq(totalBondSharesAfter, totalBondSharesBefore + feeShares);

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0] + 3 ether,
            "fee split shares mismatch"
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1] + 5 ether,
            "fee split shares mismatch"
        );
    }

    function test_pullFeeRewards_withSplits_lowFeeAmount()
        public
        assertInvariants
    {
        uint256 feeShares = 3 wei;

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 100
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 500
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore + feeShares);
        assertEq(totalBondSharesAfter, totalBondSharesBefore + feeShares);

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0],
            "fee split shares mismatch"
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1],
            "fee split shares mismatch"
        );
    }

    function test_pullFeeRewards_withSplits_allBPSUsed_noReminderDueToRounding()
        public
        assertInvariants
    {
        uint256 feeShares = 1 ether;

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 7000
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore);
        assertEq(totalBondSharesAfter, totalBondSharesBefore);

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0] + 0.3 ether,
            "fee split shares mismatch"
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1] + 0.7 ether,
            "fee split shares mismatch"
        );
    }

    function test_pullFeeRewards_withSplits_ZeroFeeAmount()
        public
        assertInvariants
    {
        uint256 feeShares = 0;

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 100
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 500
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore + feeShares);
        assertEq(totalBondSharesAfter, totalBondSharesBefore + feeShares);

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0],
            "fee split shares mismatch"
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1],
            "fee split shares mismatch"
        );
    }

    function testFuzz_pullFeeRewards_withSplits(
        uint256 feeShares,
        uint8 splitsCount,
        uint256 shareSeed
    ) public assertInvariants {
        splitsCount = uint8(bound(splitsCount, 1, FeeSplits.MAX_FEE_SPLITS));
        feeShares = bound(feeShares, 0, 10 ether);

        uint256[] memory fees = new uint256[](splitsCount);
        uint256 totalFeeSharesForSplits;

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](
            splitsCount
        );
        uint256 totalShare;
        for (uint8 i = 0; i < splitsCount; i++) {
            splits[i].recipient = nextAddress();
            uint256 remainingShare = 10_000 - totalShare;
            if (i == splitsCount - 1) {
                splits[i].share = remainingShare;
            } else {
                uint256 reserveForOthers = splitsCount - i - 1; // at least 1 share for remaining splits
                uint256 maxPossible = remainingShare - reserveForOthers;
                splits[i].share = ((shareSeed / (i + 1)) % maxPossible) + 1; // at least 1 share per split
            }
            totalShare += splits[i].share;
            fees[i] = (feeShares * splits[i].share) / 10_000;
            totalFeeSharesForSplits += fees[i];
        }

        uint256[] memory sharesBefore = new uint256[](splitsCount);

        for (uint8 i = 0; i < splitsCount; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        feeShares -= totalFeeSharesForSplits; // remaining shares after splits

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();

        assertEq(bondSharesAfter, bondSharesBefore + feeShares);
        assertEq(totalBondSharesAfter, totalBondSharesBefore + feeShares);

        for (uint8 i = 0; i < splitsCount; i++) {
            assertEq(
                stETH.sharesOf(splits[i].recipient),
                sharesBefore[i] + fees[i],
                "fee split shares mismatch"
            );
        }
    }

    function test_pullFeeRewards_withSplits_claimableLessThanPending()
        public
        assertInvariants
    {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3000
        });
        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        uint256 feeShares = 2 ether;
        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(1);

        (, uint256 requiredShares) = accounting.getBondSummaryShares(0);
        assertGt(requiredShares, 0);
        assertLt(requiredShares, feeShares);

        uint256 expectedClaimableAfterPull = feeShares - requiredShares;

        uint256 pendingBefore = accounting.getPendingSharesToSplit(0);
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));
        uint256 pendingAfter = accounting.getPendingSharesToSplit(0);

        uint256 expectedPendingIncrease = feeShares;
        uint256 expectedPendingDecrease = expectedClaimableAfterPull;
        uint256 expectedPendingAfter = pendingBefore +
            expectedPendingIncrease -
            expectedPendingDecrease;

        uint256 expectedSplit0 = (expectedClaimableAfterPull * 5000) / 10000;
        uint256 expectedSplit1 = (expectedClaimableAfterPull * 3000) / 10000;

        assertGt(pendingAfter, 0);
        assertEq(pendingAfter, expectedPendingAfter);
        assertEq(stETH.sharesOf(splits[0].recipient), expectedSplit0);
        assertEq(stETH.sharesOf(splits[1].recipient), expectedSplit1);
    }

    function test_pullFeeRewards_withSplits_multipleCallsAccumulatePending()
        public
        assertInvariants
    {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(100500); // Required significantly more than we will pull

        // First pull with less than required - should be limited by claimable
        uint256 firstFeeShares = 0.5 ether;
        stETH.mintShares(address(feeDistributor), firstFeeShares);
        accounting.pullAndSplitFeeRewards(0, firstFeeShares, new bytes32[](1));

        // Multiple small pulls to accumulate pending
        uint256 secondFeeShares = 0.1 ether;
        for (uint256 i = 0; i < 5; i++) {
            stETH.mintShares(address(feeDistributor), secondFeeShares);
            accounting.pullAndSplitFeeRewards(
                0,
                secondFeeShares,
                new bytes32[](1)
            );
        }

        mock_getNodeOperatorNonWithdrawnKeys(0); // Now claimable >= pending

        // One more pull should process accumulated pending
        stETH.mintShares(address(feeDistributor), secondFeeShares);
        accounting.pullAndSplitFeeRewards(0, secondFeeShares, new bytes32[](1));

        uint256 expectedTransferred = (firstFeeShares +
            (5 * secondFeeShares) +
            secondFeeShares) / 2;

        uint256 recipientSharesAfter = stETH.sharesOf(splits[0].recipient);
        assertEq(recipientSharesAfter, expectedTransferred, "recipient shares");

        uint256 claimableAfter = accounting.getClaimableBondShares(0);
        assertEq(claimableAfter, expectedTransferred, "claimable mismatch");

        uint256 pendingAfter = accounting.getPendingSharesToSplit(0);
        assertEq(pendingAfter, 0);
    }

    function test_pullFeeRewards_withSplits_zeroClaimableShares()
        public
        assertInvariants
    {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(100500); // Required significantly more than we will pull

        uint256 feeShares = 1 ether;
        stETH.mintShares(address(feeDistributor), feeShares);

        uint256 sharesBefore = stETH.sharesOf(splits[0].recipient);
        uint256 bondSharesBefore = accounting.getBondShares(0);

        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        assertEq(stETH.sharesOf(splits[0].recipient), sharesBefore);
        assertEq(accounting.getBondShares(0), bondSharesBefore + feeShares);
        assertEq(accounting.getPendingSharesToSplit(0), feeShares);
    }

    function test_pullFeeRewards_withSplits_roundingRemainderToBond()
        public
        assertInvariants
    {
        uint256 feeShares = 10; // small amount to trigger rounding

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3333
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3333
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 recipient0 = (feeShares * splits[0].share) / 10_000;
        uint256 recipient1 = (feeShares * splits[1].share) / 10_000;
        uint256 expectedRemainder = feeShares - (recipient0 + recipient1);

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0] + recipient0,
            "split[0] shares"
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1] + recipient1,
            "split[1] shares"
        );

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();
        assertGt(expectedRemainder, 0);
        assertEq(bondSharesAfter, bondSharesBefore + expectedRemainder);
        assertEq(
            totalBondSharesAfter,
            totalBondSharesBefore + expectedRemainder
        );
    }

    function test_pullFeeRewards_withSplits_zeroAmountSplitsNoChange()
        public
        assertInvariants
    {
        uint256 feeShares = 3; // ensure some splits round to zero

        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](3);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 2500
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 2500
        });
        splits[2] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });

        uint256[] memory sharesBefore = new uint256[](splits.length);
        for (uint8 i = 0; i < splits.length; i++) {
            sharesBefore[i] = stETH.sharesOf(splits[i].recipient);
        }

        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        stETH.mintShares(address(feeDistributor), feeShares);
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 bondSharesBefore = accounting.getBondShares(0);
        uint256 totalBondSharesBefore = accounting.totalBondShares();

        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 recipient0 = (feeShares * splits[0].share) / 10_000; // 0
        uint256 recipient1 = (feeShares * splits[1].share) / 10_000; // 0
        uint256 recipient2 = (feeShares * splits[2].share) / 10_000; // 1
        uint256 expectedRemainder = feeShares -
            (recipient0 + recipient1 + recipient2); // 2

        assertEq(stETH.sharesOf(splits[0].recipient), sharesBefore[0]);
        assertEq(stETH.sharesOf(splits[1].recipient), sharesBefore[1]);
        assertEq(
            stETH.sharesOf(splits[2].recipient),
            sharesBefore[2] + recipient2
        );

        uint256 bondSharesAfter = accounting.getBondShares(0);
        uint256 totalBondSharesAfter = accounting.totalBondShares();
        assertGt(expectedRemainder, 0);
        assertEq(bondSharesAfter, bondSharesBefore + expectedRemainder);
        assertEq(
            totalBondSharesAfter,
            totalBondSharesBefore + expectedRemainder
        );
    }

    function test_pullFeeRewards_withSplits_withLock() public assertInvariants {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });
        mock_getNodeOperatorOwner(user);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        // Create a lock so claimable stays zero and pending accumulates
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);

        // Accumulate pending while locked
        uint256 first = 5;
        stETH.mintShares(address(feeDistributor), first);
        accounting.pullAndSplitFeeRewards(0, first, new bytes32[](1));
        assertEq(accounting.getPendingSharesToSplit(0), first);

        uint256 second = 7;
        stETH.mintShares(address(feeDistributor), second);
        accounting.pullAndSplitFeeRewards(0, second, new bytes32[](1));
        assertEq(accounting.getPendingSharesToSplit(0), first + second);

        // Let the lock expire
        Accounting.BondLockData memory lockInfo = accounting.getLockedBondInfo(
            0
        );
        vm.warp(lockInfo.until);
        assertEq(accounting.getActualLockedBond(0), 0);

        // One more pull should process all accumulated pending
        uint256 third = 8;
        stETH.mintShares(address(feeDistributor), third);
        uint256 recipientBefore = stETH.sharesOf(splits[0].recipient);
        accounting.pullAndSplitFeeRewards(0, third, new bytes32[](1));

        uint256 total = first + second + third; // all pending becomes claimable now
        uint256 expectedToRecipient = (total * 5000) / 10000;
        uint256 expectedRemainder = total - expectedToRecipient;

        assertGt(expectedRemainder, 0);
        assertGt(expectedToRecipient, 0);
        assertEq(
            stETH.sharesOf(splits[0].recipient),
            recipientBefore + expectedToRecipient
        );
        assertEq(accounting.getBondShares(0), expectedRemainder);
        assertEq(accounting.getPendingSharesToSplit(0), 0);
    }
}

contract ClaimRewardsWithFeeSplitsTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        // Setup some bond to make claims possible
        vm.deal(address(stakingModule), 32 ether);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, 0);
    }

    function test_claimRewardsStETH_withFeeSplits() public assertInvariants {
        // Setup fee splits
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](2);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 3000
        });
        splits[1] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 2000
        });

        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorManagementProperties(user, user, false);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        // Setup fee rewards
        uint256 feeShares = 1 ether;
        stETH.mintShares(address(feeDistributor), feeShares);

        uint256[] memory sharesBefore = new uint256[](2);
        sharesBefore[0] = stETH.sharesOf(splits[0].recipient);
        sharesBefore[1] = stETH.sharesOf(splits[1].recipient);

        uint256 userBalanceBefore = stETH.balanceOf(user);

        // Claim rewards with fee splits
        vm.prank(user);
        uint256 claimedShares = accounting.claimRewardsStETH(
            0,
            0.5 ether,
            feeShares,
            new bytes32[](1)
        );

        // Verify fee splits were processed
        uint256 expectedSplit0 = (feeShares * 3000) / 10000;
        uint256 expectedSplit1 = (feeShares * 2000) / 10000;

        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore[0] + expectedSplit0
        );
        assertEq(
            stETH.sharesOf(splits[1].recipient),
            sharesBefore[1] + expectedSplit1
        );

        // Verify user got their claim
        assertGt(stETH.balanceOf(user), userBalanceBefore);
        assertGt(claimedShares, 0);
    }

    function test_claimRewardsWstETH_withFeeSplits() public assertInvariants {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 4000
        });

        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorManagementProperties(user, user, false);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        uint256 feeShares = 0.8 ether;
        stETH.mintShares(address(feeDistributor), feeShares);

        uint256 sharesBefore = stETH.sharesOf(splits[0].recipient);
        uint256 userWstBalanceBefore = wstETH.balanceOf(user);

        vm.prank(user);
        uint256 claimedWstETH = accounting.claimRewardsWstETH(
            0,
            0.3 ether,
            feeShares,
            new bytes32[](1)
        );

        uint256 expectedSplit = (feeShares * 4000) / 10000;
        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore + expectedSplit
        );

        assertGt(wstETH.balanceOf(user), userWstBalanceBefore);
        assertGt(claimedWstETH, 0);
    }

    function test_claimRewardsUnstETH_withFeeSplits() public assertInvariants {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 6000
        });

        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorManagementProperties(user, user, false);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        uint256 feeShares = 1.2 ether;
        stETH.mintShares(address(feeDistributor), feeShares);

        uint256 sharesBefore = stETH.sharesOf(splits[0].recipient);

        vm.prank(user);
        accounting.claimRewardsUnstETH(
            0,
            0.4 ether,
            feeShares,
            new bytes32[](1)
        );

        uint256 expectedSplit = (feeShares * 6000) / 10000;
        assertEq(
            stETH.sharesOf(splits[0].recipient),
            sharesBefore + expectedSplit
        );
    }

    function test_claimRewards_withEmptyProofButSplits()
        public
        assertInvariants
    {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });

        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorManagementProperties(user, user, false);

        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        uint256 sharesBefore = stETH.sharesOf(splits[0].recipient);
        uint256 userBalanceBefore = stETH.balanceOf(user);

        // Claim with empty proof - should not process fee splits
        vm.prank(user);
        uint256 claimedShares = accounting.claimRewardsStETH(
            0,
            0.5 ether,
            0,
            new bytes32[](0)
        );

        // No rewards fee splits should have been processed
        assertEq(stETH.sharesOf(splits[0].recipient), sharesBefore);

        // But user should still get their claim
        assertGt(stETH.balanceOf(user), userBalanceBefore);
        assertGt(claimedShares, 0);
    }

    function test_splitPendingOnly_withoutPull() public assertInvariants {
        IAccounting.FeeSplit[] memory splits = new IAccounting.FeeSplit[](1);
        splits[0] = IAccounting.FeeSplit({
            recipient: nextAddress(),
            share: 5000
        });

        mock_getNodeOperatorOwner(user);
        mock_getNodeOperatorManagementProperties(user, user, false);
        vm.prank(user);
        accounting.setFeeSplits(0, 0, new bytes32[](0), splits);

        // Ensure no claimable: for 1 key more than current bond
        _operator({ ongoing: 17, withdrawn: 0 });
        uint256 claimable = accounting.getClaimableBondShares(0);
        assertEq(claimable, 0, "initial claimable must be zero");

        uint256 feeShares = stETH.getSharesByPooledEth(1 ether);
        stETH.mintShares(address(feeDistributor), feeShares);
        // Pull rewards (with proof) to accumulate pending while claimable == 0
        accounting.pullAndSplitFeeRewards(0, feeShares, new bytes32[](1));

        uint256 claimableAfterPull = accounting.getClaimableBondShares(0);
        assertEq(claimableAfterPull, 0, "claimable must still be zero");
        uint256 pendingAfterPull = accounting.getPendingSharesToSplit(0);
        assertEq(
            pendingAfterPull,
            feeShares,
            "pending must be equal feeShares after pull"
        );

        // Increase claimable by depositing 6 ETH
        _deposit({ bond: 6 ether });

        uint256 claimableBeforeSplit = accounting.getClaimableBondShares(0);
        assertGt(claimableBeforeSplit, 0, "claimable must be > 0");

        uint256 recipientBefore = stETH.sharesOf(splits[0].recipient);
        uint256 bondBeforeSplit = accounting.getBondShares(0);

        // Now split pending without pulling (empty proof, zero amount)
        accounting.pullAndSplitFeeRewards(0, 0, new bytes32[](0));

        uint256 expectedToRecipient = (feeShares * splits[0].share) / 10_000;
        assertEq(
            stETH.sharesOf(splits[0].recipient),
            recipientBefore + expectedToRecipient,
            "recipient should receive split shares"
        );

        assertEq(
            accounting.getPendingSharesToSplit(0),
            0,
            "pending should be zero after split"
        );

        // Bond reduced only by transferred (not by rounding remainder)
        uint256 bondAfterSplit = accounting.getBondShares(0);
        assertEq(
            bondAfterSplit,
            bondBeforeSplit - expectedToRecipient,
            "bond should be reduced by transferred shares"
        );
    }
}

contract ScenarioTest is BaseTest {
    function test_scenario_lock_curve_withdraw_settle()
        public
        assertInvariants
    {
        uint256 curr;
        uint256 req;

        // 1) Initial operator with 16 ongoing, 0 withdrawn
        _operator({ ongoing: 16, withdrawn: 0 });

        // Required: 32 ether
        (curr, req) = accounting.getBondSummary(0);
        assertEq(curr, 0);
        assertEq(req, 32 ether);

        // 2) Deposit 40 ether bond, we have 8 ether excess claimable
        _deposit({ bond: 40 ether });
        (curr, req) = accounting.getBondSummary(0);
        assertApproxEqAbs(curr, ethToSharesToEth(40 ether), 1);
        assertEq(req, 32 ether);

        // 3) Apply a lock of 3 ether
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 3 ether);
        (, req) = accounting.getBondSummary(0);
        // required grows by locked amount
        assertEq(req, 35 ether);

        // 4) Change curve to discounted: for 16 keys = 17 ether
        {
            IBondCurve.BondCurveIntervalInput[]
                memory curve = new IBondCurve.BondCurveIntervalInput[](2);
            curve[0] = IBondCurve.BondCurveIntervalInput({
                minKeysCount: 1,
                trend: 2 ether
            });
            curve[1] = IBondCurve.BondCurveIntervalInput({
                minKeysCount: 2,
                trend: 1 ether
            });
            vm.startPrank(admin);
            uint256 curveId = accounting.addBondCurve(curve);
            accounting.setBondCurve(0, curveId);
            vm.stopPrank();
        }
        (, req) = accounting.getBondSummary(0);
        // lock is kept
        assertEq(req, 20 ether);

        // 5) Withdraw 2 validators => non-withdrawn becomes 14, curve(14)=15 ether
        mock_getNodeOperatorNonWithdrawnKeys(14);
        (, req) = accounting.getBondSummary(0);
        // required: 15 + 3 locked = 18 ether
        assertEq(req, 18 ether);

        // Since current >= required, all unbonded should be zero
        assertEq(accounting.getUnbondedKeysCount(0), 0);
        assertEq(accounting.getUnbondedKeysCountToEject(0), 0);

        // 6.a) Increase active keys to 37. We expect unbonded (include locked)
        _operator({ ongoing: 37, withdrawn: 0 });
        // include locked -> available = 37 ETH -> covers 36 keys -> 1 unbonded
        assertEq(accounting.getUnbondedKeysCount(0), 1);
        // exclude locked -> available = 40 ETH -> covers >= 36 keys -> 0 unbonded
        assertEq(accounting.getUnbondedKeysCountToEject(0), 0);

        // 6.b) Penalize a small amount.
        vm.prank(address(stakingModule));
        accounting.penalize(0, 1 ether);
        // after 1 ETH penalty: include locked -> available = 36 ETH -> covers 35 keys -> 2 unbonded
        assertEq(accounting.getUnbondedKeysCount(0), 2);
        // exclude locked -> available = 39 ETH -> covers >= 15 -> 0 unbonded
        assertEq(accounting.getUnbondedKeysCountToEject(0), 0);

        // 7) Settle lock
        vm.prank(address(stakingModule));
        bool applied = accounting.settleLockedBondETH(0);
        assertTrue(applied);

        (, req) = accounting.getBondSummary(0);

        assertApproxEqAbs(req, 38 ether, 1);
        // after settling lock, locked=0 but available = 36 ETH -> covers 35 keys -> 2 unbonded
        assertEq(accounting.getUnbondedKeysCount(0), 2);
        assertEq(accounting.getUnbondedKeysCountToEject(0), 2);
    }
}
