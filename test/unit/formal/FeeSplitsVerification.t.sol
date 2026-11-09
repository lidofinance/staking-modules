// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test, stdError } from "forge-std/Test.sol";
import { FeeSplitsHarness } from "../../../certora/harnesses/FeeSplitsHarness.sol";
import { IFeeSplits } from "../../../src/interfaces/IFeeSplits.sol";

/// @notice Executable checks of the production transitions used in the CVL suite.
contract FeeSplitsVerificationTest is Test {
    FeeSplitsHarness internal splits;
    address internal constant STETH = address(0x1000);

    function setUp() public {
        splits = new FeeSplitsHarness();
    }

    function testFuzz_fullTenRecipientSplitConservesBudget(uint128 amount) public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](10);
        for (uint256 i; i < config.length; ++i) {
            config[i] = IFeeSplits.FeeSplit(address(uint160(i + 1)), 1000);
        }
        splits.updateSplits(0, config, STETH);
        uint256 paid = splits.transferSum(0, amount);
        assertLe(paid, amount);
        assertLt(uint256(amount) - paid, 10);
    }

    function testFuzz_partialSplitRetainsOperatorRemainder(uint128 amount, uint16 bp) public {
        bp = uint16(bound(bp, 1, 9999));
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(1), bp);
        splits.updateSplits(0, config, STETH);
        assertEq(splits.transferSum(0, amount), (uint256(amount) * bp) / 10_000);
    }

    function testFuzz_validConfigurationsConserveAndRoundDown(
        uint128 amount,
        uint8 count,
        uint16[10] memory weights
    ) public {
        count = uint8(bound(count, 1, 10));
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](count);
        uint256 remaining = 10_000;
        for (uint256 i; i < count; ++i) {
            uint256 bp = bound(weights[i], 1, remaining - (count - i - 1));
            config[i] = IFeeSplits.FeeSplit(address(uint160(i + 1)), bp);
            remaining -= bp;
        }
        splits.updateSplits(0, config, STETH);
        IFeeSplits.SplitTransfer[] memory transfers = splits.getFeeSplitTransfers(0, amount);
        if (amount == 0) {
            assertEq(transfers.length, 0);
            return;
        }
        assertEq(transfers.length, count);
        uint256 paid;
        for (uint256 i; i < count; ++i) {
            assertEq(transfers[i].recipient, config[i].recipient);
            assertEq(transfers[i].shares, (uint256(amount) * config[i].share) / 10_000);
            paid += transfers[i].shares;
        }
        assertLe(paid, amount);
    }

    function test_duplicateRecipientsAndHarnessRecipientAreValid() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](2);
        config[0] = IFeeSplits.FeeSplit(address(splits), 2500);
        config[1] = IFeeSplits.FeeSplit(address(splits), 2500);
        splits.updateSplits(0, config, STETH);
        assertEq(splits.transferSum(0, 100), 50);
    }

    function test_pendingIncludesRetainedRemainder() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(1), 2500);
        splits.updateSplits(0, config, STETH);
        splits.increasePending(0, 100);
        assertEq(splits.transferSum(0, 100), 25);
        splits.decreasePending(0, 100);
        assertEq(splits.getPendingSharesToSplit(0), 0);
    }

    function test_emptyConfigurationClearsEntries() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(1), 10_000);
        splits.updateSplits(0, config, STETH);
        splits.updateSplits(0, new IFeeSplits.FeeSplit[](0), STETH);
        assertFalse(splits.hasSplits(0));
        assertEq(splits.transferSum(0, 100), 0);
    }

    function testFuzz_pendingTransitionsAreOperatorLocal(uint128 credit, uint128 debit) public {
        debit = uint128(bound(debit, 0, credit));
        splits.increasePending(1, 77);
        splits.increasePending(0, credit);
        splits.decreasePending(0, debit);
        assertEq(splits.getPendingSharesToSplit(0), uint256(credit) - debit);
        assertEq(splits.getPendingSharesToSplit(1), 77);
    }

    function test_configurationWithPendingSharesReverts() public {
        splits.increasePending(0, 1);
        vm.expectRevert(IFeeSplits.PendingSharesExist.selector);
        splits.updateSplits(0, new IFeeSplits.FeeSplit[](0), STETH);
    }

    function test_moreThanTenRecipientsReverts() public {
        vm.expectRevert(IFeeSplits.TooManySplits.selector);
        splits.updateSplits(0, new IFeeSplits.FeeSplit[](11), STETH);
    }

    function test_zeroRecipientReverts() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(0), 1);
        vm.expectRevert(IFeeSplits.ZeroSplitRecipient.selector);
        splits.updateSplits(0, config, STETH);
    }

    function test_stETHRecipientReverts() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(STETH, 1);
        vm.expectRevert(IFeeSplits.InvalidSplitRecipient.selector);
        splits.updateSplits(0, config, STETH);
    }

    function test_zeroShareReverts() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(1), 0);
        vm.expectRevert(IFeeSplits.ZeroSplitShare.selector);
        splits.updateSplits(0, config, STETH);
    }

    function test_excessiveBasisPointsRevert() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](2);
        config[0] = IFeeSplits.FeeSplit(address(1), 5001);
        config[1] = IFeeSplits.FeeSplit(address(2), 5000);
        vm.expectRevert(IFeeSplits.TooManySplitShares.selector);
        splits.updateSplits(0, config, STETH);
    }

    function test_excessiveDebitReverts() public {
        splits.increasePending(0, 10);
        vm.expectRevert(stdError.arithmeticError);
        splits.decreasePending(0, 11);
    }

    function test_largePayoutInputCanRevertOnCheckedMultiplication() public {
        IFeeSplits.FeeSplit[] memory config = new IFeeSplits.FeeSplit[](1);
        config[0] = IFeeSplits.FeeSplit(address(1), 10_000);
        splits.updateSplits(0, config, STETH);
        vm.expectRevert(stdError.arithmeticError);
        splits.getFeeSplitTransfers(0, type(uint256).max);
    }
}
