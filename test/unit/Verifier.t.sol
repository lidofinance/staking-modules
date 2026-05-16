// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { Verifier } from "src/Verifier.sol";
import { toGIndex } from "src/lib/GIndex.sol";
import { Slot } from "src/lib/Types.sol";
import { GIndex } from "src/lib/GIndex.sol";
import { SSZ } from "src/lib/SSZ.sol";

import { IVerifier } from "src/interfaces/IVerifier.sol";
import { IBaseModule, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";

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

function add(Slot self, uint64 v) pure returns (Slot slot) {
    assembly ("memory-safe") {
        slot := add(self, v)
    }
}

using { dec, inc, add } for Slot;

GIndex constant NULL_GINDEX = GIndex.wrap(0);

contract VerifierTestBase is Test, Utilities {
    using stdJson for string;

    Verifier public verifier;
    Stub public module;
    Slot public firstSupportedSlot;
    address public admin;
    address public stranger;

    bytes32 public pauseRole;
    bytes32 public resumeRole;

    string internal fixturesPath = "./test/fixtures/Verifier/";

    function _readFixture(string memory filename) internal noGasMetering returns (bytes memory data) {
        string memory path = string.concat(fixturesPath, filename);
        string memory json = vm.readFile(path);
        data = json.parseRaw("$");
    }
}

contract VerifierTestConstructor is VerifierTestBase {
    function setUp() public {
        module = new Stub();
        firstSupportedSlot = Slot.wrap(100_500);
        admin = nextAddress("ADMIN");
    }

    function test_constructor_HappyPath() public {
        address withdrawalAddress = nextAddress("WITHDRAWAL_ADDRESS");

        verifier = new Verifier({
            withdrawalAddress: withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c1),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000001),
                gIHistoricalSummariesPreGloas: toGIndex(0xfff0),
                gIHistoricalSummaries: toGIndex(0xffff),
                gIBalancesPreGloas: toGIndex(0x160000000000),
                gIBalances: toGIndex(0x160000000001)
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: Slot.wrap(100_501),
            capellaSlot: Slot.wrap(42),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        assertEq(address(verifier.WITHDRAWAL_ADDRESS()), withdrawalAddress);
        assertEq(address(verifier.MODULE()), address(module));
        assertEq(verifier.SLOTS_PER_EPOCH(), 32);
        assertEq(verifier.SLOTS_PER_HISTORICAL_ROOT(), 8192);
        assertEq(GIndex.unwrap(verifier.GI_WITHDRAWALS_PRE_GLOAS()), GIndex.unwrap(toGIndex(0xe1c0)));
        assertEq(GIndex.unwrap(verifier.GI_WITHDRAWALS()), GIndex.unwrap(toGIndex(0xe1c1)));
        assertEq(GIndex.unwrap(verifier.GI_VALIDATORS_PRE_GLOAS()), GIndex.unwrap(toGIndex(0x560000000000)));
        assertEq(GIndex.unwrap(verifier.GI_VALIDATORS()), GIndex.unwrap(toGIndex(0x560000000001)));
        assertEq(GIndex.unwrap(verifier.GI_HISTORICAL_SUMMARIES_PRE_GLOAS()), GIndex.unwrap(toGIndex(0xfff0)));
        assertEq(GIndex.unwrap(verifier.GI_HISTORICAL_SUMMARIES()), GIndex.unwrap(toGIndex(0xffff)));
        assertEq(GIndex.unwrap(verifier.GI_BLOCK_ROOT_IN_SUMMARY()), GIndex.unwrap(toGIndex(2)));
        assertEq(GIndex.unwrap(verifier.GI_BALANCES_PRE_GLOAS()), GIndex.unwrap(toGIndex(0x160000000000)));
        assertEq(GIndex.unwrap(verifier.GI_BALANCES()), GIndex.unwrap(toGIndex(0x160000000001)));
        assertEq(Slot.unwrap(verifier.FIRST_SUPPORTED_SLOT()), Slot.unwrap(firstSupportedSlot));
        assertEq(Slot.unwrap(verifier.PIVOT_SLOT()), Slot.unwrap(Slot.wrap(100_501)));
        assertEq(Slot.unwrap(verifier.CAPELLA_SLOT()), Slot.unwrap(Slot.wrap(42)));
        assertEq(verifier.MIN_WITHDRAWAL_RATIO(), 9000);
    }

    function test_constructor_RevertWhen_InvalidChainConfig_SlotsPerEpoch() public {
        vm.expectRevert(IVerifier.InvalidChainConfig.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 0,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot, // Any value less than the slots from the fixtures.
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_InvalidPivotSlot() public {
        vm.expectRevert(IVerifier.InvalidPivotSlot.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: firstSupportedSlot.dec(),
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_InvalidCapellaSlot() public {
        vm.expectRevert(IVerifier.InvalidCapellaSlot.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot.inc(),
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IVerifier.ZeroModuleAddress.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(0),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot, // Any value less than the slots from the fixtures.
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_ZeroWithdrawalAddress() public {
        vm.expectRevert(IVerifier.ZeroWithdrawalAddress.selector);
        verifier = new Verifier({
            withdrawalAddress: address(0),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot, // Any value less than the slots from the fixtures.
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_ZeroAdminAddress() public {
        vm.expectRevert(IVerifier.ZeroAdminAddress.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot, // Any value less than the slots from the fixtures.
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: address(0)
        });
    }

    function test_constructor_RevertWhen_InvalidMinWithdrawalRatio_Zero() public {
        vm.expectRevert(IVerifier.InvalidMinWithdrawalRatio.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 0,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_InvalidMinWithdrawalRatio_AboveMax() public {
        vm.expectRevert(IVerifier.InvalidMinWithdrawalRatio.selector);
        verifier = new Verifier({
            withdrawalAddress: nextAddress(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0xe1c0),
                gIWithdrawals: toGIndex(0xe1c0),
                gIValidatorsPreGloas: toGIndex(0x560000000000),
                gIValidators: toGIndex(0x560000000000),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0x3b),
                gIBalancesPreGloas: toGIndex(0x260000000000),
                gIBalances: toGIndex(0x260000000000)
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 10_001,
            admin: admin
        });
    }
}

contract VerifierWithdrawalTest is VerifierTestBase {
    using Strings for uint8;
    using Strings for uint256;

    struct Fixture {
        bytes32 blockRoot;
        IVerifier.ProcessWithdrawalInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture();

        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new Verifier({
            withdrawalAddress: fixture.data.withdrawal.object.withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: GIndices.WITHDRAWALS_ELECTRA,
                gIWithdrawals: GIndices.WITHDRAWALS_ELECTRA,
                gIValidatorsPreGloas: GIndices.VALIDATORS_ELECTRA,
                gIValidators: GIndices.VALIDATORS_ELECTRA,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            // Route through the pre-Gloas (static-list) branch; the post-Gloas
            // progressive-list branch is exercised by tests that override this
            // pivot, currently skipped until fixtures are ready.
            pivotSlot: fixture.data.withdrawalBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        pauseRole = verifier.PAUSE_ROLE();
        resumeRole = verifier.RESUME_ROLE();

        vm.startPrank(admin);
        verifier.grantRole(pauseRole, admin);
        verifier.grantRole(resumeRole, admin);
        vm.stopPrank();

        _setMocks();
    }

    function test_processWithdrawalProof_HappyPath() public {
        WithdrawnValidatorInfo[] memory withdrawals = new WithdrawnValidatorInfo[](1);
        withdrawals[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(IBaseModule.reportRegularWithdrawnValidators.selector, withdrawals)
        );

        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_ZeroWithdrawalIndex() public {
        {
            _loadFixtureWithWithdrawalOffset(0);
            _setMocks();
        }

        test_processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_RevertWhen_WithdrawalBlockSlotUnsupported() public {
        fixture.data.withdrawalBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(IVerifier.UnsupportedSlot.selector, fixture.data.withdrawalBlock.header.slot)
        );
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidWithdrawalBlock() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.withdrawalBlock.rootsTimestamp),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidBlockHeader.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidWithdrawalCredentials() public {
        fixture.data.validator.object.withdrawalCredentials = someBytes32();

        vm.expectRevert(IVerifier.InvalidWithdrawalAddress.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidWithdrawalAddress() public {
        fixture.data.withdrawal.object.withdrawalAddress = nextAddress();

        vm.expectRevert(IVerifier.InvalidWithdrawalAddress.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidPublicKey() public {
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getSigningKeys.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            ),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidPublicKey.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_ValidatorSlashed() public {
        fixture.data.validator.object.slashed = true;

        vm.expectRevert(IVerifier.ValidatorIsSlashed.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_ValidatorIsNotWithdrawable() public {
        fixture.data.validator.object.withdrawableEpoch = fixture.data.withdrawalBlock.header.slot.unwrap() / 32 + 1;

        vm.expectRevert(IVerifier.ValidatorIsNotWithdrawable.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_ValidatorIndexDoesNotMatch() public {
        fixture.data.withdrawal.object.validatorIndex = fixture.data.validator.index + 1;

        vm.expectRevert(IVerifier.InvalidValidatorIndex.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_HappyPath_WithAddedBalance() public {
        // Use a small verified added balance so the threshold stays below the fixture's 32 ETH withdrawal.
        // absolute = 3 ether + 32 ether = 35 ether; threshold = 35 * 9000 / 10000 = 31.5 ETH < 32 ETH
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getKeyConfirmedBalances.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex,
                1
            ),
            abi.encode(UintArr(3 ether))
        );

        WithdrawnValidatorInfo[] memory withdrawals = new WithdrawnValidatorInfo[](1);
        withdrawals[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(IBaseModule.reportRegularWithdrawnValidators.selector, withdrawals)
        );

        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_HappyPath_MaxEffectiveBalance() public {
        // threshold = 2048 * 9000 / 10000 = 1843.2 ETH = 1_843_200_000_000 gwei
        // Reload fixture with the minimal expected withdrawal amount.
        _loadFixtureWithAmount({ offset: 11, amountGwei: 1_843_200_000_000 });
        _setMocks();

        // Mock keyConfirmedBalance for a fully consolidated validator (2048 - 32 = 2016 ETH added).
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getKeyConfirmedBalances.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex,
                1
            ),
            abi.encode(UintArr(2016 ether))
        );

        WithdrawnValidatorInfo[] memory withdrawals = new WithdrawnValidatorInfo[](1);
        withdrawals[0] = WithdrawnValidatorInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.data.withdrawal.object.amount) * 1e9,
            slashingPenalty: 0,
            isSlashed: false
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(IBaseModule.reportRegularWithdrawnValidators.selector, withdrawals)
        );

        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_PartialWithdrawal() public {
        // 32 ether in gwei * 9000 / 10000 = 28_800_000_000 gwei = 28.8 ether
        fixture.data.withdrawal.object.amount = 28_800_000_000 - 1;

        vm.expectRevert(IVerifier.PartialWithdrawal.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_PartialWithdrawal_WithAddedBalance() public {
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getKeyConfirmedBalances.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex,
                1
            ),
            abi.encode(UintArr(100 ether))
        );

        // absolute = 100 + 32 = 132 ether; 132 ether in gwei * 9000 / 10000 = 118_800_000_000 gwei = 118.8 ether
        fixture.data.withdrawal.object.amount = 118_800_000_000 - 1;

        vm.expectRevert(IVerifier.PartialWithdrawal.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_PartialWithdrawal_MaxEffectiveBalance() public {
        // Mock keyConfirmedBalance for a fully consolidated validator (2048 - 32 = 2016 ETH added).
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getKeyConfirmedBalances.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex,
                1
            ),
            abi.encode(UintArr(2016 ether))
        );

        // threshold = 2048 * 9000 / 10000 = 1843.2 ETH = 1_843_200_000_000 gwei
        // Reverts before SSZ proof check, so modifying amount is safe.
        fixture.data.withdrawal.object.amount = 1_843_200_000_000 - 1;

        vm.expectRevert(IVerifier.PartialWithdrawal.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_ForkBeforePivot() public {
        verifier = new Verifier({
            withdrawalAddress: fixture.data.withdrawal.object.withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: GIndices.WITHDRAWALS_ELECTRA,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: GIndices.VALIDATORS_ELECTRA,
                gIValidators: NULL_GINDEX,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.withdrawalBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        test_processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_ForkAtPivot() public {
        vm.skip(true, "progressive-list helpers and fixtures are not ready yet");

        verifier = new Verifier({
            withdrawalAddress: fixture.data.withdrawal.object.withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: GIndices.WITHDRAWALS_ELECTRA,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_ELECTRA,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.withdrawalBlock.header.slot,
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        test_processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_ForkAfterPivot() public {
        vm.skip(true, "progressive-list helpers and fixtures are not ready yet");

        verifier = new Verifier({
            withdrawalAddress: fixture.data.withdrawal.object.withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: GIndices.WITHDRAWALS_ELECTRA,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_ELECTRA,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        test_processWithdrawalProof_HappyPath();
    }

    function _setMocks() internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.withdrawalBlock.rootsTimestamp),
            abi.encode(fixture.blockRoot)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(IBaseModule.getSigningKeys.selector, 0, 0),
            abi.encode(fixture.data.validator.object.pubkey)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getKeyConfirmedBalances.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex,
                1
            ),
            abi.encode(UintArr(0))
        );

        vm.mockCall(address(module), abi.encodeWithSelector(IBaseModule.reportRegularWithdrawnValidators.selector), "");
    }

    function _loadFixture() internal {
        _loadFixtureWithWithdrawalOffset(11);
    }

    function _loadFixtureWithWithdrawalOffset(uint8 offset) internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/withdrawal.mjs";
        cmd[3] = offset.toString();
        bytes memory res = vm.ffi(cmd);
        fixture = abi.decode(res, (Fixture));
    }

    function _loadFixtureWithAmount(uint8 offset, uint256 amountGwei) internal {
        string[] memory cmd = new string[](5);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/withdrawal.mjs";
        cmd[3] = offset.toString();
        cmd[4] = Strings.toString(amountGwei);
        bytes memory res = vm.ffi(cmd);
        fixture = abi.decode(res, (Fixture));
    }

    function ffi_interface(Fixture memory) external {}
}

contract VerifierSlashingTest is VerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        IVerifier.ProcessSlashedInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture();

        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new Verifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: GIndices.VALIDATORS_ELECTRA,
                gIValidators: GIndices.VALIDATORS_ELECTRA,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: Slot.wrap(8192),
            // Route through the pre-Gloas (static-list) branch.
            pivotSlot: fixture.data.recentBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        pauseRole = verifier.PAUSE_ROLE();
        resumeRole = verifier.RESUME_ROLE();

        vm.startPrank(admin);
        verifier.grantRole(pauseRole, admin);
        verifier.grantRole(resumeRole, admin);
        vm.stopPrank();

        _setMocks();

        assertGt(verifier.FIRST_SUPPORTED_SLOT().unwrap(), 0, "Non-zero slot needed for tests");
    }

    function test_processSlashed_HappyPath() public {
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.reportValidatorSlashing.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            )
        );

        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashed_RevertWhenPaused() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);

        vm.expectRevert(PausableUntil.ResumedExpected.selector, address(verifier));
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashed_RevertWhen_RecentBlockSlotUnsupported() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(IVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashed_RevertWhen_NotSlashed() public {
        fixture.data.validator.object.slashed = false;

        vm.expectRevert(IVerifier.ValidatorIsNotSlashed.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashed_RevertWhen_InvalidPublicKey() public {
        fixture.data.validator.object.pubkey = hex"deadbeef";

        vm.expectRevert(IVerifier.InvalidPublicKey.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashed_RevertWhen_InvalidBlockHeader() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidBlockHeader.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function _setMocks() internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(fixture.blockRoot)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getSigningKeys.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            ),
            abi.encode(fixture.data.validator.object.pubkey)
        );

        vm.mockCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorSlashing.selector), "");
    }

    function _loadFixture() internal {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/slashing.mjs";
        bytes memory res = vm.ffi(cmd);
        fixture = abi.decode(res, (Fixture));
    }

    function ffi_interface(Fixture memory) external {}
}

contract VerifierPauseTest is VerifierTestBase {
    function setUp() public {
        module = new Stub();
        admin = nextAddress("ADMIN");
        stranger = nextAddress("STRANGER");

        verifier = new Verifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: NULL_GINDEX,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: Slot.wrap(100_500), // Any value less than the slots from the fixtures.
            pivotSlot: Slot.wrap(100_500),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        pauseRole = verifier.PAUSE_ROLE();
        resumeRole = verifier.RESUME_ROLE();

        vm.startPrank(admin);
        verifier.grantRole(pauseRole, admin);
        verifier.grantRole(resumeRole, admin);
        vm.stopPrank();
    }

    function test_pause() public {
        assertFalse(verifier.isPaused());
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());
    }

    function test_pause_RevertWhenNoRole() public {
        expectRoleRevert(stranger, pauseRole);
        vm.prank(stranger);
        verifier.pauseFor(100_500);
    }

    function test_pause_RevertWhenPaused() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        vm.prank(admin);
        verifier.pauseFor(100_500);
    }

    function test_resume() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());

        vm.prank(admin);
        verifier.resume();
        assertFalse(verifier.isPaused());
    }

    function test_resume_RevertWhenNoRole() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());

        expectRoleRevert(stranger, resumeRole);
        vm.prank(stranger);
        verifier.resume();
    }

    function test_resume_RevertWhenNotPaused() public {
        vm.expectRevert(PausableUntil.PausedExpected.selector);
        vm.prank(admin);
        verifier.resume();
    }

    function test_processWithdrawalProof_RevertWhenPaused() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());

        IVerifier.ProcessWithdrawalInput memory emptyInput;
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processWithdrawalProof(emptyInput);
    }

    function test_processHistoricalWithdrawalProof_RevertWhenPaused() public {
        vm.prank(admin);
        verifier.pauseFor(100_500);
        assertTrue(verifier.isPaused());

        IVerifier.ProcessHistoricalWithdrawalInput memory emptyInput;
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processHistoricalWithdrawalProof(emptyInput);
    }
}

contract VerifierTestable is Verifier {
    constructor(
        address withdrawalAddress,
        address module,
        uint64 slotsPerEpoch,
        IVerifier.GIndices memory gindices,
        Slot firstSupportedSlot,
        Slot pivotSlot,
        Slot capellaSlot,
        uint256 minWithdrawalRatio,
        address admin
    )
        Verifier(
            withdrawalAddress,
            module,
            slotsPerEpoch,
            gindices,
            firstSupportedSlot,
            pivotSlot,
            capellaSlot,
            minWithdrawalRatio,
            admin
        )
    {}

    function getValidatorGI(uint256 offset, Slot stateSlot) external view returns (GIndex) {
        return _getValidatorGI(offset, stateSlot);
    }

    function getWithdrawalGI(uint256 offset, Slot stateSlot) external view returns (GIndex) {
        return _getWithdrawalGI(offset, stateSlot);
    }

    function getValidatorBalanceGI(uint256 offset, Slot stateSlot) external view returns (GIndex) {
        return _getValidatorBalanceGI(offset, stateSlot);
    }

    function getHistoricalBlockRootGI(Slot recentSlot, Slot targetSlot) external view returns (GIndex) {
        return _getHistoricalBlockRootGI(recentSlot, targetSlot);
    }

    function verifyValidatorBalance(
        uint256 validatorIndex,
        bytes32 balanceNode,
        bytes32 stateRoot,
        Slot stateSlot,
        bytes32[] calldata proof
    ) external view returns (uint256) {
        return _verifyValidatorBalance(validatorIndex, balanceNode, stateRoot, stateSlot, proof);
    }

    function getValidatorBalanceNodeInfo(
        bytes32 balanceNode,
        uint256 validatorIndex,
        Slot stateSlot
    ) external view returns (GIndex gI, uint256 balance) {
        return _getValidatorBalanceNodeInfo(balanceNode, validatorIndex, stateSlot);
    }

    function getParentBlockRoot(uint64 blockTimestamp) external view returns (bytes32) {
        return _getParentBlockRoot(blockTimestamp);
    }
}

contract VerifierGIndexTest is Test, Utilities {
    VerifierTestable public verifier;
    address public admin;
    Stub public module;

    function setUp() public virtual {
        module = new Stub();
        admin = nextAddress("ADMIN");

        // Pre-Gloas values are ad-hoc test fabrications; Gloas-side values are
        // the real `BeaconState` field gindices.
        verifier = new VerifierTestable({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0x70e),
                gIWithdrawals: toGIndex(0xb97),
                gIValidatorsPreGloas: toGIndex(0x2b),
                gIValidators: toGIndex(0x166),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0xb86),
                gIBalancesPreGloas: toGIndex(0x4c),
                gIBalances: toGIndex(0x167)
            }),
            firstSupportedSlot: Slot.wrap(8192),
            pivotSlot: Slot.wrap(8192 * 13),
            capellaSlot: Slot.wrap(8192),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        assertTrue(verifier.PIVOT_SLOT() > verifier.FIRST_SUPPORTED_SLOT());
    }

    function test_getValidatorGI_BeforeForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.FIRST_SUPPORTED_SLOT();
        slots[1] = verifier.FIRST_SUPPORTED_SLOT().inc();
        slots[2] = verifier.PIVOT_SLOT().dec();

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getValidatorGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0x560000000000).unwrap());

            gI = verifier.getValidatorGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0x560000000001).unwrap());

            gI = verifier.getValidatorGI(16, slot);
            assertEq(gI.unwrap(), toGIndex(0x560000000010).unwrap());

            gI = verifier.getValidatorGI(17, slot);
            assertEq(gI.unwrap(), toGIndex(0x560000000011).unwrap());

            gI = verifier.getValidatorGI((2 ** 40) - 1, slot);
            assertEq(gI.unwrap(), toGIndex(0x56ffffffffff).unwrap());
        }
    }

    // Expected gindices computed off-chain via remerkleable's
    // `to_gindex_progressive(i)` concatenated with real Gloas
    // `BeaconState.validators` gindex (0x166).
    function test_getValidatorGI_AfterForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.PIVOT_SLOT();
        slots[1] = verifier.PIVOT_SLOT().inc();
        slots[2] = Slot.wrap(type(uint64).max);

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getValidatorGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0x598).unwrap());

            gI = verifier.getValidatorGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0x2cc8).unwrap());

            gI = verifier.getValidatorGI(16, slot);
            assertEq(gI.unwrap(), toGIndex(0x1666b).unwrap());

            gI = verifier.getValidatorGI(17, slot);
            assertEq(gI.unwrap(), toGIndex(0x1666c).unwrap());

            gI = verifier.getValidatorGI((2 ** 40) - 1, slot);
            assertEq(gI.unwrap(), toGIndex(0x599ffffeaaaaaaaaaa).unwrap());
        }
    }

    function test_getWithdrawalGI_BeforeForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.FIRST_SUPPORTED_SLOT();
        slots[1] = verifier.FIRST_SUPPORTED_SLOT().inc();
        slots[2] = verifier.PIVOT_SLOT().dec();

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getWithdrawalGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0xe1c0).unwrap());

            gI = verifier.getWithdrawalGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0xe1c1).unwrap());

            gI = verifier.getWithdrawalGI(15, slot);
            assertEq(gI.unwrap(), toGIndex(0xe1cf).unwrap());
        }
    }

    // Expected gindices computed off-chain via remerkleable's
    // `to_gindex_progressive(i)` concatenated with real Gloas
    // `BeaconState.payload_expected_withdrawals` gindex (0xb97).
    function test_getWithdrawalGI_AfterForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.PIVOT_SLOT();
        slots[1] = verifier.PIVOT_SLOT().inc();
        slots[2] = Slot.wrap(type(uint64).max);

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getWithdrawalGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0x2e5c).unwrap());

            gI = verifier.getWithdrawalGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0x172e8).unwrap());

            gI = verifier.getWithdrawalGI(15, slot);
            assertEq(gI.unwrap(), toGIndex(0xb976a).unwrap());
        }
    }

    function test_getValidatorBalanceGI_BeforeForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.FIRST_SUPPORTED_SLOT();
        slots[1] = verifier.FIRST_SUPPORTED_SLOT().inc();
        slots[2] = verifier.PIVOT_SLOT().dec();

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getValidatorBalanceGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0x260000000000).unwrap());

            gI = verifier.getValidatorBalanceGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0x260000000001).unwrap());

            gI = verifier.getValidatorBalanceGI(16, slot);
            assertEq(gI.unwrap(), toGIndex(0x260000000010).unwrap());

            gI = verifier.getValidatorBalanceGI(17, slot);
            assertEq(gI.unwrap(), toGIndex(0x260000000011).unwrap());

            // Max balance-node index: balances are packed 4 uint64 per node, so the
            // node tree depth is log2(VALIDATOR_REGISTRY_LIMIT / 4) = 38.
            gI = verifier.getValidatorBalanceGI((2 ** 38) - 1, slot);
            assertEq(gI.unwrap(), toGIndex(0x263fffffffff).unwrap());
        }
    }

    function test_getValidatorBalanceGI_AfterForkChange() public view {
        Slot[] memory slots = new Slot[](3);

        slots[0] = verifier.PIVOT_SLOT();
        slots[1] = verifier.PIVOT_SLOT().inc();
        slots[2] = Slot.wrap(type(uint64).max);

        GIndex gI;

        for (uint256 i = 0; i < slots.length; i++) {
            Slot slot = slots[i];

            gI = verifier.getValidatorBalanceGI(0, slot);
            assertEq(gI.unwrap(), toGIndex(0x59c).unwrap());

            gI = verifier.getValidatorBalanceGI(1, slot);
            assertEq(gI.unwrap(), toGIndex(0x2ce8).unwrap());

            gI = verifier.getValidatorBalanceGI(16, slot);
            assertEq(gI.unwrap(), toGIndex(0x1676b).unwrap());

            gI = verifier.getValidatorBalanceGI(17, slot);
            assertEq(gI.unwrap(), toGIndex(0x1676c).unwrap());

            gI = verifier.getValidatorBalanceGI((2 ** 38) - 1, slot);
            assertEq(gI.unwrap(), toGIndex(0xb3bffffaaaaaaaaaa).unwrap());
        }
    }

    function test_getHistoricalBlockRootGI_RecentSlotBeforePivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().dec();
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[0].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000000000).unwrap());

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[0].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000000001).unwrap());

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[4].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000011f92).unwrap());
    }

    function test_getHistoricalBlockRootGI_RecentSlotAfterPivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().add(8192);
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8192 + 0);
        // historicalSummaries[0].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0xb860000).unwrap());

        targetSlot = Slot.wrap(8192 + 1);
        // historicalSummaries[0].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0xb860001).unwrap());

        targetSlot = Slot.wrap(8192 + 8192 * 4 + 8082);
        // historicalSummaries[4].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x5c32df92).unwrap());

        recentSlot = Slot.wrap(type(uint64).max);
        // The last slot a historical summary might be created for.
        targetSlot = Slot.wrap(8192 + 2 ** 24 * 8192 - 1);
        // historicalSummaries[16777215].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0xb867ffaaaaaa9fff).unwrap());
    }

    function test_getHistoricalBlockRootGI_RevertWhen_SummaryCannotExist() public {
        Slot recentSlot;
        Slot targetSlot;

        targetSlot = Slot.wrap(8192);
        recentSlot = Slot.wrap(8192);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(8192);
        recentSlot = Slot.wrap(8193);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(8192);
        recentSlot = Slot.wrap(8192 + 8191);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(8192);
        recentSlot = Slot.wrap(8191);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
    }
}

contract VerifierGIndexCapellaZeroTest is Test, Utilities {
    VerifierTestable public verifier;
    address public admin;
    Stub public module;

    function setUp() public {
        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new VerifierTestable({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: toGIndex(0x70e),
                gIWithdrawals: toGIndex(0xb97),
                gIValidatorsPreGloas: toGIndex(0x2b),
                gIValidators: toGIndex(0x166),
                gIHistoricalSummariesPreGloas: toGIndex(0x3b),
                gIHistoricalSummaries: toGIndex(0xb86),
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: Slot.wrap(0),
            pivotSlot: Slot.wrap(8192 * 13),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_getHistoricalBlockRootGI_BeforePivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().dec();
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8191);
        // historicalSummaries[0].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000001fff).unwrap());

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[1].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000004000).unwrap());

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[1].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000004001).unwrap());

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[5].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x1d8000015f92).unwrap());
    }

    function test_getHistoricalBlockRootGI_AfterPivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().add(8192);
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8191);
        // historicalSummaries[0].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0xb861fff).unwrap());

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[1].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x5c320000).unwrap());

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[1].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x5c320001).unwrap());

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[5].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x2e1981f92).unwrap());

        targetSlot = verifier.PIVOT_SLOT().dec();
        // historicalSummaries[12].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x2e199dfff).unwrap());

        targetSlot = verifier.PIVOT_SLOT().add(2197);
        // historicalSummaries[13].blockRoots[2197]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), toGIndex(0x2e19a0895).unwrap());
    }

    function test_getHistoricalBlockRootGI_RevertWhen_SummaryCannotExist() public {
        Slot recentSlot;
        Slot targetSlot;

        targetSlot = Slot.wrap(0);
        recentSlot = Slot.wrap(0);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(0);
        recentSlot = Slot.wrap(8191);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(8191);
        recentSlot = Slot.wrap(8191);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);

        targetSlot = Slot.wrap(8192);
        recentSlot = Slot.wrap(8191);
        vm.expectRevert(IVerifier.HistoricalSummaryDoesNotExist.selector);
        verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
    }
}

contract VerifierValidatorBalanceTest is Test, Utilities {
    // @see ../script/ssz_list_uint64.mjs

    VerifierTestable public verifier;
    address public admin;
    Stub public module;

    function setUp() public virtual {
        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new VerifierTestable({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: NULL_GINDEX,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: toGIndex(2)
            }),
            firstSupportedSlot: Slot.wrap(8192),
            pivotSlot: Slot.wrap(8192 * 13),
            capellaSlot: Slot.wrap(8192),
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_validatorBalance_Index_0() public view {
        bytes32[] memory proof = new bytes32[](3);

        // prettier-ignore
        {
            proof[0] = 0xe39ab07307000000000000000000000000000000000000002120b07307000000;
            proof[1] = 0xd7b8f9581adbdd02f99ab10acdbccd05a694d6f1d98a118c8422d91c151c4aac;
            proof[2] = 0x0a00000000000000000000000000000000000000000000000000000000000000;
        }

        uint256 balance = verifier.verifyValidatorBalance({
            validatorIndex: 0,
            balanceNode: 0x93f5317407000000dc7c7a7607000000dd7c7a76070000000aa1b07307000000,
            stateRoot: 0xf0b08e19548a9c618b163e30c63453c721b18c6e246ac0b742464c3adb43189e,
            stateSlot: verifier.PIVOT_SLOT(),
            proof: proof
        });

        assertEq(balance, 32014202259);
    }

    function test_validatorBalance_Index_1() public view {
        bytes32[] memory proof = new bytes32[](3);

        // prettier-ignore
        {
            proof[0] = 0xe39ab07307000000000000000000000000000000000000002120b07307000000;
            proof[1] = 0xd7b8f9581adbdd02f99ab10acdbccd05a694d6f1d98a118c8422d91c151c4aac;
            proof[2] = 0x0a00000000000000000000000000000000000000000000000000000000000000;
        }

        uint256 balance = verifier.verifyValidatorBalance({
            validatorIndex: 1,
            balanceNode: 0x93f5317407000000dc7c7a7607000000dd7c7a76070000000aa1b07307000000,
            stateRoot: 0xf0b08e19548a9c618b163e30c63453c721b18c6e246ac0b742464c3adb43189e,
            stateSlot: verifier.PIVOT_SLOT(),
            proof: proof
        });

        assertEq(balance, 32052509916);
    }

    function test_validatorBalance_Index_7() public view {
        bytes32[] memory proof = new bytes32[](6);

        // prettier-ignore
        {
            proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            proof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            proof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            proof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            proof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            proof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
        }

        uint256 balance = verifier.verifyValidatorBalance({
            validatorIndex: 7,
            balanceNode: 0xe39ab07307000000000000000000000000000000000000002120b07307000000,
            stateRoot: 0x74c31584d144ea7d84cb5e479e73997e8aed9673665a8bfd4b9c605caa5bed17,
            stateSlot: verifier.PIVOT_SLOT(),
            proof: proof
        });

        assertEq(balance, 32005693473);
    }

    function test_validatorBalance_ZeroBalance() public view {
        bytes32[] memory proof = new bytes32[](6);

        // prettier-ignore
        {
            proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            proof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            proof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            proof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            proof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            proof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
        }

        uint256 balance = verifier.verifyValidatorBalance({
            validatorIndex: 5,
            balanceNode: 0xe39ab07307000000000000000000000000000000000000002120b07307000000,
            stateRoot: 0x74c31584d144ea7d84cb5e479e73997e8aed9673665a8bfd4b9c605caa5bed17,
            stateSlot: verifier.PIVOT_SLOT(),
            proof: proof
        });

        assertEq(balance, 0);
    }

    function test_validatorBalance_MaxBalance() public view {
        bytes32[] memory proof = new bytes32[](6);

        // prettier-ignore
        {
            proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
            proof[1] = 0xf5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b;
            proof[2] = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
            proof[3] = 0xc78009fdf07fc56a11f122370658a353aaa542ed63e44c4bc15ff4cd105ab33c;
            proof[4] = 0x536d98837f2dd165a55d5eeae91485954472d56f246df256bf3cae19352a123c;
            proof[5] = 0x9efde052aa15429fae05bad4d0b1d7c64da64d03d7a1854a588c2cb8430c0d30;
        }

        uint256 balance = verifier.verifyValidatorBalance({
            validatorIndex: 10,
            balanceNode: 0x0a51b073070000001cb8b07307000000ffffffffffffffff0000000000000000,
            stateRoot: 0x3e0e68c19d0844990c62b60c962b1225af8592826f5f0e3bb106bdc205e9094a,
            stateSlot: verifier.PIVOT_SLOT(),
            proof: proof
        });

        assertEq(balance, type(uint64).max);
    }

    function test_validatorBalance_NodeInfo_Balance() public {
        uint256 balance;

        for (uint256 i = 0; i < 4; ++i) {
            (, balance) = verifier.getValidatorBalanceNodeInfo(
                0x0000000000000000000000000000000000000000000000000000000000000000,
                0,
                verifier.PIVOT_SLOT()
            );
            assertEq(balance, 0);
        }

        (, balance) = verifier.getValidatorBalanceNodeInfo(
            0x1112131415161718ffffffffffffffffffffffffffffffffffffffffffffffff,
            0,
            verifier.PIVOT_SLOT()
        );
        assertEq(balance, 0x1817161514131211);

        (, balance) = verifier.getValidatorBalanceNodeInfo(
            0xffffffffffffffff1112131415161718ffffffffffffffffffffffffffffffff,
            1,
            verifier.PIVOT_SLOT()
        );
        assertEq(balance, 0x1817161514131211);

        (, balance) = verifier.getValidatorBalanceNodeInfo(
            0xffffffffffffffffffffffffffffffff1112131415161718ffffffffffffffff,
            2,
            verifier.PIVOT_SLOT()
        );
        assertEq(balance, 0x1817161514131211);

        (, balance) = verifier.getValidatorBalanceNodeInfo(
            0xffffffffffffffffffffffffffffffffffffffffffffffff1112131415161718,
            3,
            verifier.PIVOT_SLOT()
        );
        assertEq(balance, 0x1817161514131211);

        (, balance) = verifier.getValidatorBalanceNodeInfo(
            0x1112131415161718ffffffffffffffffffffffffffffffffffffffffffffffff,
            4,
            verifier.PIVOT_SLOT()
        );
        assertEq(balance, 0x1817161514131211);
    }
}

contract VerifierBalanceProofTest is VerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        IVerifier.ProcessBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture();

        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new Verifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: GIndices.VALIDATORS_ELECTRA,
                gIValidators: GIndices.VALIDATORS_ELECTRA,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: GIndices.BALANCES_ELECTRA,
                gIBalances: GIndices.BALANCES_ELECTRA
            }),
            firstSupportedSlot: fixture.data.recentBlock.header.slot.dec(),
            // Route through the pre-Gloas (static-list) branch.
            pivotSlot: fixture.data.recentBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        pauseRole = verifier.PAUSE_ROLE();
        resumeRole = verifier.RESUME_ROLE();

        vm.startPrank(admin);
        verifier.grantRole(pauseRole, admin);
        verifier.grantRole(resumeRole, admin);
        vm.stopPrank();

        _setMocks();
    }

    // TODO: Add test for Gloas path.
    function test_processBalanceProof_HappyPath() public {
        vm.expectCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorBalance.selector));

        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_SlotUnsupported() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(IVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidBlockHeader() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidBlockHeader.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidBalanceNode() public {
        fixture.data.balance.node = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidPublicKey() public {
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getSigningKeys.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            ),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidPublicKey.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_ValidatorIsWithdrawable() public {
        fixture.data.validator.object.withdrawableEpoch = uint64(fixture.data.recentBlock.header.slot.unwrap() / 32);

        vm.expectRevert(IVerifier.ValidatorIsWithdrawable.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_Paused() public {
        vm.prank(admin);
        verifier.pauseFor(1 days);

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function _setMocks() internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(fixture.blockRoot)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getSigningKeys.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            ),
            abi.encode(fixture.data.validator.object.pubkey)
        );

        vm.mockCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorBalance.selector), "");
    }

    function _loadFixture() internal {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/balance.mjs";
        bytes memory res = vm.ffi(cmd);
        fixture = abi.decode(res, (Fixture));
    }

    function ffi_interface(Fixture memory) external {}
}

contract VerifierParentBlockRootTest is Test, Utilities {
    VerifierTestable public verifier;
    address public admin;
    Stub public module;

    // @see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4788.md
    // The code is obtained via `cast code 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02`
    bytes internal BEACON_ROOTS_CODE =
        hex"3373fffffffffffffffffffffffffffffffffffffffe14604d57602036146024575f5ffd5b5f35801560495762001fff810690815414603c575f5ffd5b62001fff01545f5260205ff35b5f5ffd5b62001fff42064281555f359062001fff015500";
    address internal SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

    function setUp() public virtual {
        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new VerifierTestable({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: NULL_GINDEX,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX
            }),
            firstSupportedSlot: Slot.wrap(8192),
            pivotSlot: Slot.wrap(8192 * 13),
            capellaSlot: Slot.wrap(8192),
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function testFuzz_getParentBlockRoot_HappyPath(bytes32 expected, uint64 ts) public {
        vm.assume(ts > 0); // The EIP-4788 reverts with 0 as an input.

        vm.etch(verifier.BEACON_ROOTS(), BEACON_ROOTS_CODE);

        // Sets the block root for the timestamp.
        {
            vm.startPrank(SYSTEM_ADDRESS);
            vm.warp(ts);
            (bool success, ) = verifier.BEACON_ROOTS().call(abi.encode(expected));
            assertTrue(success);
            vm.stopPrank();
        }

        bytes32 actual = verifier.getParentBlockRoot(ts);
        assertEq(actual, expected);
    }

    function test_getParentBlockRoot_RevertWhen_NoCodeAt4788Contract() public {
        vm.etch(verifier.BEACON_ROOTS(), hex"");
        vm.expectRevert(IVerifier.RootNotFound.selector);
        verifier.getParentBlockRoot(42);
    }

    function test_getParentBlockRoot_RevertWhen_4788ContractReverts() public {
        vm.etch(verifier.BEACON_ROOTS(), hex"5F5FFD"); // revert(0,0)
        vm.expectRevert(IVerifier.RootNotFound.selector);
        verifier.getParentBlockRoot(42);
    }

    function test_getParentBlockRoot_RevertWhen_RootNotFound() public {
        vm.etch(verifier.BEACON_ROOTS(), BEACON_ROOTS_CODE);
        vm.expectRevert(IVerifier.RootNotFound.selector);
        verifier.getParentBlockRoot(42);
    }
}
