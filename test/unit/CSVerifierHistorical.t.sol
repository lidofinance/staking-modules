// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { ICSVerifier } from "src/interfaces/ICSVerifier.sol";
import { ICSModule, ValidatorWithdrawalInfo } from "src/interfaces/ICSModule.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { GIndex } from "src/lib/GIndex.sol";

import { CSVerifier } from "src/CSVerifier.sol";
import { ICSVerifier } from "src/interfaces/ICSVerifier.sol";
import { pack } from "src/lib/GIndex.sol";
import { Slot } from "src/lib/Types.sol";

import { GIndices } from "script/constants/GIndices.sol";

import { Utilities } from "test/helpers/Utilities.sol";
import { Stub } from "test/helpers/mocks/Stub.sol";

function dec(Slot self) pure returns (Slot slot) {
    assembly ("memory-safe") {
        slot := sub(self, 1)
    }
}

function inc(Slot self) pure returns (Slot slot) {
    assembly ("memory-safe") {
        slot := add(self, 1)
    }
}

using { dec, inc } for Slot;

GIndex constant NULL_GINDEX = GIndex.wrap(0);

GIndex constant FIRST_WITHDRAWAL_DENEB = GIndex.wrap(
    0x0000000000000000000000000000000000000000000000000000000000e1c004
);
GIndex constant FIRST_VALIDATOR_DENEB = GIndex.wrap(
    0x0000000000000000000000000000000000000000000000000056000000000028
);
GIndex constant FIRST_HISTORICAL_SUMMARY_DENEB = GIndex.wrap(
    0x0000000000000000000000000000000000000000000000000000007600000018
);
GIndex constant FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB = GIndex.wrap(
    0x000000000000000000000000000000000000000000000000000000000040000d
);

contract CSVerifierHistoricalBase is Test, Utilities {
    struct Fixture {
        bytes32 blockRoot;
        ICSVerifier.ProcessHistoricalWithdrawalInput data;
    }

    Fixture public fixture;

    Stub public module;
    CSVerifier public verifier;

    function _setMocks() internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(fixture.blockRoot)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(ICSModule.getSigningKeys.selector, 0, 0),
            abi.encode(fixture.data.validator.object.pubkey)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(ICSModule.submitWithdrawals.selector),
            ""
        );
    }

    function _loadFixture(string memory fork) internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/CSVerifier/historical_withdrawal.mjs";
        cmd[3] = fork;
        bytes memory res = vm.ffi(cmd);
        fixture = abi.decode(res, (Fixture));
    }

    function ffi_interface(Fixture memory) external {}
}

contract CSVerifierHistoricalTest is CSVerifierHistoricalBase {
    function setUp() public {
        _loadFixture("electra");

        module = new Stub();
        verifier = new CSVerifier({
            withdrawalAddress: fixture.data.withdrawal.object.withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192,
            gindices: ICSVerifier.GIndices({
                gIFirstWithdrawalPrev: NULL_GINDEX,
                gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
                gIFirstValidatorPrev: NULL_GINDEX,
                gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
                gIFirstHistoricalSummaryPrev: NULL_GINDEX,
                gIFirstHistoricalSummaryCurr: GIndices
                    .FIRST_HISTORICAL_SUMMARY_ELECTRA,
                gIFirstBlockRootInSummaryPrev: NULL_GINDEX,
                gIFirstBlockRootInSummaryCurr: GIndices
                    .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
                gIFirstBalanceNodePrev: NULL_GINDEX,
                gIFirstBalanceNodeCurr: NULL_GINDEX,
                gIFirstPendingConsolidationPrev: NULL_GINDEX,
                gIFirstPendingConsolidationCurr: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot,
            pivotSlot: fixture.data.withdrawalBlock.header.slot,
            capellaSlot: Slot.wrap(0),
            admin: nextAddress("ADMIN")
        });

        _setMocks();
    }

    function test_processWithdrawalProof_HappyPath() public {
        ValidatorWithdrawalInfo[]
            memory withdrawals = new ValidatorWithdrawalInfo[](1);
        withdrawals[0] = ValidatorWithdrawalInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.submitWithdrawals.selector,
                withdrawals
            )
        );

        verifier.processHistoricalWithdrawalProof(fixture.data);
    }

    function test_processHistoricalWithdrawalProof_RevertWhen_ValidatorSlashed()
        public
    {
        fixture.data.validator.object.slashed = true;

        vm.expectRevert(ICSVerifier.ValidatorIsSlashed.selector);
        verifier.processHistoricalWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_UnsupportedSlot() public {
        fixture.data.recentBlock.header.slot = verifier
            .FIRST_SUPPORTED_SLOT()
            .dec();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICSVerifier.UnsupportedSlot.selector,
                fixture.data.recentBlock.header.slot
            )
        );

        verifier.processHistoricalWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_UnsupportedSlot_OldBlock()
        public
    {
        fixture.data.withdrawalBlock.header.slot = verifier
            .FIRST_SUPPORTED_SLOT()
            .dec();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICSVerifier.UnsupportedSlot.selector,
                fixture.data.withdrawalBlock.header.slot
            )
        );

        verifier.processHistoricalWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidBlockHeader()
        public
    {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(ICSVerifier.InvalidBlockHeader.selector);
        verifier.processHistoricalWithdrawalProof(fixture.data);
    }
}

contract CSVerifierCrossForkHistoricalTest is CSVerifierHistoricalBase {
    function setUp() public virtual {
        _loadFixture("deneb");

        module = new Stub();
        verifier = new CSVerifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192,
            gindices: ICSVerifier.GIndices({
                gIFirstWithdrawalPrev: FIRST_WITHDRAWAL_DENEB,
                gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
                gIFirstValidatorPrev: FIRST_VALIDATOR_DENEB,
                gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
                gIFirstHistoricalSummaryPrev: FIRST_HISTORICAL_SUMMARY_DENEB,
                gIFirstHistoricalSummaryCurr: GIndices
                    .FIRST_HISTORICAL_SUMMARY_ELECTRA,
                gIFirstBlockRootInSummaryPrev: FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB,
                gIFirstBlockRootInSummaryCurr: GIndices
                    .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
                gIFirstBalanceNodePrev: NULL_GINDEX,
                gIFirstBalanceNodeCurr: NULL_GINDEX,
                gIFirstPendingConsolidationPrev: NULL_GINDEX,
                gIFirstPendingConsolidationCurr: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot,
            pivotSlot: fixture.data.recentBlock.header.slot.dec(),
            capellaSlot: Slot.wrap(0),
            admin: nextAddress("ADMIN")
        });
        _setMocks();
    }

    function test_processWithdrawalProof_HappyPath() public {
        ValidatorWithdrawalInfo[]
            memory withdrawals = new ValidatorWithdrawalInfo[](1);
        withdrawals[0] = ValidatorWithdrawalInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.submitWithdrawals.selector,
                withdrawals
            )
        );

        verifier.processHistoricalWithdrawalProof(fixture.data);
    }
}

contract CSVerifierCrossForkHistoricalAtPivotSlotTest is
    CSVerifierHistoricalBase
{
    function setUp() public {
        _loadFixture("deneb");

        module = new Stub();
        verifier = new CSVerifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192,
            gindices: ICSVerifier.GIndices({
                gIFirstWithdrawalPrev: FIRST_WITHDRAWAL_DENEB,
                gIFirstWithdrawalCurr: GIndices.FIRST_WITHDRAWAL_ELECTRA,
                gIFirstValidatorPrev: FIRST_VALIDATOR_DENEB,
                gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
                gIFirstHistoricalSummaryPrev: FIRST_HISTORICAL_SUMMARY_DENEB,
                gIFirstHistoricalSummaryCurr: GIndices
                    .FIRST_HISTORICAL_SUMMARY_ELECTRA,
                gIFirstBlockRootInSummaryPrev: FIRST_BLOCK_ROOT_IN_SUMMARY_DENEB,
                gIFirstBlockRootInSummaryCurr: GIndices
                    .FIRST_BLOCK_ROOT_IN_SUMMARY_ELECTRA,
                gIFirstBalanceNodePrev: NULL_GINDEX,
                gIFirstBalanceNodeCurr: NULL_GINDEX,
                gIFirstPendingConsolidationPrev: NULL_GINDEX,
                gIFirstPendingConsolidationCurr: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot,
            pivotSlot: fixture.data.recentBlock.header.slot,
            capellaSlot: Slot.wrap(0),
            admin: nextAddress("ADMIN")
        });
        _setMocks();
    }

    function test_processWithdrawalProof_HappyPath() public {
        ValidatorWithdrawalInfo[]
            memory withdrawals = new ValidatorWithdrawalInfo[](1);
        withdrawals[0] = ValidatorWithdrawalInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.submitWithdrawals.selector,
                withdrawals
            )
        );

        verifier.processHistoricalWithdrawalProof(fixture.data);
    }
}
