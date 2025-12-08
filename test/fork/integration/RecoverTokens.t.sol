// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { PermitHelper } from "../../helpers/Permit.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";

contract RecoverIntegrationTest is
    Test,
    Utilities,
    PermitHelper,
    DeploymentFixtures,
    InvariantAsserts
{
    address internal user;
    address internal recoverer;

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

        recoverer = nextAddress("Recoverer");
        user = nextAddress("User");

        vm.startPrank(module.getRoleMember(module.DEFAULT_ADMIN_ROLE(), 0));
        module.grantRole(module.RECOVERER_ROLE(), recoverer);
        vm.stopPrank();

        handleStakingLimit();
        handleBunkerMode();

        vm.startPrank(
            accounting.getRoleMember(accounting.DEFAULT_ADMIN_ROLE(), 0)
        );
        accounting.grantRole(accounting.RECOVERER_ROLE(), recoverer);
        vm.stopPrank();

        vm.startPrank(
            feeDistributor.getRoleMember(feeDistributor.DEFAULT_ADMIN_ROLE(), 0)
        );
        feeDistributor.grantRole(feeDistributor.RECOVERER_ROLE(), recoverer);
        vm.stopPrank();

        vm.startPrank(oracle.getRoleMember(oracle.DEFAULT_ADMIN_ROLE(), 0));
        oracle.grantRole(oracle.RECOVERER_ROLE(), recoverer);
        vm.stopPrank();
    }

    function test_recoverStETH_fromCSM() public assertInvariants {
        assertEq(lido.sharesOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        uint256 amountStETH = lido.getPooledEthByShares(shares);
        lido.transfer(address(module), amountStETH);
        vm.stopPrank();

        vm.prank(recoverer);
        module.recoverERC20(address(lido), amountStETH);

        assertApproxEqAbs(lido.balanceOf(recoverer), amountStETH, 2 wei);
    }

    function test_recoverETH_fromCSM() public assertInvariants {
        assertEq(recoverer.balance, 0);

        uint256 contractBalance = address(module).balance;

        uint256 amount = 1 ether;
        vm.deal(address(module), amount);

        vm.prank(recoverer);
        module.recoverEther();

        assertEq(recoverer.balance, contractBalance + amount);
    }

    function test_recoverWstETH_fromCSM() public assertInvariants {
        assertEq(wstETH.balanceOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 amountWstETH = wstETH.wrap(lido.getPooledEthByShares(shares));
        wstETH.transfer(address(module), amountWstETH);
        vm.stopPrank();

        vm.prank(recoverer);
        module.recoverERC20(address(wstETH), amountWstETH);

        assertEq(wstETH.balanceOf(recoverer), amountWstETH);
    }

    function test_recoverStETH_fromAccounting() public assertInvariants {
        assertEq(lido.sharesOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.transferShares(address(accounting), shares);
        vm.stopPrank();

        vm.prank(recoverer);
        accounting.recoverStETHShares();

        assertEq(lido.sharesOf(recoverer), shares);
    }

    function test_recoverETH_fromAccounting() public assertInvariants {
        assertEq(recoverer.balance, 0);

        uint256 contractBalance = address(accounting).balance;

        uint256 amount = 1 ether;
        vm.deal(address(accounting), amount);

        vm.prank(recoverer);
        accounting.recoverEther();

        assertEq(recoverer.balance, contractBalance + amount);
    }

    function test_recoverWstETH_fromAccounting() public assertInvariants {
        assertEq(wstETH.balanceOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 amountWstETH = wstETH.wrap(lido.getPooledEthByShares(shares));
        wstETH.transfer(address(accounting), amountWstETH);
        vm.stopPrank();

        vm.prank(recoverer);
        accounting.recoverERC20(address(wstETH), amountWstETH);

        assertEq(wstETH.balanceOf(recoverer), amountWstETH);
    }

    function test_recoverETH_fromFeeDistributor() public assertInvariants {
        assertEq(recoverer.balance, 0);

        uint256 contractBalance = address(feeDistributor).balance;

        uint256 amount = 1 ether;
        vm.deal(address(feeDistributor), amount);

        vm.prank(recoverer);
        feeDistributor.recoverEther();

        assertEq(recoverer.balance, contractBalance + amount);
    }

    function test_recoverWstETH_fromFeeDistributor() public assertInvariants {
        assertEq(wstETH.balanceOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 amountWstETH = wstETH.wrap(lido.getPooledEthByShares(shares));
        wstETH.transfer(address(feeDistributor), amountWstETH);
        vm.stopPrank();

        vm.prank(recoverer);
        feeDistributor.recoverERC20(address(wstETH), amountWstETH);

        assertEq(wstETH.balanceOf(recoverer), amountWstETH);
    }

    function test_recoverETH_fromOracle() public assertInvariants {
        assertEq(recoverer.balance, 0);

        uint256 contractBalance = address(oracle).balance;

        uint256 amount = 1 ether;
        vm.deal(address(oracle), amount);

        vm.prank(recoverer);
        oracle.recoverEther();

        assertEq(recoverer.balance, contractBalance + amount);
    }

    function test_recoverWstETH_fromOracle() public assertInvariants {
        assertEq(wstETH.balanceOf(recoverer), 0);

        uint256 amount = 1 ether;
        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 shares = lido.submit{ value: amount }(address(0));
        lido.approve(address(wstETH), type(uint256).max);
        uint256 amountWstETH = wstETH.wrap(lido.getPooledEthByShares(shares));
        wstETH.transfer(address(oracle), amountWstETH);
        vm.stopPrank();

        vm.prank(recoverer);
        oracle.recoverERC20(address(wstETH), amountWstETH);

        assertEq(wstETH.balanceOf(recoverer), amountWstETH);
    }
}
