// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { CuratedVerifier } from "src/CuratedVerifier.sol";
import { GIndex, pack } from "src/lib/GIndex.sol";
import { Slot } from "src/lib/Types.sol";
import { SSZ } from "src/lib/SSZ.sol";

import { ICuratedVerifier } from "src/interfaces/ICuratedVerifier.sol";
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

using { dec, inc } for Slot;

GIndex constant NULL_GINDEX = GIndex.wrap(0);

// The withdrawal address used by the fixtures.
address constant FIXTURE_WITHDRAWAL_ADDRESS = 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36;

contract CuratedVerifierTestBase is Test, Utilities {
    CuratedVerifier public verifier;
    Stub public module;
    address public admin;

    function _deployVerifier(
        ICuratedVerifier.GIndices memory gindices,
        Slot firstSupportedSlot,
        Slot pivotSlot
    ) internal {
        verifier = new CuratedVerifier({
            withdrawalAddress: FIXTURE_WITHDRAWAL_ADDRESS,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: gindices,
            firstSupportedSlot: firstSupportedSlot,
            pivotSlot: pivotSlot,
            capellaSlot: Slot.wrap(0),
            admin: admin
        });

        vm.startPrank(admin);
        verifier.grantRole(verifier.PAUSE_ROLE(), admin);
        verifier.grantRole(verifier.RESUME_ROLE(), admin);
        vm.stopPrank();
    }

    function _gindices(
        GIndex validator,
        GIndex historicalSummary,
        GIndex balanceNode
    ) internal pure returns (ICuratedVerifier.GIndices memory) {
        return
            ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: validator,
                gIFirstValidatorCurr: validator,
                gIFirstHistoricalSummaryPrev: historicalSummary,
                gIFirstHistoricalSummaryCurr: historicalSummary,
                gIFirstBalanceNodePrev: balanceNode,
                gIFirstBalanceNodeCurr: balanceNode
            });
    }

    function _pause() internal {
        vm.prank(admin);
        verifier.pauseFor(1 days);
    }

    function _runFixtureScript(string memory script, string memory arg) internal returns (bytes memory) {
        string[] memory cmd = new string[](bytes(arg).length == 0 ? 3 : 4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = script;
        if (bytes(arg).length != 0) cmd[3] = arg;
        return vm.ffi(cmd);
    }
}

contract CuratedVerifierConstructorTest is CuratedVerifierTestBase {
    function setUp() public {
        module = new Stub();
        admin = nextAddress("ADMIN");
    }

    function test_constructor_HappyPath() public {
        address withdrawalAddress = nextAddress("WITHDRAWAL_ADDRESS");

        verifier = new CuratedVerifier({
            withdrawalAddress: withdrawalAddress,
            module: address(module),
            slotsPerEpoch: 32,
            gindices: ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: pack(0x560000000000, 40),
                gIFirstValidatorCurr: pack(0x560000000001, 40),
                gIFirstHistoricalSummaryPrev: pack(0xfff0, 4),
                gIFirstHistoricalSummaryCurr: pack(0xffff, 4),
                gIFirstBalanceNodePrev: pack(0x160000000000, 40),
                gIFirstBalanceNodeCurr: pack(0x160000000001, 40)
            }),
            firstSupportedSlot: Slot.wrap(100_500),
            pivotSlot: Slot.wrap(100_501),
            capellaSlot: Slot.wrap(42),
            admin: admin
        });

        assertEq(verifier.WITHDRAWAL_ADDRESS(), withdrawalAddress);
        assertEq(address(verifier.MODULE()), address(module));
        assertEq(verifier.SLOTS_PER_EPOCH(), 32);
        assertEq(verifier.SLOTS_PER_HISTORICAL_ROOT(), 8192);
        assertEq(GIndex.unwrap(verifier.GI_FIRST_VALIDATOR_PREV()), GIndex.unwrap(pack(0x560000000000, 40)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_VALIDATOR_CURR()), GIndex.unwrap(pack(0x560000000001, 40)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_HISTORICAL_SUMMARY_PREV()), GIndex.unwrap(pack(0xfff0, 4)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_HISTORICAL_SUMMARY_CURR()), GIndex.unwrap(pack(0xffff, 4)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_BLOCK_ROOT_IN_SUMMARY()), GIndex.unwrap(pack(0x4000, 13)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_BALANCES_NODE_PREV()), GIndex.unwrap(pack(0x160000000000, 40)));
        assertEq(GIndex.unwrap(verifier.GI_FIRST_BALANCES_NODE_CURR()), GIndex.unwrap(pack(0x160000000001, 40)));
        assertEq(verifier.FIRST_SUPPORTED_SLOT().unwrap(), 100_500);
        assertEq(verifier.PIVOT_SLOT().unwrap(), 100_501);
        assertEq(verifier.CAPELLA_SLOT().unwrap(), 42);
        assertTrue(verifier.hasRole(verifier.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_constructor_RevertWhen_InvalidChainConfig_SlotsPerEpoch() public {
        vm.expectRevert(ICuratedVerifier.InvalidChainConfig.selector);
        _newVerifier(nextAddress(), address(module), 0, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_InvalidPivotSlot() public {
        vm.expectRevert(ICuratedVerifier.InvalidPivotSlot.selector);
        _newVerifier(nextAddress(), address(module), 32, Slot.wrap(100), Slot.wrap(99), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_InvalidCapellaSlot() public {
        vm.expectRevert(ICuratedVerifier.InvalidCapellaSlot.selector);
        _newVerifier(nextAddress(), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(101), admin);
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(ICuratedVerifier.ZeroModuleAddress.selector);
        _newVerifier(nextAddress(), address(0), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_ZeroWithdrawalAddress() public {
        vm.expectRevert(ICuratedVerifier.ZeroWithdrawalAddress.selector);
        _newVerifier(address(0), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_ZeroAdminAddress() public {
        vm.expectRevert(ICuratedVerifier.ZeroAdminAddress.selector);
        _newVerifier(nextAddress(), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), address(0));
    }

    function _newVerifier(
        address withdrawalAddress,
        address moduleAddress,
        uint64 slotsPerEpoch,
        Slot firstSupportedSlot,
        Slot pivotSlot,
        Slot capellaSlot,
        address adminAddress
    ) internal returns (CuratedVerifier) {
        return
            new CuratedVerifier({
                withdrawalAddress: withdrawalAddress,
                module: moduleAddress,
                slotsPerEpoch: slotsPerEpoch,
                gindices: _gindices(
                    GIndices.FIRST_VALIDATOR_ELECTRA,
                    GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA,
                    GIndices.FIRST_BALANCE_NODE_ELECTRA
                ),
                firstSupportedSlot: firstSupportedSlot,
                pivotSlot: pivotSlot,
                capellaSlot: capellaSlot,
                admin: adminAddress
            });
    }
}

contract CuratedVerifierWithdrawnTest is CuratedVerifierTestBase {
    // Positions of the validators in the fixture state, see `test/fixtures/CuratedVerifier/withdrawn.mjs`.
    uint256 internal constant EXITED_VALIDATOR = 0;
    uint256 internal constant CONSOLIDATED_VALIDATOR = 1;
    uint256 internal constant AT_WITHDRAWABLE_EPOCH_VALIDATOR = 2;

    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessWithdrawnInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture(EXITED_VALIDATOR);

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(_gindices(GIndices.FIRST_VALIDATOR_ELECTRA, NULL_GINDEX, NULL_GINDEX), slot, slot);

        _setMocks();
    }

    function test_processWithdrawnProof_HappyPath() public {
        vm.expectCall(
            address(module),
            abi.encodeCall(IBaseModule.reportRegularWithdrawnValidators, (_expectedInfos(32 ether)))
        );

        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_HappyPath_ConsolidatedValidator() public {
        _loadFixture(CONSOLIDATED_VALIDATOR);
        _setMocks();

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_AtWithdrawableEpoch() public {
        _loadFixture(AT_WITHDRAWABLE_EPOCH_VALIDATOR);
        _setMocks();

        assertEq(
            fixture.data.validator.object.withdrawableEpoch,
            fixture.data.recentBlock.header.slot.unwrap() / 32,
            "Validator should reach the withdrawable epoch at the epoch of the state"
        );

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_ExitBalanceIncludesConfirmedBalance() public {
        vm.mockCall(
            address(module),
            abi.encodeCall(
                IBaseModule.getKeyConfirmedBalances,
                (fixture.data.validator.nodeOperatorId, fixture.data.validator.keyIndex, 1)
            ),
            abi.encode(UintArr(100 ether))
        );

        vm.expectCall(
            address(module),
            abi.encodeCall(IBaseModule.reportRegularWithdrawnValidators, (_expectedInfos(132 ether)))
        );

        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_HappyPath_ForkBeforePivot() public {
        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(
            ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: GIndices.FIRST_VALIDATOR_ELECTRA,
                gIFirstValidatorCurr: NULL_GINDEX,
                gIFirstHistoricalSummaryPrev: NULL_GINDEX,
                gIFirstHistoricalSummaryCurr: NULL_GINDEX,
                gIFirstBalanceNodePrev: NULL_GINDEX,
                gIFirstBalanceNodeCurr: NULL_GINDEX
            }),
            slot,
            slot.inc()
        );

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_ForkAtPivot() public {
        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(
            ICuratedVerifier.GIndices({
                gIFirstValidatorPrev: NULL_GINDEX,
                gIFirstValidatorCurr: GIndices.FIRST_VALIDATOR_ELECTRA,
                gIFirstHistoricalSummaryPrev: NULL_GINDEX,
                gIFirstHistoricalSummaryCurr: NULL_GINDEX,
                gIFirstBalanceNodePrev: NULL_GINDEX,
                gIFirstBalanceNodeCurr: NULL_GINDEX
            }),
            slot.dec(),
            slot
        );

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_RevertWhen_RecentBlockSlotUnsupported() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidBlockHeader() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(someBytes32())
        );

        vm.expectRevert(ICuratedVerifier.InvalidBlockHeader.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_RootNotFound() public {
        vm.mockCallRevert(verifier.BEACON_ROOTS(), abi.encode(fixture.data.recentBlock.rootsTimestamp), "");

        vm.expectRevert(ICuratedVerifier.RootNotFound.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidWithdrawalAddress() public {
        fixture.data.validator.object.withdrawalCredentials = someBytes32();

        vm.expectRevert(ICuratedVerifier.InvalidWithdrawalAddress.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_ValidatorIsSlashed() public {
        fixture.data.validator.object.slashed = true;

        vm.expectRevert(ICuratedVerifier.ValidatorIsSlashed.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_ValidatorIsNotWithdrawable() public {
        fixture.data.validator.object.withdrawableEpoch = fixture.data.recentBlock.header.slot.unwrap() / 32 + 1;

        vm.expectRevert(ICuratedVerifier.ValidatorIsNotWithdrawable.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_ValidatorIsNotExiting() public {
        fixture.data.validator.object.exitEpoch = type(uint64).max;
        fixture.data.validator.object.withdrawableEpoch = type(uint64).max;

        vm.expectRevert(ICuratedVerifier.ValidatorIsNotWithdrawable.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidPublicKey() public {
        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.getSigningKeys.selector,
                fixture.data.validator.nodeOperatorId,
                fixture.data.validator.keyIndex
            ),
            abi.encode(hex"deadbeef")
        );

        vm.expectRevert(ICuratedVerifier.InvalidPublicKey.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidValidatorObject() public {
        fixture.data.validator.object.effectiveBalance += 1;

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidValidatorIndex() public {
        fixture.data.validator.index += 1;

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_Paused() public {
        _pause();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processWithdrawnProof(fixture.data);
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

        vm.mockCall(
            address(module),
            abi.encodeCall(
                IBaseModule.getKeyConfirmedBalances,
                (fixture.data.validator.nodeOperatorId, fixture.data.validator.keyIndex, 1)
            ),
            abi.encode(UintArr(0))
        );

        vm.mockCall(address(module), abi.encodeWithSelector(IBaseModule.reportRegularWithdrawnValidators.selector), "");
    }

    function _loadFixture(uint256 validator) internal {
        bytes memory res = _runFixtureScript("test/fixtures/CuratedVerifier/withdrawn.mjs", vm.toString(validator));
        fixture = abi.decode(res, (Fixture));
    }

    function _expectedInfos(uint256 exitBalance) internal view returns (WithdrawnValidatorInfo[] memory infos) {
        infos = new WithdrawnValidatorInfo[](1);
        infos[0] = WithdrawnValidatorInfo({
            nodeOperatorId: fixture.data.validator.nodeOperatorId,
            keyIndex: fixture.data.validator.keyIndex,
            exitBalance: exitBalance,
            slashingPenalty: 0,
            isSlashed: false
        });
    }

    function ffi_interface(Fixture memory) external {}
}

contract CuratedVerifierSlashingTest is CuratedVerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessSlashedInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        // The fixture shares the layout with `IVerifier.ProcessSlashedInput`.
        fixture = abi.decode(_runFixtureScript("test/fixtures/Verifier/slashing.mjs", ""), (Fixture));

        module = new Stub();
        admin = nextAddress("ADMIN");

        _deployVerifier(
            _gindices(GIndices.FIRST_VALIDATOR_ELECTRA, NULL_GINDEX, NULL_GINDEX),
            Slot.wrap(8192),
            Slot.wrap(8192)
        );

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

    function test_processSlashedProof_HappyPath() public {
        vm.expectCall(
            address(module),
            abi.encodeCall(
                IBaseModule.reportValidatorSlashing,
                (fixture.data.validator.nodeOperatorId, fixture.data.validator.keyIndex)
            )
        );

        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_RecentBlockSlotUnsupported() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_InvalidBlockHeader() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(someBytes32())
        );

        vm.expectRevert(ICuratedVerifier.InvalidBlockHeader.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_NotSlashed() public {
        fixture.data.validator.object.slashed = false;

        vm.expectRevert(ICuratedVerifier.ValidatorIsNotSlashed.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_InvalidPublicKey() public {
        fixture.data.validator.object.pubkey = hex"deadbeef";

        vm.expectRevert(ICuratedVerifier.InvalidPublicKey.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_InvalidValidatorObject() public {
        fixture.data.validator.object.effectiveBalance += 1;

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processSlashedProof(fixture.data);
    }

    function test_processSlashedProof_RevertWhen_Paused() public {
        _pause();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processSlashedProof(fixture.data);
    }
}

contract CuratedVerifierBalanceProofTest is CuratedVerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        // The fixture shares the layout with `IVerifier.ProcessBalanceProofInput`.
        fixture = abi.decode(_runFixtureScript("test/fixtures/Verifier/balance.mjs", ""), (Fixture));

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(
            _gindices(GIndices.FIRST_VALIDATOR_ELECTRA, NULL_GINDEX, GIndices.FIRST_BALANCE_NODE_ELECTRA),
            slot.dec(),
            slot.dec()
        );

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

    function test_processBalanceProof_HappyPath() public {
        vm.expectCall(
            address(module),
            abi.encodeCall(
                IBaseModule.reportValidatorBalance,
                (fixture.data.validator.nodeOperatorId, fixture.data.validator.keyIndex, 64 ether)
            )
        );

        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_SlotUnsupported() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidBlockHeader() public {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.data.recentBlock.rootsTimestamp),
            abi.encode(someBytes32())
        );

        vm.expectRevert(ICuratedVerifier.InvalidBlockHeader.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidBalanceNode() public {
        fixture.data.balance.node = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_InvalidPublicKey() public {
        fixture.data.validator.object.pubkey = hex"deadbeef";

        vm.expectRevert(ICuratedVerifier.InvalidPublicKey.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_ValidatorIsWithdrawable() public {
        fixture.data.validator.object.withdrawableEpoch = fixture.data.recentBlock.header.slot.unwrap() / 32;

        vm.expectRevert(ICuratedVerifier.ValidatorIsWithdrawable.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_Paused() public {
        _pause();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processBalanceProof(fixture.data);
    }
}

contract CuratedVerifierHistoricalBalanceProofTest is CuratedVerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessHistoricalBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        // The fixture shares the layout with `IVerifier.ProcessHistoricalBalanceProofInput`.
        fixture = abi.decode(_runFixtureScript("test/fixtures/Verifier/historical_balance.mjs", "electra"), (Fixture));

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.historicalBlock.header.slot;
        _deployVerifier(
            _gindices(
                GIndices.FIRST_VALIDATOR_ELECTRA,
                GIndices.FIRST_HISTORICAL_SUMMARY_ELECTRA,
                GIndices.FIRST_BALANCE_NODE_ELECTRA
            ),
            slot,
            slot
        );

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

    function test_processHistoricalBalanceProof_HappyPath() public {
        vm.expectCall(
            address(module),
            abi.encodeCall(
                IBaseModule.reportValidatorBalance,
                (fixture.data.validator.nodeOperatorId, fixture.data.validator.keyIndex, 64 ether)
            )
        );

        verifier.processHistoricalBalanceProof(fixture.data);
    }

    function test_processHistoricalBalanceProof_RevertWhen_UnsupportedSlot_RecentBlock() public {
        fixture.data.recentBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.recentBlock.header.slot)
        );
        verifier.processHistoricalBalanceProof(fixture.data);
    }

    function test_processHistoricalBalanceProof_RevertWhen_UnsupportedSlot_HistoricalBlock() public {
        fixture.data.historicalBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.historicalBlock.header.slot)
        );
        verifier.processHistoricalBalanceProof(fixture.data);
    }

    function test_processHistoricalBalanceProof_RevertWhen_InvalidHistoricalBlock() public {
        fixture.data.historicalBlock.header.parentRoot = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processHistoricalBalanceProof(fixture.data);
    }

    function test_processHistoricalBalanceProof_RevertWhen_ValidatorIsWithdrawable() public {
        fixture.data.validator.object.withdrawableEpoch = fixture.data.historicalBlock.header.slot.unwrap() / 32;

        vm.expectRevert(ICuratedVerifier.ValidatorIsWithdrawable.selector);
        verifier.processHistoricalBalanceProof(fixture.data);
    }

    function test_processHistoricalBalanceProof_RevertWhen_Paused() public {
        _pause();

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        verifier.processHistoricalBalanceProof(fixture.data);
    }
}
