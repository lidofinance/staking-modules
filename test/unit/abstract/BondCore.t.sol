// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Test, Vm } from "forge-std/Test.sol";

import { BondCore } from "src/abstract/BondCore.sol";

import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { BurnerMock } from "../../helpers/mocks/BurnerMock.sol";
import { WithdrawalQueueMock } from "../../helpers/mocks/WithdrawalQueueMock.sol";

import { IStETH } from "src/interfaces/IStETH.sol";
import { IBurner } from "src/interfaces/IBurner.sol";
import { IBondCore } from "src/interfaces/IBondCore.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";

contract BondCoreTestable is BondCore {
    constructor(address lidoLocator) BondCore(lidoLocator) {}

    function depositETH(address from, uint256 nodeOperatorId) external payable {
        _depositETH(from, nodeOperatorId);
    }

    function depositStETH(address from, uint256 nodeOperatorId, uint256 amount) external {
        _depositStETH(from, nodeOperatorId, amount);
    }

    function depositWstETH(address from, uint256 nodeOperatorId, uint256 amount) external {
        _depositWstETH(from, nodeOperatorId, amount);
    }

    function claimUnstETH(
        uint256 nodeOperatorId,
        uint256 amountToClaim,
        uint256 claimableShares,
        address to
    ) external returns (uint256) {
        return _claimUnstETH(nodeOperatorId, amountToClaim, claimableShares, to);
    }

    function claimStETH(
        uint256 nodeOperatorId,
        uint256 amountToClaim,
        uint256 claimableShares,
        address to
    ) external returns (uint256) {
        return _claimStETH(nodeOperatorId, amountToClaim, claimableShares, to);
    }

    function claimWstETH(
        uint256 nodeOperatorId,
        uint256 amountToClaim,
        uint256 claimableShares,
        address to
    ) external returns (uint256) {
        return _claimWstETH(nodeOperatorId, amountToClaim, claimableShares, to);
    }

    function getClaimableBondShares(uint256 nodeOperatorId) external view returns (uint256) {
        // In base BondCore, all bond shares are claimable
        return getBondShares(nodeOperatorId);
    }

    function burn(uint256 nodeOperatorId, uint256 amount) external returns (uint256) {
        return _burn(nodeOperatorId, amount);
    }

    function charge(uint256 nodeOperatorId, uint256 amount, address recipient) external {
        _charge(nodeOperatorId, amount, recipient);
    }

    function creditBondShares(uint256 nodeOperatorId, uint256 shares) external {
        _creditBondShares(nodeOperatorId, shares);
    }
}

abstract contract BondCoreTestBase is Test, Fixtures, Utilities {
    LidoLocatorMock internal locator;
    WstETHMock internal wstETH;
    LidoMock internal stETH;
    WithdrawalQueueMock internal wq;

    BurnerMock internal burner;

    BondCoreTestable public bondCore;

    address internal user;
    address internal testChargePenaltyRecipient;

    function setUp() public {
        (locator, wstETH, stETH, burner, wq) = initLido();

        user = nextAddress("USER");
        testChargePenaltyRecipient = nextAddress("CHARGERECIPIENT");

        bondCore = new BondCoreTestable(address(locator));

        vm.startPrank(address(bondCore));
        stETH.approve(address(burner), UINT256_MAX);
        stETH.approve(address(wstETH), UINT256_MAX);
        stETH.approve(address(wq), UINT256_MAX);
        vm.stopPrank();
    }

    function _deposit(uint256 bond) internal {
        vm.deal(user, bond);
        bondCore.depositETH{ value: bond }(user, 0);
    }

    function _prepareForIncreaseBond(uint256 nodeOperatorId, uint256 amount) internal returns (uint256 mintedShares) {
        vm.deal(address(this), amount);
        mintedShares = stETH.submit{ value: amount }(address(0));
        stETH.transferShares(address(bondCore), mintedShares);
    }

    function ethToSharesToEth(uint256 amount) internal view returns (uint256) {
        return stETH.getPooledEthByShares(stETH.getSharesByPooledEth(amount));
    }

    function sharesToEthToShares(uint256 amount) internal view returns (uint256) {
        return stETH.getSharesByPooledEth(stETH.getPooledEthByShares(amount));
    }
}

contract BondCoreConstructorTest is BondCoreTestBase {
    function test_constructor() public view {
        assertEq(address(bondCore.LIDO_LOCATOR()), address(locator));
        assertEq(address(bondCore.LIDO()), locator.lido());
        assertEq(address(bondCore.WSTETH()), address(wstETH));
        assertEq(address(bondCore.WITHDRAWAL_QUEUE()), address(wq));
    }

    function test_constructor_RevertIf_ZeroLocator() public {
        vm.expectRevert(IBondCore.ZeroLocatorAddress.selector);
        new BondCoreTestable(address(0));
    }
}

contract BondCoreBondGettersTest is BondCoreTestBase {
    function test_getBondShares() public {
        _deposit(1 ether);
        assertEq(bondCore.getBondShares(0), stETH.getSharesByPooledEth(1 ether));
    }

    function test_getBond() public {
        _deposit(1 ether);
        assertEq(bondCore.getBond(0), ethToSharesToEth(1 ether));
    }

    function test_getBondDebt() public {
        bondCore.burn(0, 1 ether);
        assertEq(bondCore.getBondDebt(0), 1 ether);
    }
}

contract BondCoreETHTest is BondCoreTestBase {
    function test_depositETH() public {
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedETH(0, user, 1 ether);

        bondCore.depositETH{ value: 1 ether }(user, 0);
        uint256 shares = stETH.getSharesByPooledEth(1 ether);

        assertEq(bondCore.getBondShares(0), shares);
        assertEq(bondCore.totalBondShares(), shares);
        assertEq(stETH.sharesOf(address(bondCore)), shares);
    }

    function test_depositETH_coversDebt() public {
        uint256 debt = 1 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(debt);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, debt);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedETH(0, user, deposit);

        bondCore.depositETH{ value: deposit }(user, 0);

        assertEq(bondCore.getBondDebt(0), 0);
    }

    function test_depositETH_coversDebtPartially() public {
        uint256 debt = 3 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(deposit);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, deposit);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedETH(0, user, deposit);

        bondCore.depositETH{ value: deposit }(user, 0);

        assertEq(bondCore.getBondDebt(0), debt - deposit);
    }

    function test_claimUnstETH() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedUnstETH(0, user, claimableETH, 0);
        uint256 requestId = bondCore.claimUnstETH(0, claimableETH + 1, bondCore.getClaimableBondShares(0), user);

        assertEq(requestId, 0);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - sharesToEthToShares(claimableShares));
        assertEq(bondCore.totalBondShares(), bondSharesBefore - sharesToEthToShares(claimableShares));
    }

    function test_claimUnstETH_WhenClaimableIsZero() public {
        assertEq(bondCore.getBondShares(0), 0);

        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimUnstETH(0, 100, 0, user);
    }

    function test_claimUnstETH_WhenToClaimIsZero() public {
        _deposit(2 ether);
        uint256 claimable = bondCore.getClaimableBondShares(0);
        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimUnstETH(0, 0, claimable, user);
    }

    function test_claimUnstETH_WhenToClaimIsMoreThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedUnstETH(0, user, claimableETH, 0);
        bondCore.claimUnstETH(0, 2 ether, bondCore.getClaimableBondShares(0), user);

        assertEq(bondCore.getBondShares(0), bondSharesBefore - sharesToEthToShares(claimableShares));
        assertEq(bondCore.totalBondShares(), bondSharesBefore - sharesToEthToShares(claimableShares));
    }

    function test_claimUnstETH_WhenToClaimIsLessThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = stETH.getSharesByPooledEth(0.25 ether);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedUnstETH(0, user, claimableETH, 0);
        bondCore.claimUnstETH(0, 0.25 ether, bondCore.getClaimableBondShares(0), user);

        assertEq(bondCore.getBondShares(0), bondSharesBefore - sharesToEthToShares(claimableShares));
        assertEq(bondCore.totalBondShares(), bondSharesBefore - sharesToEthToShares(claimableShares));
    }
}

contract BondCoreStETHTest is BondCoreTestBase {
    function test_depositStETH() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        stETH.submit{ value: 1 ether }(address(0));
        stETH.approve(address(bondCore), 1 ether);
        vm.stopPrank();

        uint256 depositedAmount = ethToSharesToEth(1 ether);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedStETH(0, user, depositedAmount);

        bondCore.depositStETH(user, 0, 1 ether);
        uint256 shares = stETH.getSharesByPooledEth(1 ether);

        assertEq(bondCore.getBondShares(0), shares);
        assertEq(bondCore.totalBondShares(), shares);
        assertEq(stETH.sharesOf(address(bondCore)), shares);
    }

    function test_depositStETH_coversDebt() public {
        uint256 debt = 1 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        vm.deal(user, deposit);
        vm.startPrank(user);
        stETH.submit{ value: deposit }(address(0));
        stETH.approve(address(bondCore), deposit);
        vm.stopPrank();

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(debt);
        uint256 depositedAmount = ethToSharesToEth(deposit);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, debt);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedStETH(0, user, depositedAmount);

        bondCore.depositStETH(user, 0, deposit);

        assertEq(bondCore.getBondDebt(0), 0);
    }

    function test_depositStETH_coversDebtPartially() public {
        uint256 debt = 3 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        vm.deal(user, deposit);
        vm.startPrank(user);
        stETH.submit{ value: deposit }(address(0));
        stETH.approve(address(bondCore), deposit);
        vm.stopPrank();

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(deposit);
        uint256 depositedAmount = ethToSharesToEth(deposit);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, deposit);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedStETH(0, user, depositedAmount);

        bondCore.depositStETH(user, 0, deposit);

        assertEq(bondCore.getBondDebt(0), debt - deposit);
    }

    function test_claimStETH() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedStETH(0, user, claimableETH);
        uint256 claimedShares = bondCore.claimStETH(0, claimableETH, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedShares, claimableShares);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableShares);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableShares);
        assertEq(stETH.sharesOf(user), claimableShares);
    }

    function test_claimStETH_WhenClaimableIsZero() public {
        assertEq(bondCore.getBondShares(0), 0);

        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimStETH(0, 100, 0, user);
    }

    function test_claimStETH_WhenToClaimIsZero() public {
        _deposit(2 ether);

        uint256 claimable = bondCore.getClaimableBondShares(0);
        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimStETH(0, 0, claimable, user);
    }

    function test_claimStETH_WhenToClaimIsMoreThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedStETH(0, user, claimableETH);
        uint256 claimedShares = bondCore.claimStETH(0, 2 ether, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedShares, claimableShares);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableShares);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableShares);
        assertEq(stETH.sharesOf(user), claimableShares);
    }

    function test_claimStETH_WhenToClaimIsLessThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = stETH.getSharesByPooledEth(0.25 ether);
        uint256 claimableETH = stETH.getPooledEthByShares(claimableShares);
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedStETH(0, user, claimableETH);
        uint256 claimedShares = bondCore.claimStETH(0, 0.25 ether, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedShares, claimableShares);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableShares);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableShares);
        assertEq(stETH.sharesOf(user), claimableShares);
    }
}

contract BondCoreWstETHTest is BondCoreTestBase {
    function test_depositWstETH() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        stETH.submit{ value: 1 ether }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(1 ether);
        vm.stopPrank();

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedWstETH(0, user, wstETHAmount);

        bondCore.depositWstETH(user, 0, wstETHAmount);

        uint256 shares = stETH.getSharesByPooledEth(wstETH.getStETHByWstETH(wstETHAmount));
        assertEq(bondCore.getBondShares(0), shares);
        assertEq(bondCore.totalBondShares(), shares);
        assertEq(stETH.sharesOf(address(bondCore)), shares);
    }

    function test_depositWstETH_coversDebt() public {
        uint256 debt = 1 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        vm.deal(user, deposit);
        vm.startPrank(user);
        stETH.submit{ value: deposit }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(deposit);
        vm.stopPrank();

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(debt);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, debt);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedWstETH(0, user, wstETHAmount);

        bondCore.depositWstETH(user, 0, wstETHAmount);

        assertEq(bondCore.getBondDebt(0), 0);
    }

    function test_depositWstETH_coversDebtPartially() public {
        uint256 debt = 3 ether;
        uint256 deposit = 2 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        vm.deal(user, deposit);
        vm.startPrank(user);
        stETH.submit{ value: deposit }(address(0));
        stETH.approve(address(wstETH), UINT256_MAX);
        uint256 wstETHAmount = wstETH.wrap(deposit);
        vm.stopPrank();

        uint256 toBurn = ethToSharesToEth(debt);
        uint256 burned = ethToSharesToEth(ethToSharesToEth(deposit));
        uint256 covered = ethToSharesToEth(deposit);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, toBurn, burned);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, covered);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDepositedWstETH(0, user, wstETHAmount);

        bondCore.depositWstETH(user, 0, wstETHAmount);

        assertEq(bondCore.getBondDebt(0), debt - ethToSharesToEth(deposit));
    }

    function test_claimWstETH() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableWstETH = stETH.getSharesByPooledEth(stETH.getPooledEthByShares(claimableShares));
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedWstETH(0, user, claimableWstETH);
        uint256 claimedWstETH = bondCore.claimWstETH(0, claimableShares, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedWstETH, claimableWstETH);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableWstETH);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableWstETH);
        assertEq(wstETH.balanceOf(user), claimableWstETH);
    }

    function test_claimWstETH_WhenClaimableIsZero() public {
        assertEq(bondCore.getBondShares(0), 0);

        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimWstETH(0, 100, 0, user);
    }

    function test_claimWstETH_WhenToClaimIsZero() public {
        _deposit(2 ether);

        uint256 claimable = bondCore.getClaimableBondShares(0);
        vm.expectRevert(IBondCore.NothingToClaim.selector);
        bondCore.claimWstETH(0, 0, claimable, user);
    }

    function test_claimWstETH_WhenToClaimIsMoreThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = bondCore.getClaimableBondShares(0);
        uint256 claimableWstETH = stETH.getSharesByPooledEth(stETH.getPooledEthByShares(claimableShares));
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedWstETH(0, user, claimableWstETH);
        uint256 claimedWstETH = bondCore.claimWstETH(0, claimableShares + 1, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedWstETH, claimableWstETH);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableWstETH);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableWstETH);
        assertEq(wstETH.balanceOf(user), claimableWstETH);
    }

    function test_claimWstETH_WhenToClaimIsLessThanClaimable() public {
        _deposit(1 ether);

        uint256 claimableShares = stETH.getSharesByPooledEth(0.25 ether);
        uint256 claimableWstETH = stETH.getSharesByPooledEth(stETH.getPooledEthByShares(claimableShares));
        uint256 bondSharesBefore = bondCore.getBondShares(0);

        vm.expectEmit(address(bondCore));
        emit IBondCore.BondClaimedWstETH(0, user, claimableWstETH);
        uint256 claimedWstETH = bondCore.claimWstETH(0, claimableShares, bondCore.getClaimableBondShares(0), user);

        assertEq(claimedWstETH, claimableWstETH);
        assertEq(bondCore.getBondShares(0), bondSharesBefore - claimableWstETH);
        assertEq(bondCore.totalBondShares(), bondSharesBefore - claimableWstETH);
        assertEq(wstETH.balanceOf(user), claimableWstETH);
    }
}

contract BondCoreBurnTest is BondCoreTestBase {
    function test_burn_LessThanDeposit() public {
        _deposit(32 ether);

        uint256 shares = stETH.getSharesByPooledEth(1 ether);
        uint256 burned = stETH.getPooledEthByShares(shares);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, burned, burned);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        vm.expectCall(locator.burner(), abi.encodeWithSelector(IBurner.requestBurnMyShares.selector, shares));
        uint256 unburned = bondCore.burn(0, 1 ether);
        uint256 bondSharesAfter = bondCore.getBondShares(0);

        assertEq(bondSharesAfter, bondSharesBefore - shares, "bond shares should be decreased by burning");
        assertEq(bondCore.totalBondShares(), bondSharesAfter);
        assertEq(unburned, 0, "should be fully burned");
        assertEq(bondCore.getBondDebt(0), 0, "debt should be 0");
    }

    function test_burn_MoreThanDeposit() public {
        _deposit(32 ether);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        uint256 burnShares = stETH.getSharesByPooledEth(33 ether);
        uint256 amountToBurn = 32 ether;
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(
            0,
            stETH.getPooledEthByShares(burnShares),
            stETH.getPooledEthByShares(bondSharesBefore)
        );
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtIncreased(0, 1 ether);

        vm.expectCall(
            locator.burner(),
            abi.encodeWithSelector(IBurner.requestBurnMyShares.selector, stETH.getSharesByPooledEth(amountToBurn))
        );

        uint256 unburned = bondCore.burn(0, 33 ether);

        assertEq(bondCore.getBondShares(0), 0, "bond shares should be 0 after burning");
        assertEq(bondCore.totalBondShares(), 0);
        assertEq(unburned, 1 ether, "should not be fully burned");
        assertEq(bondCore.getBondDebt(0), 1 ether, "debt should be 1 ether");
    }

    function test_burn_EqualToDeposit() public {
        _deposit(32 ether);

        uint256 shares = stETH.getSharesByPooledEth(32 ether);
        uint256 burned = stETH.getPooledEthByShares(shares);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondBurned(0, burned, burned);

        vm.expectCall(locator.burner(), abi.encodeWithSelector(IBurner.requestBurnMyShares.selector, shares));

        uint256 unburned = bondCore.burn(0, 32 ether);

        assertEq(bondCore.getBondShares(0), 0, "bond shares should be 0 after burning");
        assertEq(bondCore.totalBondShares(), 0);
        assertEq(unburned, 0, "should be fully burned");
        assertEq(bondCore.getBondDebt(0), 0, "debt should be 0");
    }

    function test_burn_ZeroAmount() public {
        _deposit(32 ether);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        uint256 totalBondSharesBefore = bondCore.totalBondShares();

        // Should not emit any events for zero burn
        vm.recordLogs();
        uint256 unburned = bondCore.burn(0, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no events were emitted
        assertEq(logs.length, 0, "no events should be emitted for zero burn");

        // Verify no state changes
        assertEq(bondCore.getBondShares(0), bondSharesBefore, "bond shares should remain unchanged for zero burn");
        assertEq(
            bondCore.totalBondShares(),
            totalBondSharesBefore,
            "total bond shares should remain unchanged for zero burn"
        );
        assertEq(unburned, 0, "should be fully burned");
        assertEq(bondCore.getBondDebt(0), 0, "debt should be 0");
    }
}

contract BondCoreChargeTest is BondCoreTestBase {
    function test_charge_LessThanDeposit() public {
        _deposit(32 ether);

        uint256 shares = stETH.getSharesByPooledEth(1 ether);
        uint256 charged = stETH.getPooledEthByShares(shares);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondCharged(0, charged, charged);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        vm.expectCall(
            locator.lido(),
            abi.encodeWithSelector(IStETH.transferShares.selector, testChargePenaltyRecipient, shares)
        );
        bondCore.charge(0, 1 ether, testChargePenaltyRecipient);
        uint256 bondSharesAfter = bondCore.getBondShares(0);

        assertEq(bondSharesAfter, bondSharesBefore - shares, "bond shares should be decreased by charging");
        assertEq(bondCore.totalBondShares(), bondSharesAfter);
    }

    function test_charge_MoreThanDeposit() public {
        _deposit(32 ether);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        uint256 chargeShares = stETH.getSharesByPooledEth(33 ether);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondCharged(
            0,
            stETH.getPooledEthByShares(chargeShares),
            stETH.getPooledEthByShares(bondSharesBefore)
        );

        vm.expectCall(
            locator.lido(),
            abi.encodeWithSelector(
                IStETH.transferShares.selector,
                testChargePenaltyRecipient,
                stETH.getSharesByPooledEth(32 ether)
            )
        );
        bondCore.charge(0, 33 ether, testChargePenaltyRecipient);

        assertEq(bondCore.getBondShares(0), 0, "bond shares should be 0 after charging");
        assertEq(bondCore.totalBondShares(), 0);
    }

    function test_charge_EqualToDeposit() public {
        _deposit(32 ether);

        uint256 shares = stETH.getSharesByPooledEth(32 ether);
        uint256 charged = stETH.getPooledEthByShares(shares);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondCharged(0, charged, charged);

        vm.expectCall(
            locator.lido(),
            abi.encodeWithSelector(IStETH.transferShares.selector, testChargePenaltyRecipient, shares)
        );

        bondCore.charge(0, 32 ether, testChargePenaltyRecipient);

        assertEq(bondCore.getBondShares(0), 0, "bond shares should be 0 after charging");
        assertEq(bondCore.totalBondShares(), 0);
    }

    function test_charge_ZeroAmount() public {
        _deposit(32 ether);

        uint256 bondSharesBefore = bondCore.getBondShares(0);
        uint256 totalBondSharesBefore = bondCore.totalBondShares();

        // Should not emit any events for zero charge
        vm.recordLogs();
        bondCore.charge(0, 0, testChargePenaltyRecipient);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no events were emitted
        assertEq(logs.length, 0, "no events should be emitted for zero charge");

        // Verify no state changes
        assertEq(bondCore.getBondShares(0), bondSharesBefore, "bond shares should remain unchanged for zero charge");
        assertEq(
            bondCore.totalBondShares(),
            totalBondSharesBefore,
            "total bond shares should remain unchanged for zero charge"
        );
    }
}

contract BondCoreDebtTest is BondCoreTestBase {
    function test_coverBondDebt_fullCover() public {
        uint256 debt = 5 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        uint256 sharesToIncrease = _prepareForIncreaseBond(0, 10 ether);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, debt);
        bondCore.creditBondShares(0, sharesToIncrease);

        assertEq(bondCore.getBondDebt(0), 0);
    }

    function test_coverBondDebt_partialCover() public {
        uint256 debt = 10 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        uint256 bondAmount = 5 ether;
        uint256 sharesToIncrease = _prepareForIncreaseBond(0, bondAmount);
        vm.expectEmit(address(bondCore));
        emit IBondCore.BondDebtCovered(0, bondAmount);
        bondCore.creditBondShares(0, sharesToIncrease);

        assertEq(bondCore.getBondDebt(0), debt - bondAmount);
    }

    function test_coverBondDebt_NoDebt() public {
        assertEq(bondCore.getBondDebt(0), 0);

        uint256 bondAmount = 10 ether;
        uint256 sharesToIncrease = _prepareForIncreaseBond(0, bondAmount);

        // Should not emit any events when there is no debt
        vm.recordLogs();
        bondCore.creditBondShares(0, sharesToIncrease);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no events were emitted
        assertEq(logs.length, 0, "no events should be emitted when no debt");
    }

    function test_coverBondDebt_noBondToCoverDebt() public {
        uint256 debt = 10 ether;
        bondCore.burn(0, debt);
        assertEq(bondCore.getBondDebt(0), debt);

        // Should not emit any events when there is no bond to cover debt
        vm.recordLogs();
        bondCore.creditBondShares(0, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no events were emitted
        assertEq(logs.length, 0, "no events should be emitted when no bond to cover debt");
        assertEq(bondCore.getBondDebt(0), debt);
    }
}
