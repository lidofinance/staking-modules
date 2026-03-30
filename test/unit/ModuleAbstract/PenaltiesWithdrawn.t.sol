// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleReportWithdrawnValidators is ModuleFixtures {
    function test_isValidatorWithdrawn_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorWithdrawn(noId, 0));
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
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, keyIndex, ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE, 0, pubkey);
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
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(
            noId,
            keyIndex,
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            0,
            pubkey
        );
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_reportRegularWithdrawnValidators_exitPenaltyScaledByMaxReportedBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 fee = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(0, false)
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
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, fee * multiplier)
        );
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, expectedPenalty));
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
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.depositableValidatorsCount, 2);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFee() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, exitDelayFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFeeWithMultiplier() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 fee = 1 ether;
        uint256 multiplier = 3;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1 ether - 1 wei,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, fee * multiplier)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFeeAtMaxWithMultiplier() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 fee = (1 << 245) - 1;
        uint256 multiplier = ValidatorBalanceLimits.MAX_EFFECTIVE_BALANCE /
            ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, fee * multiplier)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_strikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
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

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
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

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1 ether - 1 wei,
            slashingPenalty: 0,
            isSlashed: false
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

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_revertWhen_SlashingPenaltyPresent() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 154,
            isSlashed: false
        });

        vm.expectRevert(IBaseModule.InvalidWithdrawnValidatorInfo.selector, address(module));
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyApplied() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyOverridesExitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - 11 ether,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyNotScaled() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, keyIndex);

        uint256 slashingPenalty = 7 ether;
        uint256 multiplier = 5;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyIsZero_fallbackPath() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, keyIndex);

        uint256 balanceShortage = 1 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            slashingPenalty: 0,
            isSlashed: true
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenalty_RevertWhenNotReported() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectRevert(IBaseModule.SlashingPenaltyIsNotApplicable.selector, address(module));

        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_SlashedInfoWithRegularMethod() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, keyIndex);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 1 ether,
            isSlashed: true
        });

        vm.expectRevert(IBaseModule.InvalidWithdrawnValidatorInfo.selector, address(module));
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_RevertWhen_NotSlashedInfo() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectRevert(IBaseModule.InvalidWithdrawnValidatorInfo.selector, address(module));
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_DelayFee() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = 0.7 ether;
        uint256 withdrawalRequestFeeAmount = 0.3 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, exitDelayFeeAmount + withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_StrikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE - strikesPenaltyAmount - 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_HugeStrikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeHugeWithdrawalFee_StrikesPenalty() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the charges are not covered by the bond.
        assertNotEq(no.targetLimitMode, 2);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_DelayAndStrikesPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = 0.17 ether;
        uint256 strikesPenaltyAmount = 0.31 ether;
        uint256 withdrawalRequestFeeAmount = 0.42 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, exitDelayFeeAmount + withdrawalRequestFeeAmount)
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_DelayAndStrikesPenalties_AllHuge() public {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE + 17 ether;
        uint256 strikesPenaltyAmount = BOND_SIZE + 31 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 42 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(_toUint248(strikesPenaltyAmount), true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, exitDelayFeeAmount + withdrawalRequestFeeAmount)
        );
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

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_zeroPenaltyValue() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFeeNotScaled() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 withdrawalRequestFee = 0.1 ether;
        uint256 multiplier = 5;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                elWithdrawalRequestFee: MarkedUint248(withdrawalRequestFee, true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFee)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_dontChargeWithdrawalFee_noPenalties() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if there were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_dontChargeWithdrawalFee_exitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;
        uint256 balanceShortage = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(_toUint248(withdrawalRequestFeeAmount), true)
            })
        );

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(accounting.chargeFee.selector, noId, withdrawalRequestFeeAmount)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
            slashingPenalty: 0,
            isSlashed: false
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
                slashingPenalty: 0,
                isSlashed: false
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
                slashingPenalty: 0,
                isSlashed: false
            });
        }
        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(module.getNonce(), nonceBefore + 1, "Module nonce should increment only once for batch withdrawals");
    }

    function test_reportValidatorSlashing_HappyPath() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorSlashingReported(noId, keyIndex, pubkey);

        module.reportValidatorSlashing(noId, keyIndex);
        assertTrue(module.isValidatorSlashed(noId, keyIndex));
    }

    function test_isValidatorSlashed_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorSlashed(noId, 0));
    }

    function test_reportValidatorSlashing_RevertWhen_CalledTwice() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;

        module.reportValidatorSlashing(noId, keyIndex);
        vm.expectRevert(IBaseModule.ValidatorSlashingAlreadyReported.selector, address(module));
        module.reportValidatorSlashing(noId, keyIndex);
    }

    function test_reportValidatorSlashing_RevertWhen_OperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportValidatorSlashing(0, 0);
    }

    function test_reportValidatorSlashing_RevertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportValidatorSlashing(noId, 0);
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
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(accounting.getBond(noId), bondBefore - balanceShortage);
    }

    function test_keyConfirmedBalance_PenalizeWhenSlashed() public assertInvariants {
        uint256 noId = createNodeOperator();

        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, 0);

        uint256 topUp = 10 ether;
        uint256 balanceShortage = 1 ether;

        setKeyConfirmedBalance(noId, 0, topUp);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(noId);
        uint256 bondBefore = accounting.getBond(noId);

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + topUp - balanceShortage,
            slashingPenalty: 0,
            isSlashed: true
        });

        module.reportSlashedWithdrawnValidators(validatorInfos);
        assertEq(accounting.getBond(noId), bondBefore - balanceShortage);
    }
}
