// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { BondCoreHarness } from "../../../certora/harnesses/BondCoreHarness.sol";
import { BondTokenModel, BondBurnerModel, BondWstETHModel, BondWithdrawalQueueModel, BondLocatorModel } from "../../../certora/models/BondEnvironmentModel.sol";

/// @dev These executable tests check the proof fixture against multi-step
///      share accounting and rounding scenarios. They do not replace Prover
///      proofs and do not validate the production external dependencies.
contract BondCoreVerificationTest is Test {
    BondCoreHarness internal core;
    BondTokenModel internal token;
    BondWstETHModel internal wrapped;
    BondWithdrawalQueueModel internal queue;
    address internal constant RECIPIENT = address(0xBEEF);

    function setUp() public {
        token = new BondTokenModel();
        BondBurnerModel burner = new BondBurnerModel(token);
        wrapped = new BondWstETHModel(token);
        queue = new BondWithdrawalQueueModel(token, address(wrapped));
        BondLocatorModel locator = new BondLocatorModel(address(token), address(burner), address(queue));
        core = new BondCoreHarness(address(locator));
        vm.deal(address(this), 1_000 ether);
    }

    function testFuzz_mixedFlowsPreserveShareAccounting(uint256 seed) public {
        // Exercise debt coverage, all three deposits, all three exits, fee
        // charges, and burns in different orders for two independent operators.
        for (uint256 i; i < 32; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 id = (seed >> 8) % 2;
            uint256 amount = ((seed >> 16) % 1 ether) + 3;
            uint256 op = seed % 8;
            if (op == 0) {
                core.depositETH{ value: amount }(address(this), id);
            } else if (op == 1) {
                token.mintShares(address(this), token.getSharesByPooledEth(amount));
                core.depositStETH(address(this), id, amount);
            } else if (op == 2) {
                wrapped.mint(address(this), amount);
                token.mintShares(address(wrapped), amount);
                core.depositWstETH(address(this), id, amount);
            } else if (op == 3) {
                core.charge(id, amount, RECIPIENT);
            } else if (op == 4) {
                core.burn(id, amount);
            } else {
                uint256 claimable = core.getBondShares(id) / 2;
                if (claimable == 0) continue;
                if (op == 5) {
                    core.claimStETH(id, type(uint128).max, claimable, RECIPIENT);
                } else if (op == 6) {
                    core.claimWstETH(id, type(uint128).max, claimable, RECIPIENT);
                } else if (claimable >= 2) {
                    core.claimUnstETH(id, type(uint128).max, claimable, RECIPIENT);
                }
            }
            _assertShareAccounting();
        }
    }

    function test_depositCoversPenaltyDebtBeforeRetainingNewBond() public {
        token.mintShares(address(core), 1);
        core.credit(0, 1);

        uint256 shortage = core.burn(0, 10);
        assertEq(shortage, 8);
        assertEq(core.getBondDebt(0), 8);
        assertEq(core.getBondShares(0), 0);

        core.depositETH{ value: 12 }(address(this), 0);

        assertEq(core.getBondDebt(0), 0);
        assertEq(core.getBondShares(0), 3);
        _assertShareAccounting();
    }

    function test_debtFreeCreditUpdatesBothLedgers() public {
        token.mintShares(address(core), 10);

        core.credit(0, 10);

        assertEq(core.getBondShares(0), 10);
        assertEq(core.totalBondShares(), 10);
        _assertShareAccounting();
    }

    function testFuzz_wrappedClaimPreservesCallerProtectedShares(uint128 bondInput, uint128 capInput) public {
        uint256 bond = bound(uint256(bondInput), 2, 1e30);
        uint256 cap = bound(uint256(capInput), 1, bond);
        token.mintShares(address(core), bond);
        core.credit(0, bond);
        uint256 protectedShares = bond - cap;

        uint256 paid = core.claimWstETH(0, type(uint128).max, cap, RECIPIENT);

        assertLe(paid, cap);
        assertGe(core.getBondShares(0), protectedShares);
        assertEq(core.getBondShares(0), bond - paid);
        assertEq(wrapped.balanceOf(RECIPIENT), paid);
        _assertShareAccounting();
    }

    function test_dustPenaltyDoesNotCreateUncollectableDebt() public {
        // 1 pooled-ETH unit converts to zero shares in the 3:2 model.
        assertEq(core.sharesByEth(1), 0);
        assertEq(core.burn(0, 1), 0);
        assertEq(core.getBondDebt(0), 0);
        _assertShareAccounting();
    }

    function _assertShareAccounting() private view {
        assertEq(core.totalBondShares(), core.getBondShares(0) + core.getBondShares(1));
        assertEq(token.sharesOf(address(core)), core.totalBondShares());
    }
}
