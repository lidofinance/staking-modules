// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IBaseModule } from "src/interfaces/IBaseModule.sol";

import { StETHMock } from "../../helpers/mocks/StETHMock.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";

import { BaseTest } from "./_Base.t.sol";

// Combined deposit tests: ETH, stETH, wstETH (both regular and permissionless)

contract DepositEthTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositETH() public assertInvariants {
        vm.deal(address(stakingModule), 32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(32 ether);

        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 32 ether }(user, 0);

        assertEq(
            address(stakingModule).balance,
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositETH_zeroAmount() public assertInvariants {
        vm.prank(address(stakingModule));
        accounting.depositETH{ value: 0 ether }(user, 0);

        assertEq(
            address(stakingModule).balance,
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositETH_revertWhen_SenderIsNotModule() public {
        vm.deal(stranger, 32 ether);
        vm.prank(stranger);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        accounting.depositETH{ value: 32 ether }(stranger, 0);
    }
}

contract DepositStEthTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositStETH() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.prank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));

        vm.prank(address(stakingModule));
        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_zeroAmount() public assertInvariants {
        vm.prank(address(stakingModule));
        accounting.depositStETH(
            user,
            0,
            0 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositStETH_withoutPermitButWithAllowance()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(stakingModule));
        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_withPermit() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.prank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));

        vm.prank(address(stakingModule));
        vm.expectEmit(address(stETH));
        emit StETHMock.Approval(user, address(accounting), 32 ether);

        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithLess()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), 1 ether);
        vm.stopPrank();

        vm.expectEmit(address(stETH));
        emit StETHMock.Approval(user, address(accounting), 32 ether);

        vm.recordLogs();

        vm.prank(address(stakingModule));
        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            2,
            "should emit only one event about approve and deposit"
        );
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithInf()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.prank(address(stakingModule));

        vm.recordLogs();

        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithTheSame()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), 32 ether);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(stakingModule));
        accounting.depositStETH(
            user,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositStETH_revertWhen_SenderIsNotModule() public {
        vm.prank(stranger);

        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        accounting.depositStETH(
            stranger,
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}

contract DepositWstEthTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositWstETH() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        vm.stopPrank();

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_zeroAmount() public assertInvariants {
        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            0 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositWstETH_withoutPermitButWithAllowance()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        wstETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_withPermit() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        vm.stopPrank();

        vm.expectEmit(address(wstETH));
        emit WstETHMock.Approval(user, address(accounting), 32 ether);

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            accounting.totalBondShares(),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithLess()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), 1 ether);
        vm.stopPrank();

        vm.expectEmit(address(wstETH));
        emit WstETHMock.Approval(user, address(accounting), 32 ether);

        vm.recordLogs();

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            2,
            "should emit only one event about approve and deposit"
        );
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithInf()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithTheSame()
        public
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), 32 ether);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(stakingModule));
        accounting.depositWstETH(
            user,
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositWstETH_revertWhen_SenderIsNotModule() public {
        vm.prank(stranger);
        vm.expectRevert(IAccounting.SenderIsNotModule.selector);
        accounting.depositWstETH(
            stranger,
            0,
            100,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}

contract DepositEthPermissionlessTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositETH() public assertInvariants {
        vm.deal(address(user), 32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(32 ether);

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );
        vm.prank(address(user));
        accounting.depositETH{ value: 32 ether }(0);

        assertEq(
            address(user).balance,
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositETH_zeroAmount() public assertInvariants {
        vm.prank(address(user));
        accounting.depositETH{ value: 0 ether }(0);

        assertEq(
            address(user).balance,
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositETH_revertWhen_OperatorDoesNotExist() public {
        mock_getNodeOperatorsCount(0);
        vm.deal(user, 32 ether);

        vm.expectRevert(IAccounting.NodeOperatorDoesNotExist.selector);
        accounting.depositETH{ value: 32 ether }(0);
    }
}

contract DepositStEthPermissionlessTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositStETH() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.prank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );

        vm.prank(user);
        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: 0,
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_zeroAmount() public assertInvariants {
        vm.prank(address(user));
        accounting.depositStETH(
            0,
            0 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositStETH_withoutPermitButWithAllowance()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(user));
        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_withPermit() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.prank(user);
        uint256 sharesToDeposit = stETH.submit{ value: 32 ether }(address(0));

        vm.prank(address(user));
        vm.expectEmit(address(stETH));
        emit StETHMock.Approval(user, address(accounting), 32 ether);

        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            stETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithLess()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), 1 ether);
        vm.stopPrank();

        vm.expectEmit(address(stETH));
        emit StETHMock.Approval(user, address(accounting), 32 ether);

        vm.recordLogs();

        vm.prank(address(user));
        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            2,
            "should emit only one event about approve and deposit"
        );
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithInf()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.prank(address(user));
        vm.recordLogs();

        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositStETH_withPermit_AlreadyPermittedWithTheSame()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(accounting), 32 ether);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(user));
        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositStETH_revertWhen_OperatorDoesNotExist() public {
        mock_getNodeOperatorsCount(0);
        vm.deal(user, 32 ether);

        vm.expectRevert(IAccounting.NodeOperatorDoesNotExist.selector);
        accounting.depositStETH(
            0,
            32 ether,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}

contract DepositWstEthPermissionlessTest is BaseTest {
    function setUp() public override {
        super.setUp();
        mock_getNodeOperatorNonWithdrawnKeys(0);
        mock_getNodeOperatorsCount(1);
    }

    function test_depositWstETH() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        vm.stopPrank();

        vm.expectCall(
            address(accounting.MODULE()),
            abi.encodeWithSelector(
                IBaseModule.updateDepositableValidatorsCount.selector,
                0
            )
        );

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_zeroAmount() public assertInvariants {
        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            0 ether,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            0,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            0,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), 0);
    }

    function test_depositWstETH_withoutPermitButWithAllowance()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        wstETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            stETH.sharesOf(address(accounting)),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_withPermit() public assertInvariants {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        uint256 sharesToDeposit = stETH.getSharesByPooledEth(
            wstETH.getStETHByWstETH(wstETHAmount)
        );
        vm.stopPrank();

        vm.expectEmit(address(wstETH));
        emit WstETHMock.Approval(user, address(accounting), 32 ether);

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            wstETH.balanceOf(user),
            0,
            "user balance should be 0 after deposit"
        );
        assertEq(
            accounting.getBondShares(0),
            sharesToDeposit,
            "bond shares should be equal to deposited shares"
        );
        assertEq(
            accounting.totalBondShares(),
            sharesToDeposit,
            "bond manager shares should be equal to deposited shares"
        );
        assertEq(accounting.totalBondShares(), sharesToDeposit);
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithLess()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), 1 ether);
        vm.stopPrank();

        vm.expectEmit(address(wstETH));
        emit WstETHMock.Approval(user, address(accounting), 32 ether);

        vm.recordLogs();

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            2,
            "should emit only one event about approve and deposit"
        );
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithInf()
        public
        assertInvariants
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), UINT256_MAX);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositWstETH_withPermit_AlreadyPermittedWithTheSame()
        public
    {
        vm.deal(user, 32 ether);
        vm.startPrank(user);
        stETH.submit{ value: 32 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(32 ether);
        wstETH.approve(address(accounting), 32 ether);
        vm.stopPrank();

        vm.recordLogs();

        vm.prank(address(user));
        accounting.depositWstETH(
            0,
            wstETHAmount,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                // mock permit signature
                v: 0,
                r: 0,
                s: 0
            })
        );

        assertEq(
            vm.getRecordedLogs().length,
            1,
            "should emit only one event about deposit"
        );
    }

    function test_depositWstETH_revertWhen_OperatorDoesNotExist() public {
        mock_getNodeOperatorsCount(0);
        vm.deal(user, 32 ether);

        vm.expectRevert(IAccounting.NodeOperatorDoesNotExist.selector);
        accounting.depositWstETH(
            0,
            100,
            IAccounting.PermitInput({
                value: 32 ether,
                deadline: type(uint256).max,
                v: 0,
                r: 0,
                s: 0
            })
        );
    }
}
