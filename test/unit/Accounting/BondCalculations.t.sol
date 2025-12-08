// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { BaseTest, BondStateBaseTest, FailedReceiverStub, GetRequiredBondBaseTest, GetRequiredBondForKeysBaseTest, RewardsBaseTest } from "./_Base.t.sol";
import { Accounting } from "src/Accounting.sol";
import { IBondCurve } from "src/interfaces/IBondCurve.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";
import { IBurner } from "src/interfaces/IBurner.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

// Combined bond tests: curves, claimable, locking, required bonds, summaries

contract BondCurveTest is BaseTest {
    function test_addBondCurve() public {
        IBondCurve.BondCurveIntervalInput[]
            memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });
        vm.prank(admin);
        uint256 addedId = accounting.addBondCurve(curvePoints);

        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo({
            curveId: addedId
        });

        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
    }

    function test_addBondCurve_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.MANAGE_BOND_CURVES_ROLE());
        vm.prank(stranger);
        accounting.addBondCurve(new IBondCurve.BondCurveIntervalInput[](0));
    }

    function test_updateBondCurve() public assertInvariants {
        IBondCurve.BondCurveIntervalInput[]
            memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        uint256 toUpdate = 0;

        vm.prank(admin);
        accounting.updateBondCurve(toUpdate, curvePoints);

        IBondCurve.BondCurveData memory curve = accounting.getCurveInfo({
            curveId: toUpdate
        });

        assertEq(curve.intervals[0].minBond, 2 ether);
        assertEq(curve.intervals[0].trend, 2 ether);
    }

    function test_updateBondCurve_RevertWhen_DoesNotHaveRole() public {
        expectRoleRevert(stranger, accounting.MANAGE_BOND_CURVES_ROLE());
        vm.prank(stranger);
        accounting.updateBondCurve(
            0,
            new IBondCurve.BondCurveIntervalInput[](0)
        );
    }

    function test_updateBondCurve_RevertWhen_InvalidBondCurveId() public {
        vm.expectRevert(IBondCurve.InvalidBondCurveId.selector);
        vm.prank(admin);
        accounting.updateBondCurve(
            1,
            new IBondCurve.BondCurveIntervalInput[](0)
        );
    }

    function test_setBondCurve() public assertInvariants {
        IBondCurve.BondCurveIntervalInput[]
            memory curvePoints = new IBondCurve.BondCurveIntervalInput[](1);
        curvePoints[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });

        mock_getNodeOperatorsCount(1);

        vm.startPrank(admin);

        uint256 addedId = accounting.addBondCurve(curvePoints);

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
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

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
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

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
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

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
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

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting.getClaimableBondShares(0);

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
    }
}

contract LockBondETHTest is BaseTest {
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

    function test_lockBondETH() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);
        assertEq(accounting.getActualLockedBond(0), 1 ether);
    }

    function test_lockBondETH_RevertWhen_SenderIsNotModule() public {
        mock_getNodeOperatorsCount(1);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.lockBondETH(0, 1 ether);
    }

    function test_lockBondETH_RevertWhen_LockOverflow() public {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);
        assertEq(accounting.getActualLockedBond(0), 1 ether);

        vm.expectRevert();
        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, type(uint256).max);
    }

    function test_releaseLockedBondETH() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);

        vm.prank(address(stakingModule));
        accounting.releaseLockedBondETH(0, 0.4 ether);

        assertEq(accounting.getActualLockedBond(0), 0.6 ether);
    }

    function test_releaseLockedBondETH_RevertWhen_SenderIsNotModule() public {
        mock_getNodeOperatorsCount(1);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.releaseLockedBondETH(0, 1 ether);
    }

    function test_compensateLockedBondETH() public assertInvariants {
        mock_getNodeOperatorsCount(1);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);

        vm.expectEmit(address(accounting));
        emit IAccounting.BondLockCompensated(0, 0.4 ether);

        vm.deal(address(stakingModule), 0.4 ether);
        vm.prank(address(stakingModule));
        accounting.compensateLockedBondETH{ value: 0.4 ether }(0);

        assertEq(accounting.getActualLockedBond(0), 0.6 ether);
    }

    function test_compensateLockedBondETH_RevertWhen_ReceiveFailed()
        public
        assertInvariants
    {
        mock_getNodeOperatorsCount(1);
        FailedReceiverStub failedReceiver = new FailedReceiverStub();
        vm.mockCall(
            address(locator),
            abi.encodeWithSelector(locator.elRewardsVault.selector),
            abi.encode(address(failedReceiver))
        );

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);

        vm.deal(address(stakingModule), 0.4 ether);
        vm.prank(address(stakingModule));
        vm.expectRevert(IAccounting.ElRewardsVaultReceiveFailed.selector);
        accounting.compensateLockedBondETH{ value: 0.4 ether }(0);
    }

    function test_compensateLockedBondETH_RevertWhen_SenderIsNotModule()
        public
    {
        mock_getNodeOperatorsCount(1);
        vm.deal(stranger, 1 ether);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(0, 1 ether);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        vm.prank(stranger);
        accounting.compensateLockedBondETH{ value: 1 ether }(0);
    }

    function test_settleLockedBondETH() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(noId, amount);
        assertEq(accounting.getActualLockedBond(noId), amount);

        vm.prank(address(stakingModule));
        bool applied = accounting.settleLockedBondETH(noId);
        assertEq(accounting.getActualLockedBond(noId), 0);
        assertTrue(applied);
    }

    function test_settleLockedBondETH_noLocked() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        vm.deal(address(stakingModule), 32 ether);
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, noId);
        uint256 bond = accounting.getBondShares(noId);

        vm.prank(address(stakingModule));
        bool applied = accounting.settleLockedBondETH(noId);
        assertEq(accounting.getActualLockedBond(noId), 0);
        assertEq(accounting.getBondShares(noId), bond);
        assertFalse(applied);
    }

    function test_settleLockedBondETH_noBond() public assertInvariants {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;
        uint256 amount = 1 ether;

        vm.startPrank(address(stakingModule));
        accounting.lockBondETH(noId, amount);

        expectNoCall(
            address(burner),
            abi.encodeWithSelector(IBurner.requestBurnShares.selector)
        );
        bool applied = accounting.settleLockedBondETH(noId);
        vm.stopPrank();

        Accounting.BondLockData memory bondLockAfter = accounting
            .getLockedBondInfo(0);

        assertEq(bondLockAfter.amount, 1 ether);
        assertEq(bondLockAfter.until, type(uint128).max);
        assertEq(accounting.getBondShares(noId), 0);
        assertTrue(applied);
    }

    function test_settleLockedBondETH_partialBurn_setsInfiniteLockToRestOnly()
        public
        assertInvariants
    {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;

        uint256 bond = 10 ether;
        uint256 locked = 15 ether;
        addBond(noId, bond);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(noId, locked);

        uint256 bondSharesBefore = accounting.getBondShares(noId);
        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(
                IBurner.requestBurnShares.selector,
                address(accounting),
                bondSharesBefore
            )
        );

        vm.prank(address(stakingModule));
        accounting.settleLockedBondETH(noId);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(
            noId
        );
        assertApproxEqAbs(lockAfter.amount, locked - bond, 1);
        assertEq(lockAfter.until, type(uint128).max);
    }

    function test_settleLockedBondETH_restZero_removesLock()
        public
        assertInvariants
    {
        mock_getNodeOperatorsCount(1);
        uint256 noId = 0;

        uint256 amount = 5 ether;
        addBond(noId, amount);

        vm.prank(address(stakingModule));
        accounting.lockBondETH(noId, amount);

        vm.prank(address(stakingModule));
        accounting.settleLockedBondETH(noId);

        Accounting.BondLockData memory lockAfter = accounting.getLockedBondInfo(
            noId
        );
        assertEq(lockAfter.amount, 0);
        assertEq(lockAfter.until, 0);
        assertEq(accounting.getActualLockedBond(noId), 0);
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

    function test_OneWithdrawnOneAddedValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), 32 ether);
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeys(0, 0),
            required - current
        );
    }

    function test_WithBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeys(0, 1),
            2 ether - (current - required)
        );
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeys(0, 1), 0);
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeys(0, 0),
            required - current
        );
    }

    function test_WithMissingBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeys(0, 0),
            required - current
        );
    }

    function test_WithMissingBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeys(0, 1),
            required - current + 2 ether
        );
    }
}

contract GetRequiredWstETHBondTest is GetRequiredBondBaseTest {
    function test_default() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_OneWithdrawnOneAddedValidator()
        public
        override
        assertInvariants
    {
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
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 1), 0);
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 0), 0);
    }

    function test_WithExcessBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        assertEq(accounting.getRequiredBondForNextKeysWstETH(0, 1), 0);
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithMissingBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        (uint256 current, uint256 required) = accounting.getBondSummary(0);
        assertEq(
            accounting.getRequiredBondForNextKeysWstETH(0, 0),
            wstETH.getWstETHByStETH(required - current)
        );
    }

    function test_WithMissingBondAndOneWithdrawnAndOneAddedValidator()
        public
        override
    {
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
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(1, 0),
            wstETH.getWstETHByStETH(2 ether)
        );
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(2, 0),
            wstETH.getWstETHByStETH(4 ether)
        );
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(8, 0),
            wstETH.getWstETHByStETH(16 ether)
        );
    }

    function test_WithCurve() public override assertInvariants {
        IBondCurve.BondCurveIntervalInput[]
            memory defaultCurve = new IBondCurve.BondCurveIntervalInput[](2);
        defaultCurve[0] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 1,
            trend: 2 ether
        });
        defaultCurve[1] = IBondCurve.BondCurveIntervalInput({
            minKeysCount: 2,
            trend: 1 ether
        });

        vm.startPrank(admin);
        uint256 curveId = accounting.addBondCurve(defaultCurve);
        assertEq(accounting.getBondAmountByKeysCountWstETH(0, curveId), 0);
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(1, curveId),
            wstETH.getWstETHByStETH(2 ether)
        );
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(2, curveId),
            wstETH.getWstETHByStETH(3 ether)
        );
        assertEq(
            accounting.getBondAmountByKeysCountWstETH(15, curveId),
            wstETH.getWstETHByStETH(16 ether)
        );
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

    function test_WithBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
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

    function test_WithExcessBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
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

    function test_WithMissingBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
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
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithCurve() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(17 ether));
    }

    function test_WithLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(33 ether));
    }

    function test_WithLocked_MoreThanBond() public assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _lock({ amount: 100500 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(100532 ether));
    }

    function test_WithCurveAndLocked() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _curve(curveWithDiscount);
        _lock({ amount: 1 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(18 ether));
    }

    function test_WithOneWithdrawnValidator() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 1 });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, 0 ether);
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(32 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(32 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithExcessBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(33 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithExcessBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 33 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(33 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }

    function test_WithMissingBond() public override assertInvariants {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(29 ether));
        assertEq(required, stETH.getSharesByPooledEth(32 ether));
    }

    function test_WithMissingBondAndOneWithdrawnValidator()
        public
        override
        assertInvariants
    {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 29 ether });
        (uint256 current, uint256 required) = accounting.getBondSummaryShares(
            0
        );
        assertEq(current, stETH.getSharesByPooledEth(29 ether));
        assertEq(required, stETH.getSharesByPooledEth(30 ether));
    }
}

contract ClaimableRewardsAndBondSharesTest is RewardsBaseTest {
    function test_default() public override {
        _operator({ ongoing: 16, withdrawn: 0 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            stETH.getSharesByPooledEth(0.1 ether),
            "claimable bond shares should be equal to rewards"
        );
    }

    function test_WithBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 32 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

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

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
    }

    function test_WithMissingBondAndOneWithdrawnValidator() public override {
        _operator({ ongoing: 16, withdrawn: 1 });
        _deposit({ bond: 16 ether });
        _rewards({ fee: 0.1 ether });

        uint256 claimableBondShares = accounting
            .getClaimableRewardsAndBondShares(0, leaf.shares, leaf.proof);

        assertEq(
            claimableBondShares,
            0,
            "claimable bond shares should be zero"
        );
    }
}
