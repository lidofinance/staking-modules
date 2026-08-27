// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { Verifier } from "src/Verifier.sol";
import { toGIndex } from "src/lib/GIndex.sol";
import { BeaconBlockHeader, Slot } from "src/lib/Types.sol";
import { GIndex } from "src/lib/GIndex.sol";
import { SSZ } from "src/lib/SSZ.sol";
import { WCType, toWC } from "src/utils/WithdrawalCredentials.sol";

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
        bytes32 withdrawalCredentials = someBytes32();

        verifier = new Verifier({
            withdrawalCredentials: withdrawalCredentials,
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
                gIBalances: toGIndex(0x160000000001),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
            }),
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: Slot.wrap(100_501),
            capellaSlot: Slot.wrap(42),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        assertEq(verifier.WITHDRAWAL_CREDENTIALS(), withdrawalCredentials);
        assertEq(address(verifier.MODULE()), address(module));
        assertEq(verifier.SLOTS_PER_EPOCH(), 32);
        assertEq(verifier.SLOTS_PER_HISTORICAL_ROOT(), 8192);
        assertEq(GIndex.unwrap(verifier.GI_WITHDRAWALS_PRE_GLOAS()), 0xe1c0);
        assertEq(GIndex.unwrap(verifier.GI_WITHDRAWALS()), 0xe1c1);
        assertEq(GIndex.unwrap(verifier.GI_VALIDATORS_PRE_GLOAS()), 0x560000000000);
        assertEq(GIndex.unwrap(verifier.GI_VALIDATORS()), 0x560000000001);
        assertEq(GIndex.unwrap(verifier.GI_HISTORICAL_SUMMARIES_PRE_GLOAS()), 0xfff0);
        assertEq(GIndex.unwrap(verifier.GI_HISTORICAL_SUMMARIES()), 0xffff);
        assertEq(GIndex.unwrap(verifier.GI_BLOCK_ROOT_IN_SUMMARY()), 2);
        assertEq(GIndex.unwrap(verifier.GI_BALANCES_PRE_GLOAS()), 0x160000000000);
        assertEq(GIndex.unwrap(verifier.GI_BALANCES()), 0x160000000001);
        assertEq(Slot.unwrap(verifier.FIRST_SUPPORTED_SLOT()), Slot.unwrap(firstSupportedSlot));
        assertEq(Slot.unwrap(verifier.PIVOT_SLOT()), Slot.unwrap(Slot.wrap(100_501)));
        assertEq(Slot.unwrap(verifier.CAPELLA_SLOT()), Slot.unwrap(Slot.wrap(42)));
        assertEq(verifier.MIN_WITHDRAWAL_RATIO(), 9000);
    }

    function test_constructor_RevertWhen_InvalidChainConfig_SlotsPerEpoch() public {
        vm.expectRevert(IVerifier.InvalidChainConfig.selector);
        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
            }),
            firstSupportedSlot: firstSupportedSlot, // Any value less than the slots from the fixtures.
            pivotSlot: firstSupportedSlot,
            capellaSlot: firstSupportedSlot,
            minWithdrawalRatio: 9000,
            admin: admin
        });
    }

    function test_constructor_RevertWhen_ZeroWithdrawalCredentials() public {
        vm.expectRevert(IVerifier.ZeroWithdrawalCredentials.selector);
        verifier = new Verifier({
            withdrawalCredentials: bytes32(0),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x260000000000),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
    using SSZ for BeaconBlockHeader;

    using Strings for uint8;
    using Strings for uint256;

    struct Fixture {
        bytes32 blockRoot;
        IVerifier.ProcessWithdrawalInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture({ fork: "electra", offset: 11, amountGwei: 32e9 });

        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new Verifier({
            withdrawalCredentials: fixture.data.validator.object.withdrawalCredentials,
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: GIndices.BLOCK_ROOTS_ELECTRA,
                gIBlockRoots: GIndices.BLOCK_ROOTS_ELECTRA
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

    function test_processWithdrawalProof_RevertWhen_UnsupportedSlot_WithdrawalBlock() public {
        fixture.data.withdrawalBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(IVerifier.UnsupportedSlot.selector, fixture.data.withdrawalBlock.header.slot)
        );
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidRecentBlock() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(IVerifier.InvalidBlockHeader.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_InvalidWithdrawalBlock() public {
        // Breaking something in the header so its hashTreeRoot no longer matches the entry in `block_roots`.
        fixture.data.withdrawalBlock.header.parentRoot = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_BlockRootNotInRange_TargetNotBeforeRecent() public {
        // target == recent: the recent block's own root is not yet in its state's ring buffer.
        fixture.data.withdrawalBlock.header.slot = fixture.data.recentBlock.header.slot;
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.processWithdrawalProof(fixture.data);

        // target > recent: target hasn't been built yet from the recent state's perspective.
        fixture.data.withdrawalBlock.header.slot = fixture.data.recentBlock.header.slot.inc();
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_BlockRootNotInRange_DistanceExceedsRing() public {
        // setUp pins FIRST_SUPPORTED_SLOT to `withdrawalBlock.slot - 1`, so there's no room to
        // shift the withdrawal slot more than SLOTS_PER_HISTORICAL_ROOT slots behind the recent
        // slot without also tripping the UnsupportedSlot guard. Instead, shift the recent block
        // far ahead and re-mock EIP-4788 (bumping its `slot` changes its hashTreeRoot, so the
        // anchor returned by the system contract must follow).
        BeaconBlockHeader memory recentBlock = fixture.data.recentBlock.header;
        recentBlock.slot = recentBlock.slot.add(100500);
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(recentBlock.hashTreeRoot())
        );
        fixture.data.recentBlock.header = recentBlock;

        // Push the withdrawal slot one slot past the ring buffer edge.
        fixture.data.withdrawalBlock.header.slot = Slot.wrap(recentBlock.slot.unwrap() - 8192 - 1);

        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.processWithdrawalProof(fixture.data);
    }

    function test_processWithdrawalProof_RevertWhen_VerifierEth1AndValidatorCompounding() public {
        address withdrawalAddress = fixture.data.withdrawal.object.withdrawalAddress;
        assertEq(verifier.WITHDRAWAL_CREDENTIALS(), toWC(withdrawalAddress, WCType.Eth1));
        fixture.data.validator.object.withdrawalCredentials = toWC(withdrawalAddress, WCType.Compounding);

        vm.expectRevert(IVerifier.InvalidWithdrawalCredentials.selector);
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

    function test_processWithdrawalProof_HappyPath_MaxEffectiveBalance() public {
        // threshold = 2048 * 9000 / 10000 = 1843.2 ETH = 1_843_200_000_000 gwei
        // Reload fixture with the minimal expected withdrawal amount.
        _loadFixture({ fork: "electra", offset: 11, amountGwei: 1_843_200_000_000 });
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

    function test_processWithdrawalProof_ZeroWithdrawalIndex() public {
        {
            _loadFixture({ fork: "electra", offset: 0, amountGwei: 32e9 });
            _setMocks();
        }

        _processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_ForkBeforePivot() public {
        {
            _loadFixture({ fork: "electra", offset: 11, amountGwei: 32e9 });
            _setMocks();
        }

        verifier = new Verifier({
            withdrawalCredentials: fixture.data.validator.object.withdrawalCredentials,
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: GIndices.BLOCK_ROOTS_ELECTRA,
                gIBlockRoots: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.recentBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        _processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_ForkAtPivot() public {
        {
            _loadFixture({ fork: "gloas", offset: 11, amountGwei: 32e9 });
            _setMocks();
        }

        verifier = new Verifier({
            withdrawalCredentials: fixture.data.validator.object.withdrawalCredentials,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: GIndices.WITHDRAWALS_GLOAS,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: GIndices.BLOCK_ROOTS_GLOAS
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.withdrawalBlock.header.slot,
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        _processWithdrawalProof_HappyPath();
    }

    function test_processWithdrawalProof_ForkAfterPivot() public {
        {
            _loadFixture({ fork: "gloas", offset: 11, amountGwei: 32e9 });
            _setMocks();
        }

        verifier = new Verifier({
            withdrawalCredentials: fixture.data.validator.object.withdrawalCredentials,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: GIndices.WITHDRAWALS_GLOAS,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: GIndices.BLOCK_ROOTS_GLOAS
            }),
            firstSupportedSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            pivotSlot: fixture.data.withdrawalBlock.header.slot.dec(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        _processWithdrawalProof_HappyPath();
    }

    function _processWithdrawalProof_HappyPath() public {
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

    function _setMocks() internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
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

    function _loadFixture(string memory fork, uint8 offset, uint256 amountGwei) internal {
        string[] memory cmd = new string[](6);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/withdrawal.mjs";
        cmd[3] = offset.toString();
        cmd[4] = Strings.toString(amountGwei);
        cmd[5] = fork;
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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

        IVerifier.ProcessWithdrawalInput memory emptyInput;
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processHistoricalWithdrawalProof(emptyInput);
    }
}

contract VerifierTestable is Verifier {
    constructor(
        bytes32 withdrawalCredentials,
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
            withdrawalCredentials,
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

    function getBlockRootsBlockGI(Slot recentSlot, Slot targetSlot) external view returns (GIndex) {
        return _getBlockRootsBlockGI(recentSlot, targetSlot);
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(0x167),
                gIBlockRootsPreGloas: toGIndex(0x45),
                gIBlockRoots: toGIndex(0x160)
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
            assertEq(gI.unwrap(), 0x560000000000);

            gI = verifier.getValidatorGI(1, slot);
            assertEq(gI.unwrap(), 0x560000000001);

            gI = verifier.getValidatorGI(16, slot);
            assertEq(gI.unwrap(), 0x560000000010);

            gI = verifier.getValidatorGI(17, slot);
            assertEq(gI.unwrap(), 0x560000000011);

            gI = verifier.getValidatorGI((2 ** 40) - 1, slot);
            assertEq(gI.unwrap(), 0x56ffffffffff);
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
            assertEq(gI.unwrap(), 0x598);

            gI = verifier.getValidatorGI(1, slot);
            assertEq(gI.unwrap(), 0x2cc8);

            gI = verifier.getValidatorGI(16, slot);
            assertEq(gI.unwrap(), 0x1666b);

            gI = verifier.getValidatorGI(17, slot);
            assertEq(gI.unwrap(), 0x1666c);

            gI = verifier.getValidatorGI((2 ** 40) - 1, slot);
            assertEq(gI.unwrap(), 0x599ffffeaaaaaaaaaa);
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
            assertEq(gI.unwrap(), 0xe1c0);

            gI = verifier.getWithdrawalGI(1, slot);
            assertEq(gI.unwrap(), 0xe1c1);

            gI = verifier.getWithdrawalGI(15, slot);
            assertEq(gI.unwrap(), 0xe1cf);
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
            assertEq(gI.unwrap(), 0x2e5c);

            gI = verifier.getWithdrawalGI(1, slot);
            assertEq(gI.unwrap(), 0x172e8);

            gI = verifier.getWithdrawalGI(15, slot);
            assertEq(gI.unwrap(), 0xb976a);
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
            assertEq(gI.unwrap(), 0x260000000000);

            gI = verifier.getValidatorBalanceGI(1, slot);
            assertEq(gI.unwrap(), 0x260000000001);

            gI = verifier.getValidatorBalanceGI(16, slot);
            assertEq(gI.unwrap(), 0x260000000010);

            gI = verifier.getValidatorBalanceGI(17, slot);
            assertEq(gI.unwrap(), 0x260000000011);

            // Max balance-node index: balances are packed 4 uint64 per node, so the
            // node tree depth is log2(VALIDATOR_REGISTRY_LIMIT / 4) = 38.
            gI = verifier.getValidatorBalanceGI((2 ** 38) - 1, slot);
            assertEq(gI.unwrap(), 0x263fffffffff);
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
            assertEq(gI.unwrap(), 0x59c);

            gI = verifier.getValidatorBalanceGI(1, slot);
            assertEq(gI.unwrap(), 0x2ce8);

            gI = verifier.getValidatorBalanceGI(16, slot);
            assertEq(gI.unwrap(), 0x1676b);

            gI = verifier.getValidatorBalanceGI(17, slot);
            assertEq(gI.unwrap(), 0x1676c);

            gI = verifier.getValidatorBalanceGI((2 ** 38) - 1, slot);
            assertEq(gI.unwrap(), 0xb3bffffaaaaaaaaaa);
        }
    }

    function test_getHistoricalBlockRootGI_RecentSlotBeforePivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().dec();
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[0].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000000000);

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[0].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000000001);

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[4].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000011f92);
    }

    function test_getHistoricalBlockRootGI_RecentSlotAfterPivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().add(8192);
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8192 + 0);
        // historicalSummaries[0].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000000000);

        targetSlot = Slot.wrap(8192 + 1);
        // historicalSummaries[0].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000000001);

        targetSlot = Slot.wrap(8192 + 8192 * 4 + 8082);
        // historicalSummaries[4].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000011f92);

        recentSlot = Slot.wrap(type(uint64).max);
        // The last slot a historical summary might be created for.
        targetSlot = Slot.wrap(8192 + 2 ** 24 * 8192 - 1);
        // historicalSummaries[16777215].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c33fffffdfff);
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

    function test_getBlockRootsBlockGI_RecentSlotBeforePivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().dec(); // 13 * 8192 - 1 = 106495
        Slot targetSlot;

        GIndex gI;

        // block_roots[8190]
        targetSlot = recentSlot.dec();
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x8bffe);

        // block_roots[0]
        targetSlot = Slot.wrap(8192 * 12);
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x8a000);

        // block_roots[1]
        targetSlot = Slot.wrap(8192 * 12 + 1);
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x8a001);

        // block_roots[8191]
        targetSlot = Slot.wrap(recentSlot.unwrap() - 8192);
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x8bfff);
    }

    function test_getBlockRootsBlockGI_RecentSlotAfterPivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().add(8192);
        Slot targetSlot;

        GIndex gI;

        // block_roots[8191]
        targetSlot = recentSlot.dec();
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x2c1fff);

        // block_roots[0]
        targetSlot = Slot.wrap(8192 * 13);
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x2c0000);

        // block_roots[3504]
        targetSlot = Slot.wrap(8192 * 13 + 3504);
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x2c0db0);

        // block_roots[8190]
        recentSlot = Slot.wrap(type(uint64).max);
        targetSlot = recentSlot.dec();
        gI = verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x2c1ffe);
    }

    function test_getBlockRootsBlockGI_RevertWhen_OutOfRange() public {
        Slot recentSlot;
        Slot targetSlot;

        // target == recent: the recent block's own root is not yet in its state's ring buffer.
        recentSlot = verifier.PIVOT_SLOT().dec();
        targetSlot = recentSlot;
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.getBlockRootsBlockGI(recentSlot, targetSlot);

        // target > recent.
        recentSlot = verifier.PIVOT_SLOT();
        targetSlot = recentSlot.inc();
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.getBlockRootsBlockGI(recentSlot, targetSlot);

        // distance > SLOTS_PER_HISTORICAL_ROOT: target = recent - 8193.
        recentSlot = Slot.wrap(20000);
        targetSlot = Slot.wrap(recentSlot.unwrap() - 8193);
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.getBlockRootsBlockGI(recentSlot, targetSlot);
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
        assertEq(gI.unwrap(), 0x1d8000001fff);

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[1].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000004000);

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[1].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000004001);

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[5].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x1d8000015f92);
    }

    function test_getHistoricalBlockRootGI_AfterPivot() public view {
        Slot recentSlot = verifier.PIVOT_SLOT().add(8192);
        Slot targetSlot;

        GIndex gI;

        targetSlot = Slot.wrap(8191);
        // historicalSummaries[0].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000001fff);

        targetSlot = Slot.wrap(8192);
        // historicalSummaries[1].blockRoots[0]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000004000);

        targetSlot = Slot.wrap(8193);
        // historicalSummaries[1].blockRoots[1]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000004001);

        targetSlot = Slot.wrap(49042);
        // historicalSummaries[5].blockRoots[8082]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000015f92);

        targetSlot = verifier.PIVOT_SLOT().dec();
        // historicalSummaries[12].blockRoots[8191]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000031fff);

        targetSlot = verifier.PIVOT_SLOT().add(2197);
        // historicalSummaries[13].blockRoots[2197]
        gI = verifier.getHistoricalBlockRootGI(recentSlot, targetSlot);
        assertEq(gI.unwrap(), 0x5c30000034895);
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: toGIndex(2),
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
    using SSZ for BeaconBlockHeader;

    struct Fixture {
        bytes32 blockRoot;
        IVerifier.ProcessBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture("gloas");

        module = new Stub();
        admin = nextAddress("ADMIN");

        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: GIndices.BALANCES_GLOAS,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: GIndices.BLOCK_ROOTS_GLOAS
            }),
            firstSupportedSlot: fixture.data.balanceBlock.header.slot.dec(),
            pivotSlot: fixture.data.balanceBlock.header.slot.dec(),
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

    function test_processBalanceProof_RevertWhen_UnsupportedSlot_BalanceBlock() public {
        fixture.data.balanceBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(IVerifier.UnsupportedSlot.selector, fixture.data.balanceBlock.header.slot)
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

    function test_processBalanceProof_RevertWhen_InvalidBalanceBlock() public {
        fixture.data.balanceBlock.header.parentRoot = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_BlockRootNotInRange() public {
        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
            }),
            firstSupportedSlot: Slot.wrap(0),
            pivotSlot: Slot.wrap(0),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });

        fixture.data.balanceBlock.header.slot = fixture.data.recentBlock.header.slot;
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.processBalanceProof(fixture.data);

        fixture.data.balanceBlock.header.slot = fixture.data.recentBlock.header.slot.inc();
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
        verifier.processBalanceProof(fixture.data);

        fixture.data.balanceBlock.header.slot = Slot.wrap(fixture.data.recentBlock.header.slot.unwrap() - 8192 - 1);
        vm.expectRevert(IVerifier.BlockRootNotInRange.selector);
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
        fixture.data.validator.object.withdrawableEpoch = uint64(fixture.data.balanceBlock.header.slot.unwrap() / 32);

        vm.expectRevert(IVerifier.ValidatorIsWithdrawable.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_Paused() public {
        vm.prank(admin);
        verifier.pauseFor(1 days);

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_ForkBeforePivot() public {
        _loadFixture("electra");
        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: GIndices.VALIDATORS_ELECTRA,
                gIValidators: NULL_GINDEX,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: GIndices.BALANCES_ELECTRA,
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: GIndices.BLOCK_ROOTS_ELECTRA,
                gIBlockRoots: NULL_GINDEX
            }),
            firstSupportedSlot: fixture.data.balanceBlock.header.slot.dec(),
            pivotSlot: fixture.data.recentBlock.header.slot.inc(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });
        _setMocks();

        vm.expectCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorBalance.selector));
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_ForkAtPivot() public {
        _loadFixture("gloas");
        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: GIndices.BALANCES_GLOAS,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: GIndices.BLOCK_ROOTS_GLOAS
            }),
            firstSupportedSlot: fixture.data.balanceBlock.header.slot.dec(),
            pivotSlot: fixture.data.balanceBlock.header.slot,
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });
        _setMocks();

        vm.expectCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorBalance.selector));
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_ForkAfterPivot() public {
        _loadFixture("gloas");
        verifier = new Verifier({
            withdrawalCredentials: someBytes32(),
            module: address(module),
            slotsPerEpoch: 32,
            gindices: IVerifier.GIndices({
                gIWithdrawalsPreGloas: NULL_GINDEX,
                gIWithdrawals: NULL_GINDEX,
                gIValidatorsPreGloas: NULL_GINDEX,
                gIValidators: GIndices.VALIDATORS_GLOAS,
                gIHistoricalSummariesPreGloas: NULL_GINDEX,
                gIHistoricalSummaries: NULL_GINDEX,
                gIBalancesPreGloas: NULL_GINDEX,
                gIBalances: GIndices.BALANCES_GLOAS,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: GIndices.BLOCK_ROOTS_GLOAS
            }),
            firstSupportedSlot: fixture.data.balanceBlock.header.slot.dec(),
            pivotSlot: fixture.data.balanceBlock.header.slot.dec(),
            capellaSlot: Slot.wrap(0),
            minWithdrawalRatio: 9000,
            admin: admin
        });
        _setMocks();

        vm.expectCall(address(module), abi.encodeWithSelector(IBaseModule.reportValidatorBalance.selector));
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

    function _loadFixture(string memory fork) internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/Verifier/balance.mjs";
        cmd[3] = fork;
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
            withdrawalCredentials: someBytes32(),
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
                gIBalances: NULL_GINDEX,
                gIBlockRootsPreGloas: NULL_GINDEX,
                gIBlockRoots: NULL_GINDEX
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
