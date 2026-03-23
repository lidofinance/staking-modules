// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { BaseTest, BondStateBaseTest, GetRequiredBondBaseTest, GetRequiredBondForKeysBaseTest, RewardsBaseTest } from "./_Base.t.sol";
import { Accounting } from "src/Accounting.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IBondLock } from "src/interfaces/IBondLock.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IBurner } from "src/interfaces/IBurner.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

// Combined bond tests: curves, claimable, locking, required bonds, summaries

contract BondCurveTest is BaseTest {
    function test_addBondCurve() public {
        IBondCurve.BondCurveIntervalInput[] memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: 2 ether });
        vm.prank(admin);
        uint256 addedId = accounting.addBondCurve(curvePoints);

        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo({ curveId: addedId });

        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
    }

    function test_addBondCurve_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.MANAGE_BOND_CURVES_ROLE());
        vm.prank(stranger);
        accounting.addBondCurve(new IBondCurve.BondCurveIntervalInput[](0));
    }

    function test_updateBondCurve() public assertInvariants {
        IBondCurve.BondCurveIntervalInput[] memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: 2 ether });

        uint256 toUpdate = 0;

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(IBaseModule.requestFullDepositInfoUpdate.selector)
        );
        vm.prank(admin);
        accounting.updateBondCurve(toUpdate, curvePoints);

        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo({ curveId: toUpdate });

        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
    }

    function test_updateBondCurve_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.MANAGE_BOND_CURVES_ROLE());
        vm.prank(stranger);
        accounting.updateBondCurve(0, new IBondCurve.BondCurveIntervalInput[](0));
    }

    function test_updateBondCurve_RevertWhen_InvalidBondCurveId() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        vm.prank(admin);
        accounting.updateBondCurve(1, new IBondCurve.BondCurveIntervalInput[](0));
    }

    function test_setBondCurve() public assertInvariants {
        IBondCurve.BondCurveIntervalInput[] memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: 2 ether });

        mock_getNodeOperatorsCount(1);

        vm.startPrank(admin);

        uint256 addedId = accounting.addBondCurve(curvePoints);

        vm.expectCall(address(accounting.MODULE()), abi.encodeWithSelector(IBaseModule.updateDepositInfo.selector, 0));
        accounting.setBondCurve({ nodeOperatorId: 0, curveId: addedId });

        vm.stopPrank();

        IBondCurve.BondCurveData memory curve = accounting.getBondCurve(0);

        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
    }

    function test_setBondCurve_RevertWhen_OperatorDoesNotExist() public {
        mock_getNodeOperatorsCount(0);
        vm.expectRevert(IAccounting.NodeOperatorDoesNotExist.selector);
        vm.prank(admin);
        accounting.setBondCurve({ nodeOperatorId: 0, curveId: 2 });
    }

    function test_setBondCurve_RevertWhen_SameBondCurveId() public {
        mock_getNodeOperatorsCount(1);
        vm.expectRevert(IBondCurve.SameBondCurveId.selector);
        vm.prank(admin);
        accounting.setBondCurve({ nodeOperatorId: 0, curveId: 0 });
    }

    function test_setBondCurve_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.SET_BOND_CURVE_ROLE());
        vm.prank(stranger);
        accounting.setBondCurve({ nodeOperatorId: 0, curveId: 2 });
    }
}

contract ClaimableBondTest is RewardsBaseTest {
    function test_default() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithCurve() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });
        _curve(curveWithDiscount);

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(15 ether),
            1 wei,
            "claimable bond shares should be equal to the curve discount"
        );
    }

    function test_WithLocked() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });
        _lock({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithCurveAndLocked() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(14 ether),
            1 wei,
            "claimable bond shares should be equal to the curve discount minus locked"
        );
    }

    function test_WithOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(2 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond"
        );
    }

    function test_WithBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithBondDebt() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _debt({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(2 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond"
        );
    }

    function test_WithExcessBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(1 ether),
            1 wei,
            "claimable bond shares should be equal to the excess bond"
        );
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(3 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond plus the excess bond"
        );
    }

    function test_WithMissingBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }
}

contract LockBondTest is BaseTest {
    function test_setBondLockPeriod() public {
        vm.prank(admin);
        accounting.setBondLockPeriod(200 days);
        assertEq(accounting.getBondLockPeriod(), 200 days);
    }

    function test_setBondLockPeriod_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        accounting.setBondLockPeriod(200 days);
    }

    function test_lockBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBond(0, 1 ether);
        assertEq(accounting.getLockedBond(0), 1 ether);
    }

    function test_lockBond_RevertWhen_SenderIsNotModule() public {
        mock_getNodeOperatorsCount(1);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.lockBond(0, 1 ether);
    }

    function test_lockBond_RevertWhen_LockOverflow() public {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBond(0, 1 ether);
        assertEq(accounting.getLockedBond(0), 1 ether);

        vm.expectRevert();
        vm.prank(address(stakingModule));
        accounting.lockBond(0, type(uint256).max);
    }

    function test_releaseLockedBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBond(0, 1 ether);

        vm.prank(address(stakingModule));
        bool released = accounting.releaseLockedBond(0, 0.4 ether);

        assertTrue(released, "release should return true when bond is released");
        assertEq(accounting.getLockedBond(0), 0.6 ether);
    }

    function test_releaseLockedBond_NoLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        assertEq(accounting.getLockedBond(0), 0);

        vm.prank(address(stakingModule));
        bool released = accounting.releaseLockedBond(0, 0.4 ether);

        assertFalse(released, "release should return false when bond is released");
        assertEq(accounting.getLockedBond(0), 0);
    }

    function test_releaseLockedBond_ExpiredLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBond(0, 1 ether);

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1 seconds);

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(IBaseModule.updateDepositableValidatorsCount.selector, 0)
        );
        vm.prank(address(stakingModule));
        bool released = accounting.releaseLockedBond(0, 0.4 ether);

        assertFalse(released, "release should return false when lock is expired");
        assertEq(accounting.getLockedBond(0), 0);
    }

    function test_releaseLockedBond_RevertWhen_SenderIsNotModule() public {
        mock_getNodeOperatorsCount(1);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.releaseLockedBond(0, 1 ether);
    }

    function test_compensateLockedBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 amountToLock = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, amountToLock);

        assertEq(accounting.getLockedBond(0), amountToLock);

        uint256 amountToCompensate = 0.4 ether;
        addBond(0, amountToCompensate);

        vm.expectEmit(address(accounting));
        emit IAccounting.BondLockCompensated(0, ethToSharesToEth(amountToCompensate));

        vm.prank(address(stakingModule));
        accounting.compensateLockedBond(0);

        assertEq(accounting.getLockedBond(0), amountToLock - ethToSharesToEth(amountToCompensate));
    }

    function test_compensateLockedBond_notingLocked() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        assertEq(accounting.getLockedBond(0), 0);

        vm.prank(address(stakingModule));
        accounting.compensateLockedBond(0);

        assertEq(accounting.getLockedBond(0), 0);
    }

    function test_compensateLockedBond_unlockExpiredLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        assertEq(accounting.getLockedBond(0), 0);

        uint256 amountToLock = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, amountToLock);

        assertEq(accounting.getLockedBond(0), amountToLock);

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1 seconds);

        assertTrue(accounting.isLockExpired(0), "lock should be expired");

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(IBaseModule.updateDepositableValidatorsCount.selector, 0)
        );
        vm.expectEmit(address(accounting));
        emit IBondLock.ExpiredBondLockRemoved(0);
        vm.prank(address(stakingModule));
        accounting.compensateLockedBond(0);

        assertEq(accounting.getLockedBond(0), 0);
    }

    function test_compensateLockedBond_requiredWithoutLockIsMoreThanCurrent() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(1);

        uint256 amountToLock = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, amountToLock);

        assertEq(accounting.getLockedBond(0), amountToLock);

        uint256 amountToCompensate = 1 ether;
        addBond(0, amountToCompensate);

        vm.prank(address(stakingModule));
        accounting.compensateLockedBond(0);

        assertEq(accounting.getLockedBond(0), amountToLock);
    }

    function test_compensateLockedBond_FullCompensation() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        mock_getNodeOperatorNonWithdrawnKeys(0);

        uint256 amountToLock = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, amountToLock);

        uint256 amountToCompensate = 1.4 ether;
        addBond(0, amountToCompensate);

        vm.expectEmit(address(accounting));
        emit IAccounting.BondLockCompensated(0, amountToLock);

        vm.prank(address(stakingModule));
        accounting.compensateLockedBond(0);

        assertEq(accounting.getLockedBond(0), 0);
    }

    function test_compensateLockedBond_RevertWhen_SenderIsNotModule() public {
        mock_getNodeOperatorsCount(1);

        uint256 amountToLock = 1 ether;
        vm.prank(address(stakingModule));
        accounting.lockBond(0, amountToLock);

        uint256 amountToCompensate = 0.4 ether;
        addBond(0, amountToCompensate);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.compensateLockedBond(0);
    }

    function test_settleLockedBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);
        assertEq(accounting.getLockedBond(noId), amount);

        vm.prank(address(stakingModule));
        uint256 settled = accounting.settleLockedBond(noId, amount);
        assertEq(settled, amount);
        assertEq(accounting.getLockedBond(noId), 0);
    }

    function test_settleLockedBond_noLocked() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        vm.deal(address(stakingModule), 32 ether);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, noId);
        uint256 bond = accounting.getBondShares(noId);

        vm.prank(address(stakingModule));
        accounting.settleLockedBond(noId, 1 ether);
        assertEq(accounting.getLockedBond(noId), 0);
        assertEq(accounting.getBondShares(noId), bond);
    }

    function test_settleLockedBond_unlockExpiredLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);
        assertEq(accounting.getLockedBond(noId), amount);

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1 seconds);

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(IBaseModule.updateDepositableValidatorsCount.selector, noId)
        );
        vm.expectEmit(address(accounting));
        emit IBondLock.ExpiredBondLockRemoved(noId);
        vm.prank(address(stakingModule));
        uint256 settled = accounting.settleLockedBond(noId, amount);

        assertEq(settled, 0);
        assertEq(accounting.getLockedBond(noId), 0);
    }

    function test_settleLockedBond_maxGreaterThanLocked() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);
        assertEq(accounting.getLockedBond(noId), amount);

        vm.prank(address(stakingModule));
        uint256 settled = accounting.settleLockedBond(noId, amount + 0.4 ether);
        assertEq(settled, amount);
        assertEq(accounting.getLockedBond(noId), 0);
    }

    function test_settleLockedBond_maxLessThanLocked() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);
        assertEq(accounting.getLockedBond(noId), amount);

        vm.prank(address(stakingModule));
        uint256 settled = accounting.settleLockedBond(noId, amount - 0.4 ether);
        assertEq(settled, amount - 0.4 ether);
        assertEq(accounting.getLockedBond(noId), 0.4 ether);
    }

    function test_settleLockedBond_noBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;

        vm.startPrank(address(stakingModule));
        accounting.lockBond(noId, amount);

        expectNoCall(address(burner), abi.encodeWithSelector(IBurner.requestBurnMyShares.selector));
        accounting.settleLockedBond(noId, amount);
        vm.stopPrank();

        Accounting.BondLockData memory bondLockAfter = accounting.getLockedBondInfo(0);

        assertEq(bondLockAfter.amount, 0);
        assertEq(bondLockAfter.until, 0);
        assertEq(accounting.getBondShares(noId), 0);
        assertApproxEqAbs(accounting.getBondDebt(noId), amount, 1);
    }

    function test_settleLockedBond_partialBurn_bondDebtCreated() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;

        uint256 bond = 10 ether;
        uint256 locked = 15 ether;
        addBond(noId, bond);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, locked);

        uint256 bondSharesBefore = accounting.getBondShares(noId);
        vm.expectCall(locator.burner(), abi.encodeWithSelector(IBurner.requestBurnMyShares.selector, bondSharesBefore));

        vm.prank(address(stakingModule));
        accounting.settleLockedBond(noId, locked);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(noId);
        assertEq(lockAfter.amount, 0);
        assertEq(lockAfter.until, 0);
        assertApproxEqAbs(accounting.getBondDebt(noId), locked - bond, 1);
    }

    function test_settleLockedBond_restZero_removesLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;

        uint256 amount = 5 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.settleLockedBond(noId, amount);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(noId);
        assertEq(lockAfter.amount, 0);
        assertEq(lockAfter.until, 0);
        assertEq(accounting.getLockedBond(noId), 0);
    }

    function test_unlockExpiredLock() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);

        vm.warp(block.timestamp + accounting.getBondLockPeriod() + 1 seconds);

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(IBaseModule.updateDepositableValidatorsCount.selector, noId)
        );
        vm.expectEmit(address(accounting));
        emit IBondLock.ExpiredBondLockRemoved(noId);
        vm.prank(address(stakingModule));
        accounting.unlockExpiredLock(noId);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(noId);
        assertEq(lockAfter.amount, 0);
        assertEq(lockAfter.until, 0);
    }

    function test_unlockExpiredLock_lockIsNotExpired() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;

        vm.prank(address(stakingModule));
        accounting.lockBond(noId, amount);

        vm.expectRevert(IBondLock.BondLockNotExpired.selector);
        vm.prank(address(stakingModule));
        accounting.unlockExpiredLock(noId);
    }
}

contract GetRequiredETHBondTest is GetRequiredBondBaseTest {
    function test_default() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 32 ether);
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 17 ether);
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 33 ether);
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 18 ether);
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 30 ether);
    }

    function test_OneWithdrawnOneAddedValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), 32 ether);
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), required - current);
    }

    function test_WithBondDebt() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _debt({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), required - current);
    }

    function test_WithBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), 2 ether - (current - required));
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), 0);
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), required - current);
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), required - current);
    }

    function test_WithMissingBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), required - current + 2 ether);
    }
}

contract GetRequiredWstETHBondTest is GetRequiredBondBaseTest {
    function test_default() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_OneWithdrawnOneAddedValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 1),
            wstETH.getWstETHByStETH(required - current + 2 ether)
        );
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithBondDebt() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _debt({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 1), 0);
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 1), 0);
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), wstETH.getWstETHByStETH(required - current));
    }

    function test_WithMissingBondAndOneWithdrawnAndOneAddedValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 1),
            wstETH.getWstETHByStETH(required - current + 2 ether)
        );
    }
}

contract GetBondAmountByKeysCountWstETHTest is GetRequiredBondForKeysBaseTest {
    function test_default() public override assertInvariants {
        assertEq(accounting.getBondAmountByKeysCountWstETH(0, 0), 0);
        assertEq(accounting.getBondAmountByKeysCountWstETH(1, 0), wstETH.getWstETHByStETH(2 ether));
        assertEq(accounting.getBondAmountByKeysCountWstETH(2, 0), wstETH.getWstETHByStETH(4 ether));
        assertEq(accounting.getBondAmountByKeysCountWstETH(8, 0), wstETH.getWstETHByStETH(16 ether));
    }

    function test_WithCurve() public override assertInvariants {
        IBondCurve.BondCurveIntervalInput[] memory defaultCurve = new IBondCurve.BondCurveIntervalInput[](2);
        defaultCurve[0] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 1, trend: 2 ether });
        defaultCurve[1] = IBondCurve.BondCurveIntervalInput({ minKeysCount: 2, trend: 1 ether });

        vm.startPrank(admin);
        uint256 curveId = accounting.addBondCurve(defaultCurve);
        assertEq(accounting.getBondAmountByKeysCountWstETH(0, curveId), 0);
        assertEq(accounting.getBondAmountByKeysCountWstETH(1, curveId), wstETH.getWstETHByStETH(2 ether));
        assertEq(accounting.getBondAmountByKeysCountWstETH(2, curveId), wstETH.getWstETHByStETH(3 ether));
        assertEq(accounting.getBondAmountByKeysCountWstETH(15, curveId), wstETH.getWstETHByStETH(16 ether));
    }
}

// Combined bond summary and shares tests

contract GetBondSummaryTest is BondStateBaseTest {
    function test_default() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 32 ether);
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 17 ether);
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 33 ether);
    }

    function test_WithLocked_MoreThanBond() public assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 100500 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 100532 ether);
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 18 ether);
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0 ether);
        assertEq(required, 30 ether);
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(32 ether));
        assertEq(required, 32 ether);
    }

    function test_WithBondDebt() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _debt({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, 0);
        assertApproxEqAbs(required, 33 ether, 1 wei);
    }

    function test_WithBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(32 ether));
        assertEq(required, 30 ether);
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(33 ether));
        assertEq(required, 32 ether);
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(33 ether));
        assertEq(required, 30 ether);
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(29 ether));
        assertEq(required, 32 ether);
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(current, ethToSharesToEth(29 ether));
        assertEq(required, 30 ether);
    }
}

contract GetBondSummarySharesTest is BondStateBaseTest {
    function test_default() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(17 ether));
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(33 ether));
    }

    function test_WithLocked_MoreThanBond() public assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 100500 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(100532 ether));
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(18 ether));
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(32 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithBondDebt() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _debt({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, 0);
        assertApproxEqAbs(required, stETH.getSharesByPooledEth(32 ether + 1 ether), 1 wei);
    }

    function test_WithBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(32 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(33 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(33 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(29 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(0);
        assertEq(current, stETH.getSharesByPooledEth(29 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }
}

contract ClaimableRewardsAndBondSharesTest is RewardsBaseTest {
    function test_default() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            stETH.getSharesByPooledEth(0.1 ether),
            "claimable bond shares should not be zero"
        );
    }

    function test_WithCurve() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });
        _curve(curveWithDiscount);

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(15.1 ether),
            1 wei,
            "claimable bond shares should be equal to the curve discount + rewards"
        );
    }

    function test_WithLocked() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });
        _lock({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            stETH.getSharesByPooledEth(0.1 ether),
            "claimable bond shares should not be zero"
        );
    }

    function test_WithLockedMoreThanBondPlusRewards() public {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });
        _lock({ amount: 1.05 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            stETH.getSharesByPooledEth(0.05 ether),
            "claimable bond shares should not be zero"
        );
    }

    function test_WithCurveAndLocked() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(14.1 ether),
            1 wei,
            "claimable bond shares should be equal to the curve discount + rewards - locked"
        );
    }

    function test_WithOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(2.1 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond + rewards"
        );
    }

    function test_WithBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            stETH.getSharesByPooledEth(0.1 ether),
            "claimable bond shares should be equal to rewards"
        );
    }

    function test_WithBondDebt() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });
        _debt({ amount: 1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(2.1 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond"
        );
    }

    function test_WithExcessBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(1.1 ether),
            1 wei,
            "claimable bond shares should be equal to the excess bond"
        );
    }

    function test_WithExcessBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertApproxEqAbs(
            claimableBondShares,
            stETH.getSharesByPooledEth(3.1 ether),
            1 wei,
            "claimable bond shares should be equal to a single validator bond + excess bond + rewards"
        );
    }

    function test_WithMissingBond() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(claimableBondShares, 0, "claimable bond shares should be zero");
    }
}
