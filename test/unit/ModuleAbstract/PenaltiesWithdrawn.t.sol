// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";
import { KeyPointerLib } from "src/lib/KeyPointerLib.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleReportWithdrawnValidators is ModuleFixtures {
    function test_isValidatorWithdrawn_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorWithdrawn(noId, 0));
    }

    function test_isValidatorWithdrawn_RevertWhen_InvalidKeyIndex() public {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorWithdrawn(0, 0);

        uint256 emptyNoId = createNodeOperator(0);
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorWithdrawn(emptyNoId, 0);

        uint256 noId = createNodeOperator(1);
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorWithdrawn(noId, 1);
    }

    function test_reportRegularWithdrawnValidators_NoPenalties() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, keyIndex, pubkey);
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        bool withdrawn = module.isValidatorWithdrawn(noId, keyIndex);
        assertTrue(withdrawn);

        assertEq(module.getNonce(), nonce + 1);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_changeNonce() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            slashingPenalty: 0
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, keyIndex, pubkey);
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        // depositable decrease should
        assertEq(module.getNonce(), nonce + 1);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_lowExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            slashingPenalty: 0
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_exitBalanceBelowKeyBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 maxReportedBalance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether;
        uint256 exitBalance = maxReportedBalance - 1 ether;
        uint256 expectedPenalty = maxReportedBalance - exitBalance;

        module.reportValidatorBalance(noId, keyIndex, maxReportedBalance);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: exitBalance,
            slashingPenalty: 0
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, expectedPenalty));
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_removesAllocatedButUnconfirmedExtra() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        module.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(10 ether)
        });

        assertEq(module.getKeyAllocatedBalances(noId, 0, 1), UintArr(10 ether));
        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(0));
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_keepsRemainingTrackedStakeOfOtherKey() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        bytes memory key = module.getSigningKeys(noId, 0, 1);
        module.allocateDeposits({
            maxDepositAmount: 10 ether,
            pubkeys: BytesArr(key),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(10 ether)
        });

        assertEq(module.getTotalModuleStake(), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getNodeOperatorBalance(noId), 2 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_reportRegularWithdrawnValidators_exitPenaltyScaledByMaxReportedBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        uint256 maxReportedBalance = ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1 wei;
        uint256 exitBalance = maxReportedBalance - 1 ether;
        uint256 expectedPenalty = maxReportedBalance - exitBalance;

        module.reportValidatorBalance(noId, keyIndex, maxReportedBalance);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: exitBalance,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier + expectedPenalty)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidators_superLowExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(4);
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE + 1 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            slashingPenalty: 0
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.depositableValidatorsCount, 2);
    }

    function test_reportRegularWithdrawnValidators_strikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_hugeStrikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_strikesPenaltyWithMultiplier() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 penalty = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1 ether - 1 wei,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_strikesPenaltyAtMaxWithMultiplier() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 penalty = (1 << 245) - 1;
        uint256 multiplier = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE /
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1000 ether,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_SlashingPenaltyPresent() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 1 ether
        });

        vm.expectRevert(IBaseModule.SlashingPenaltyIsNotApplicable.selector, address(module));
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_ignoresLegacyFees() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // A shifted or reused deprecated slot would surface as a settled penalty or fee here.
        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(_toUint248(BOND_SIZE), true),
                strikesPenalty: MarkedUint248(0, false),
                legacyElWithdrawalRequestFee: MarkedUint248(_toUint248(BOND_SIZE), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector));
        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.chargeFee.selector));
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_unbondedKeys() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 1 ether,
            slashingPenalty: 0
        });

        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_ZeroExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 0,
            slashingPenalty: 0
        });

        vm.expectRevert(IBaseModule.ZeroExitBalance.selector);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_NoNodeOperator() public assertInvariants {
        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: 32 ether,
            slashingPenalty: 0
        });

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_InvalidKeyIndexOffset() public assertInvariants {
        uint256 noId = createNodeOperator();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 32 ether,
            slashingPenalty: 0
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_alreadyWithdrawn() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        module.reportRegularWithdrawnValidators(validatorInfos);

        uint256 nonceBefore = module.getNonce();
        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(
            module.getNonce(),
            nonceBefore,
            "Nonce should not change when trying to withdraw already withdrawn key"
        );
    }

    function test_reportRegularWithdrawnValidators_emptyBatch_NoNonceChange() public assertInvariants {
        createNodeOperator(1);
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](0);
        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getNonce(), nonceBefore, "Nonce should not change when batch is empty");
    }

    function test_reportRegularWithdrawnValidators_allAlreadyWithdrawn_NoNonceChange() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](2);
        for (uint256 i = 0; i < 2; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0
            });
        }

        module.reportRegularWithdrawnValidators(validatorInfos);
        uint256 nonceBefore = module.getNonce();
        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getNonce(), nonceBefore, "Nonce should not change when all keys are already withdrawn");
    }

    function test_reportRegularWithdrawnValidators_nonceIncrementsOnceForManyWithdrawals() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](3);
        for (uint256 i = 0; i < 3; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0
            });
        }
        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(module.getNonce(), nonceBefore + 1, "Module nonce should increment only once for batch withdrawals");
    }

    function test_reportRegularWithdrawnValidators_gas16Withdrawals() public {
        uint256 keysCount = 16;
        uint256 noId = createNodeOperator(keysCount);
        module.obtainDepositData(keysCount, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](keysCount);
        for (uint256 i = 0; i < keysCount; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0
            });
        }

        vm.startSnapshotGas("reportRegularWithdrawnValidators_16");
        module.reportRegularWithdrawnValidators(validatorInfos);
        vm.stopSnapshotGas();
    }

    function test_reportValidatorSlashing_HappyPath() public assertInvariants {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);
        uint256 timeToWithdrawable = 36 days;
        uint256 lockedUntil = block.timestamp + timeToWithdrawable + 14 days;
        uint256 slashingPenalty = 1 ether;

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorSlashingReported(noId, keyIndex, pubkey);
        vm.expectEmit(address(module));
        emit IBaseModule.BondClaimLockedUntilChanged(noId, lockedUntil);
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportValidatorSlashing(noId, keyIndex, timeToWithdrawable);

        assertTrue(module.isValidatorSlashed(noId, keyIndex));
        assertTrue(module.isValidatorWithdrawn(noId, keyIndex));
        assertEq(module.getBondClaimLockedUntil(noId), lockedUntil);
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
    }

    function test_reportValidatorSlashing_penaltyFromTheCurve() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        uint256 slashingPenalty = 3 ether;
        parametersRegistry.setSlashingPenalty(accounting.getBondCurveId(noId), slashingPenalty);

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportValidatorSlashing(noId, 0, 0);

        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getTotalModuleStake(), 0);
    }

    function test_reportValidatorSlashing_keepsTheFurthestLock() public assertInvariants {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");
        uint256 timeToWithdrawable = 36 days;
        uint256 lockedUntil = block.timestamp + timeToWithdrawable + module.BOND_CLAIM_LOCK_DELAY();

        module.reportValidatorSlashing(noId, 0, timeToWithdrawable);
        assertEq(module.getBondClaimLockedUntil(noId), lockedUntil);

        // An earlier slashing does not shorten the lock set by the later one.
        module.reportValidatorSlashing(noId, 1, timeToWithdrawable - 1 days);

        assertEq(module.getBondClaimLockedUntil(noId), lockedUntil);
    }

    function test_reportValidatorSlashing_penaltyScaledByAllocatedBalance() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        uint256 topUp = 10 ether;
        bytes memory pubkey = module.getSigningKeys(noId, 0, 1);
        module.allocateDeposits({
            maxDepositAmount: topUp,
            pubkeys: BytesArr(pubkey),
            keyIndices: UintArr(0),
            operatorIds: UintArr(noId),
            topUpLimits: UintArr(topUp)
        });
        assertEq(module.getKeyAllocatedBalances(noId, 0, 1), UintArr(topUp));
        assertEq(module.getKeyConfirmedBalances(noId, 0, 1), UintArr(0));

        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0.01 ether, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );
        uint256 slashingPenalty = 1.3125 ether;
        uint256 totalPenalty = slashingPenalty + 0.013125 ether;
        uint256 nonce = module.getNonce();

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, totalPenalty), 1);
        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, 0, pubkey);
        module.reportValidatorSlashing(noId, 0, 0);

        assertEq(module.getNodeOperatorBalance(noId), 0);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_isValidatorSlashed_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorSlashed(noId, 0));
    }

    function test_isValidatorSlashed_RevertWhen_InvalidKeyIndex() public {
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorSlashed(0, 0);

        uint256 emptyNoId = createNodeOperator(0);
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorSlashed(emptyNoId, 0);

        uint256 noId = createNodeOperator(1);
        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.isValidatorSlashed(noId, 1);
    }

    function test_reportValidatorSlashing_CalledTwice() public assertInvariants {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;

        module.reportValidatorSlashing(noId, keyIndex, 0);
        uint256 nonce = module.getNonce();
        uint256 lockedUntil = module.getBondClaimLockedUntil(noId);

        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector));
        vm.recordLogs();
        module.reportValidatorSlashing(noId, keyIndex, 365 days);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(module.getNonce(), nonce);
        assertEq(module.getBondClaimLockedUntil(noId), lockedUntil);
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getTotalModuleStake(), 16 * ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_reportValidatorSlashing_ignoresLaterWithdrawalReports() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, 0, 0);
        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[] memory infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector));
        vm.recordLogs();
        module.reportRegularWithdrawnValidators(infos);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(module.getNonce(), nonce);
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getTotalModuleStake(), 0);
    }

    function test_reportValidatorSlashing_settlesSlashingReportedBeforeUpgrade() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // A validator slashed before the module started settling slashings right on the report.
        uint256 pointer = KeyPointerLib.keyPointer(noId, 0);
        vm.store(address(module), keccak256(abi.encode(pointer, IS_VALIDATOR_SLASHED_SLOT)), bytes32(uint256(1)));
        assertFalse(module.isValidatorWithdrawn(noId, 0));

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, 1 ether));
        module.reportValidatorSlashing(noId, 0, 0);

        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getBondClaimLockedUntil(noId), 0, "a replayed report does not re-record the slashing");
    }

    function test_reportValidatorSlashing_RevertWhen_OperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorSlashing(0, 0, 0);
    }

    function test_reportValidatorSlashing_RevertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportValidatorSlashing(noId, 0, 0);
    }

    function test_keyConfirmedBalance_chargesOnWithdraw() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = 10 ether;

        setKeyConfirmedBalance(noId, 0, balanceShortage);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(noId);
        uint256 bondBefore = accounting.getBond(noId);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0
        });

        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(accounting.getBond(noId), bondBefore - balanceShortage);
    }

    function test_keyConfirmedBalance_PenalizeWhenSlashed() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 topUp = 10 ether;
        setKeyConfirmedBalance(noId, 0, topUp);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(noId);
        uint256 bondBefore = accounting.getBond(noId);
        uint256 slashingPenalty = WithdrawnValidatorLib.scalePenalty(
            parametersRegistry.slashingPenalty(),
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + topUp
        );

        module.reportValidatorSlashing(noId, 0, 0);

        assertEq(
            accounting.getBond(noId),
            bondBefore - slashingPenalty,
            "the confirmed balance scales the slashing penalty"
        );
    }
}
