// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ValidatorBalanceLimits } from "src/lib/ValidatorBalanceLimits.sol";
import { KeyPointerLib } from "src/lib/KeyPointerLib.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleReportValidatorSlashing is ModuleFixtures {
    function test_reportValidatorSlashing_HappyPath() public assertInvariants {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);
        uint256 timeToWithdrawable = 36 days;
        uint256 deadline = block.timestamp + timeToWithdrawable + 14 days;
        uint256 slashingPenalty = 1 ether;

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorSlashingReported(noId, keyIndex, pubkey);
        vm.expectEmit(address(module));
        emit IBaseModule.SlashingSettleDeadlineChanged(noId, deadline);
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, slashingPenalty));
        module.reportValidatorSlashing(noId, keyIndex, timeToWithdrawable);

        assertTrue(module.isValidatorSlashed(noId, keyIndex));
        assertTrue(module.isValidatorWithdrawn(noId, keyIndex));
        assertEq(module.getSlashingSettleDeadline(noId), deadline);
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
        uint256 deadline = block.timestamp + timeToWithdrawable + module.SLASHING_SETTLE_DELAY();

        module.reportValidatorSlashing(noId, 0, timeToWithdrawable);
        assertEq(module.getSlashingSettleDeadline(noId), deadline);

        // An earlier slashing does not shorten the lock set by the later one.
        module.reportValidatorSlashing(noId, 1, timeToWithdrawable - 1 days);

        assertEq(module.getSlashingSettleDeadline(noId), deadline);
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

        parametersRegistry.setSlashingPenalty(accounting.getBondCurveId(noId), 3 ether);
        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0.01 ether, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );
        // Both penalties use the whole-ETH multiplier of 42; the ready slashing penalty is not scaled again.
        uint256 slashingPenalty = 3.9375 ether;
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

    function test_reportValidatorSlashing_capsPenaltyMultiplier() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        _reportValidatorBalance(noId, 0, 3000 ether, 1);
        parametersRegistry.setSlashingPenalty(accounting.getBondCurveId(noId), 3 ether);
        exitPenalties.mock_setExitPenaltyInfo(
            ExitPenaltyInfo({
                legacyDelayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0.01 ether, true),
                legacyElWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        // Scaling is capped at x64 for both the configured slashing penalty and strikes.
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, 192.64 ether), 1);
        module.reportValidatorSlashing(noId, 0, 0);

        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportValidatorSlashing_roundsBalanceDownToWholeEth() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        _reportValidatorBalance(noId, 0, 42.9 ether, 1);

        // The configured 1 ETH base penalty scales by 42 / 32, not 42.9 / 32.
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, 1.3125 ether), 1);
        module.reportValidatorSlashing(noId, 0, 0);

        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
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

    function test_reportValidatorSlashing_settlesSlashingReportedBeforeUpgrade() public assertInvariants {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // A validator slashed before the module started settling slashings right on the report.
        uint256 pointer = KeyPointerLib.keyPointer(noId, 0);
        vm.store(address(module), keccak256(abi.encode(pointer, IS_VALIDATOR_SLASHED_SLOT)), bytes32(uint256(1)));
        assertFalse(module.isValidatorWithdrawn(noId, 0));

        uint256 timeToWithdrawable = 3 days;
        uint256 settleDelay = module.SLASHING_SETTLE_DELAY();
        uint256 deadline = block.timestamp + timeToWithdrawable + settleDelay;

        vm.expectEmit(address(module));
        emit IBaseModule.SlashingSettleDeadlineChanged(noId, deadline);
        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, 1 ether));
        vm.recordLogs();
        module.reportValidatorSlashing(noId, 0, timeToWithdrawable);

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertNotEq(logs[i].topics[0], IBaseModule.ValidatorSlashingReported.selector);
        }
        assertTrue(module.isValidatorWithdrawn(noId, 0));
        assertEq(module.getNodeOperator(noId).totalWithdrawnKeys, 1);
        assertEq(module.getSlashingSettleDeadline(noId), deadline);
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

    function test_reportValidatorSlashing_RevertWhen_AlreadyWithdrawn() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;

        module.reportValidatorSlashing(noId, keyIndex, 0);

        vm.expectRevert(IBaseModule.SlashingPenaltyIsNotApplicable.selector);
        module.reportValidatorSlashing(noId, keyIndex, 365 days);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_SlashingAlreadySettled() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.reportValidatorSlashing(noId, 0, 0);

        WithdrawnValidatorInfo memory info = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.expectRevert(IBaseModule.ValidatorAlreadyWithdrawn.selector);
        module.reportRegularWithdrawnValidator(info);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_LegacySlashingReported() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // A pre-upgrade slashing must be finalized by the automatic slashing flow, not a regular withdrawal.
        uint256 pointer = KeyPointerLib.keyPointer(noId, 0);
        vm.store(address(module), keccak256(abi.encode(pointer, IS_VALIDATOR_SLASHED_SLOT)), bytes32(uint256(1)));

        WithdrawnValidatorInfo memory info = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.expectRevert(IBaseModule.SlashingPenaltyIsNotApplicable.selector);
        module.reportRegularWithdrawnValidator(info);
    }
}

abstract contract ModuleReportWithdrawnValidator is ModuleReportValidatorSlashing {
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

    function test_reportRegularWithdrawnValidator_NoPenalties() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, keyIndex, pubkey);
        module.reportRegularWithdrawnValidator(validatorInfos);

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

    function test_reportRegularWithdrawnValidator_changeNonce() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(noId, keyIndex, pubkey);
        module.reportRegularWithdrawnValidator(validatorInfos);

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

    function test_reportRegularWithdrawnValidator_lowExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportRegularWithdrawnValidator(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidator_removesAllocatedExtra() public assertInvariants {
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
        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE + 10 ether);

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        module.reportRegularWithdrawnValidator(validatorInfos);

        assertEq(module.getTotalModuleStake(), 0);
        assertEq(module.getNodeOperatorBalance(noId), 0);
    }

    function test_reportRegularWithdrawnValidator_keepsRemainingTrackedStakeOfOtherKey() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        module.reportRegularWithdrawnValidator(validatorInfos);

        assertEq(module.getTotalModuleStake(), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
        assertEq(module.getNodeOperatorBalance(noId), ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE);
    }

    function test_reportRegularWithdrawnValidator_superLowExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(4);
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE + 1 ether;

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE - balanceShortage
        });

        vm.expectCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector, noId, balanceShortage));
        module.reportRegularWithdrawnValidator(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.depositableValidatorsCount, 2);
    }

    function test_reportRegularWithdrawnValidator_strikesPenalty() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        module.reportRegularWithdrawnValidator(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidator_hugeStrikesPenalty() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, strikesPenaltyAmount)
        );
        module.reportRegularWithdrawnValidator(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidator_strikesPenaltyWithMultiplier() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1 ether - 1 wei
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier)
        );
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_strikesPenaltyAtMaxWithMultiplier() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE * multiplier + 1000 ether
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(accounting.penalize.selector, noId, penalty * multiplier)
        );
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_ignoresLegacyFees() public assertInvariants {
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

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.penalize.selector));
        expectNoCall(address(accounting), abi.encodeWithSelector(accounting.chargeFee.selector));
        module.reportRegularWithdrawnValidator(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidator_unbondedKeys() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 1 ether
        });

        module.reportRegularWithdrawnValidator(validatorInfos);
        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_ZeroExitBalance() public assertInvariants {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: 0
        });

        vm.expectRevert(IBaseModule.ZeroExitBalance.selector);
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_NoNodeOperator() public assertInvariants {
        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: 32 ether
        });

        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_InvalidKeyIndexOffset() public assertInvariants {
        uint256 noId = createNodeOperator();

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 32 ether
        });

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_RevertWhen_AlreadyWithdrawn() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo memory validatorInfos = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        module.reportRegularWithdrawnValidator(validatorInfos);

        vm.expectRevert(IBaseModule.ValidatorAlreadyWithdrawn.selector);
        module.reportRegularWithdrawnValidator(validatorInfos);
    }

    function test_reportRegularWithdrawnValidator_nonceIncrementsForEachWithdrawal() public assertInvariants {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[] memory validatorInfos = new WithdrawnValidatorInfo[](3);
        for (uint256 i = 0; i < 3; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
            });
        }
        for (uint256 i; i < validatorInfos.length; ++i) {
            module.reportRegularWithdrawnValidator(validatorInfos[i]);
        }
        assertEq(module.getNonce(), nonceBefore + validatorInfos.length);
    }

    function test_reportRegularWithdrawnValidator_gasOneWithdrawal() public {
        uint256 noId = createNodeOperator(1);
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo memory info = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: ValidatorBalanceLimits.MIN_ACTIVATION_BALANCE
        });

        vm.startSnapshotGas("reportRegularWithdrawnValidator_1");
        module.reportRegularWithdrawnValidator(info);
        vm.stopSnapshotGas();
    }
}
