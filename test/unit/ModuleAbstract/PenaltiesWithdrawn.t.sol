// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { console } from "forge-std/console.sol";
import { Test, Vm } from "forge-std/Test.sol";

import { Batch } from "src/lib/DepositQueueLib.sol";
import { BaseModule } from "src/abstract/BaseModule.sol";
import { BondLock } from "src/abstract/BondLock.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";
import { IExitPenalties, ExitPenaltyInfo, MarkedUint248 } from "src/interfaces/IExitPenalties.sol";
import { IBaseModule, NodeOperator, NodeOperatorManagementProperties, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";
import { ICSModule } from "src/interfaces/ICSModule.sol";
import { IGeneralPenalty } from "src/lib/GeneralPenaltyLib.sol";
import { ILidoLocator } from "src/interfaces/ILidoLocator.sol";
import { INOAddresses } from "src/lib/NOAddresses.sol";
import { INodeOperatorOwner } from "src/interfaces/INodeOperatorOwner.sol";
import { IStakingModule } from "src/interfaces/IStakingModule.sol";
import { IWithdrawalQueue } from "src/interfaces/IWithdrawalQueue.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { SigningKeys } from "src/lib/SigningKeys.sol";
import { WithdrawnValidatorLib } from "src/lib/WithdrawnValidatorLib.sol";

import { AccountingMock } from "../../helpers/mocks/AccountingMock.sol";
import { ParametersRegistryMock } from "../../helpers/mocks/ParametersRegistryMock.sol";
import { ERC20Testable } from "../../helpers/ERCTestable.sol";
import { ExitPenaltiesMock } from "../../helpers/mocks/ExitPenaltiesMock.sol";
import { Fixtures } from "../../helpers/Fixtures.sol";
import { InvariantAsserts } from "../../helpers/InvariantAsserts.sol";
import { LidoLocatorMock } from "../../helpers/mocks/LidoLocatorMock.sol";
import { LidoMock } from "../../helpers/mocks/LidoMock.sol";
import { Stub } from "../../helpers/mocks/Stub.sol";
import { Utilities } from "../../helpers/Utilities.sol";
import { WstETHMock } from "../../helpers/mocks/WstETHMock.sol";
import { ModuleFixtures } from "./_Base.t.sol";

abstract contract ModuleReportWithdrawnValidators is ModuleFixtures {
    function test_isValidatorWithdrawn_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorWithdrawn(noId, 0));
    }

    function test_reportRegularWithdrawnValidators_NoPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(
            noId,
            keyIndex,
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            0,
            pubkey
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the were no penalties.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
        bool withdrawn = module.isValidatorWithdrawn(noId, keyIndex);
        assertTrue(withdrawn);

        assertEq(module.getNonce(), nonce + 1);
    }

    function test_reportRegularWithdrawnValidators_changeNonce()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        (bytes memory pubkey, ) = module.obtainDepositData(1, "");

        uint256 nonce = module.getNonce();

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorWithdrawn(
            noId,
            keyIndex,
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE - balanceShortage,
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
    }

    function test_reportRegularWithdrawnValidators_lowExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE - 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_superLowExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 balanceShortage = BOND_SIZE + 1 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                balanceShortage
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFee()
        public
        assertInvariants
    {
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

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFeeWithMultiplier()
        public
        assertInvariants
    {
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

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1 ether -
                1 wei,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                fee * multiplier
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_exitDelayFeeAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 fee = (1 << 245) - 1;
        uint256 multiplier = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE /
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(fee, true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                fee * multiplier
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_strikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_hugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the penalty is not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportRegularWithdrawnValidators_strikesPenaltyWithMultiplier()
        public
        assertInvariants
    {
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

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1 ether -
                1 wei,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_strikesPenaltyAtMaxWithMultiplier()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        // (1 << (256 - log2(2048))) - 1
        uint248 penalty = (1 << 245) - 1;
        uint256 multiplier = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE /
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(penalty, true),
                elWithdrawalRequestFee: MarkedUint248(0, false)
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier +
                1000 ether,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                penalty * multiplier
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyApplied()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyOverridesExitBalancePenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                11 ether,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenaltyNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        uint256 slashingPenalty = 7 ether;
        uint256 multiplier = 5;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                slashingPenalty
            )
        );
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_slashingPenalty_RevertWhenNotReported()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 slashingPenalty = 5 ether;

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: slashingPenalty,
            isSlashed: true
        });

        vm.expectRevert(
            IBaseModule.SlashingPenaltyIsNotApplicable.selector,
            address(module)
        );

        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_RevertWhen_SlashedInfoWithRegularMethod()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, keyIndex);

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 1 ether,
            isSlashed: true
        });

        vm.expectRevert(
            IBaseModule.InvalidWithdrawnValidatorInfo.selector,
            address(module)
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportSlashedWithdrawnValidators_RevertWhen_NotSlashedInfo()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectRevert(
            IBaseModule.InvalidWithdrawnValidatorInfo.selector,
            address(module)
        );
        module.reportSlashedWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_DelayFee()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = 0.7 ether;
        uint256 withdrawalRequestFeeAmount = 0.3 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE -
            strikesPenaltyAmount -
            0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_HugeStrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE + 1 ether;
        uint256 withdrawalRequestFeeAmount = 0.1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges are covered by the bond but the penalties are not.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportRegularWithdrawnValidators_chargeHugeWithdrawalFee_StrikesPenalty()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 strikesPenaltyAmount = BOND_SIZE - 1 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
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
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_DelayAndStrikesPenalties_AllHuge()
        public
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 exitDelayFeeAmount = BOND_SIZE + 17 ether;
        uint256 strikesPenaltyAmount = BOND_SIZE + 31 ether;
        uint256 withdrawalRequestFeeAmount = BOND_SIZE + 42 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(_toUint248(exitDelayFeeAmount), true),
                strikesPenalty: MarkedUint248(
                    _toUint248(strikesPenaltyAmount),
                    true
                ),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                exitDelayFeeAmount + withdrawalRequestFeeAmount
            )
        );
        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.penalize.selector,
                noId,
                strikesPenaltyAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be target limit if the charges or penalties are not covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 2);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFee_zeroPenaltyValue()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalties and charges are covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_chargeWithdrawalFeeNotScaled()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint248 withdrawalRequestFee = 0.1 ether;
        uint256 multiplier = 5;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, true),
                strikesPenalty: MarkedUint248(0, true),
                elWithdrawalRequestFee: MarkedUint248(
                    withdrawalRequestFee,
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE *
                multiplier,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFee
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);
    }

    function test_reportRegularWithdrawnValidators_dontChargeWithdrawalFee_noPenalties()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 withdrawalRequestFeeAmount = BOND_SIZE - 1 ether;

        exitPenalties.mock_setDelayedExitPenaltyInfo(
            ExitPenaltyInfo({
                delayFee: MarkedUint248(0, false),
                strikesPenalty: MarkedUint248(0, false),
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
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
                elWithdrawalRequestFee: MarkedUint248(
                    _toUint248(withdrawalRequestFeeAmount),
                    true
                )
            })
        );

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);

        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: keyIndex,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE -
                balanceShortage,
            slashingPenalty: 0,
            isSlashed: false
        });

        expectNoCall(
            address(accounting),
            abi.encodeWithSelector(
                accounting.chargeFee.selector,
                noId,
                withdrawalRequestFeeAmount
            )
        );
        module.reportRegularWithdrawnValidators(validatorInfos);

        NodeOperator memory no = module.getNodeOperator(noId);
        assertEq(no.totalWithdrawnKeys, 1);
        // There should be no target limit if the penalty is covered by the bond.
        assertEq(no.targetLimit, 0);
        assertEq(no.targetLimitMode, 0);
    }

    function test_reportRegularWithdrawnValidators_unbondedKeys()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(1, "");
        uint256 nonce = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
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

    function test_reportRegularWithdrawnValidators_RevertWhen_ZeroExitBalance()
        public
        assertInvariants
    {
        uint256 keyIndex = 0;
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
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

    function test_reportRegularWithdrawnValidators_RevertWhen_NoNodeOperator()
        public
        assertInvariants
    {
        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
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

    function test_reportRegularWithdrawnValidators_RevertWhen_InvalidKeyIndexOffset()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
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

    function test_reportRegularWithdrawnValidators_alreadyWithdrawn()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
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

    function test_reportRegularWithdrawnValidators_emptyBatch_NoNonceChange()
        public
        assertInvariants
    {
        createNodeOperator(1);
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](0);
        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(
            module.getNonce(),
            nonceBefore,
            "Nonce should not change when batch is empty"
        );
    }

    function test_reportRegularWithdrawnValidators_allAlreadyWithdrawn_NoNonceChange()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(2);
        module.obtainDepositData(2, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](2);
        for (uint256 i = 0; i < 2; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0,
                isSlashed: false
            });
        }

        module.reportRegularWithdrawnValidators(validatorInfos);
        uint256 nonceBefore = module.getNonce();
        module.reportRegularWithdrawnValidators(validatorInfos);

        assertEq(
            module.getNonce(),
            nonceBefore,
            "Nonce should not change when all keys are already withdrawn"
        );
    }

    function test_reportRegularWithdrawnValidators_nonceIncrementsOnceForManyWithdrawals()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator(3);
        module.obtainDepositData(3, "");
        uint256 nonceBefore = module.getNonce();

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](3);
        for (uint256 i = 0; i < 3; ++i) {
            validatorInfos[i] = WithdrawnValidatorInfo({
                nodeOperatorId: noId,
                keyIndex: i,
                exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
                slashingPenalty: 0,
                isSlashed: false
            });
        }
        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(
            module.getNonce(),
            nonceBefore + 1,
            "Module nonce should increment only once for batch withdrawals"
        );
    }

    function test_onValidatorSlashed_HappyPath() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;
        bytes memory pubkey = module.getSigningKeys(noId, keyIndex, 1);

        vm.expectEmit(address(module));
        emit IBaseModule.ValidatorSlashingReported(noId, keyIndex, pubkey);

        module.onValidatorSlashed(noId, keyIndex);
        assertTrue(module.isValidatorSlashed(noId, keyIndex));
    }

    function test_isValidatorSlashed_DefaultFalse() public assertInvariants {
        uint256 noId = createNodeOperator(1);

        assertFalse(module.isValidatorSlashed(noId, 0));
    }

    function test_onValidatorSlashed_RevertWhen_CalledTwice() public {
        uint256 noId = createNodeOperator(17);
        module.obtainDepositData(17, "");
        uint256 keyIndex = 11;

        module.onValidatorSlashed(noId, keyIndex);
        vm.expectRevert(
            IBaseModule.ValidatorSlashingAlreadyReported.selector,
            address(module)
        );
        module.onValidatorSlashed(noId, keyIndex);
    }

    function test_onValidatorSlashed_RevertWhen_OperatorDoesNotExist() public {
        vm.expectRevert(IBaseModule.NodeOperatorDoesNotExist.selector);
        module.onValidatorSlashed(0, 0);
    }

    function test_onValidatorSlashed_RevertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator(1);

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.onValidatorSlashed(noId, 0);
    }
}

abstract contract ModuleKeyAddedBalance is ModuleFixtures {
    function test_increaseKeyAddedBalance_emitsAndChargesOnWithdraw()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAddedBalanceChanged(noId, 0, 10 ether);
        module.increaseKeyAddedBalance(noId, 0, 10 ether);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(noId);
        uint256 bondBefore = accounting.getBond(noId);

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });

        module.reportRegularWithdrawnValidators(validatorInfos);
        assertEq(accounting.getBond(noId), bondBefore - 10 ether);
    }

    function test_increaseKeyAddedBalance_revertWhen_NoRole() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        bytes32 role = module.VERIFIER_ROLE();
        vm.prank(stranger);
        expectRoleRevert(stranger, role);
        module.increaseKeyAddedBalance(noId, 0, 1 ether);
    }

    function test_increaseKeyAddedBalance_revertWhen_InvalidKeyIndex() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        vm.expectRevert(IBaseModule.SigningKeysInvalidOffset.selector);
        module.increaseKeyAddedBalance(noId, 1, 1 ether);
    }

    function test_increaseKeyAddedBalance_revertWhen_Withdrawn() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE,
            slashingPenalty: 0,
            isSlashed: false
        });
        module.reportRegularWithdrawnValidators(validatorInfos);

        vm.expectRevert(IBaseModule.InvalidWithdrawnValidatorInfo.selector);
        module.increaseKeyAddedBalance(noId, 0, 1 ether);
    }

    function test_increaseKeyAddedBalance_doesNotChargeWhenSlashed()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();

        module.obtainDepositData(1, "");
        module.onValidatorSlashed(noId, 0);

        module.increaseKeyAddedBalance(noId, 0, 10 ether);

        vm.deal(address(this), 100 ether);
        accounting.depositETH{ value: 100 ether }(noId);
        uint256 bondBefore = accounting.getBond(noId);

        WithdrawnValidatorInfo[]
            memory validatorInfos = new WithdrawnValidatorInfo[](1);
        validatorInfos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: noId,
            keyIndex: 0,
            exitBalance: 1 ether,
            slashingPenalty: 0,
            isSlashed: true
        });

        module.reportSlashedWithdrawnValidators(validatorInfos);
        assertEq(accounting.getBond(noId), bondBefore);
    }

    function test_increaseKeyAddedBalance_noEmitWhenAtCap()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.increaseKeyAddedBalance(
            noId,
            0,
            WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE -
                WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE
        );

        vm.recordLogs();
        module.increaseKeyAddedBalance(noId, 0, 1 ether);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 signature = keccak256(
            "KeyAddedBalanceChanged(uint256,uint256,uint256)"
        );
        for (uint256 i; i < entries.length; ++i) {
            assertNotEq(entries[i].topics[0], signature);
        }
    }

    function test_increaseKeyAddedBalance_capsAndEmits()
        public
        assertInvariants
    {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        uint256 cap = WithdrawnValidatorLib.MAX_EFFECTIVE_BALANCE -
            WithdrawnValidatorLib.MIN_ACTIVATION_BALANCE;

        vm.expectEmit(address(module));
        emit IBaseModule.KeyAddedBalanceChanged(noId, 0, cap);

        module.increaseKeyAddedBalance(noId, 0, cap + 1 ether);
    }

    function test_getKeyAddedBalance_defaultZero() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        assertEq(module.getKeyAddedBalance(noId, 0), 0);
    }

    function test_getKeyAddedBalance_afterIncrease() public {
        uint256 noId = createNodeOperator();
        module.obtainDepositData(1, "");

        module.increaseKeyAddedBalance(noId, 0, 3 ether);
        assertEq(module.getKeyAddedBalance(noId, 0), 3 ether);
    }
}
