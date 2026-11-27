// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { CuratedVerifier } from "src/CuratedVerifier.sol";
import { GIndex } from "src/lib/GIndex.sol";
import { GIndices } from "src/lib/GIndices.sol";
import { Slot } from "src/lib/Types.sol";
import { SSZ } from "src/lib/SSZ.sol";
import { WCType, toWC } from "script/utils/WithdrawalCredentials.sol";

import { ICuratedVerifier } from "src/interfaces/ICuratedVerifier.sol";
import { IBaseModule, WithdrawnValidatorInfo } from "src/interfaces/IBaseModule.sol";

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

// The withdrawal address used by the fixtures.
address constant FIXTURE_WITHDRAWAL_ADDRESS = 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36;

contract CuratedVerifierTestBase is Test, Utilities {
    CuratedVerifier public verifier;
    Stub public module;
    address public admin;

    function _deployVerifier(bytes32 withdrawalCredentials, Slot firstSupportedSlot, Slot gloasSlot) internal {
        verifier = new CuratedVerifier({
            withdrawalCredentials: withdrawalCredentials,
            module: address(module),
            slotsPerEpoch: 32,
            firstSupportedSlot: firstSupportedSlot,
            gloasSlot: gloasSlot,
            capellaSlot: Slot.wrap(0),
            admin: admin
        });

        vm.startPrank(admin);
        verifier.grantRole(verifier.PAUSE_ROLE(), admin);
        verifier.grantRole(verifier.RESUME_ROLE(), admin);
        vm.stopPrank();
    }

    function _pause() internal {
        vm.prank(admin);
        verifier.pauseFor(1 days);
    }
}

contract CuratedVerifierConstructorTest is CuratedVerifierTestBase {
    function setUp() public {
        module = new Stub();
        admin = nextAddress("ADMIN");
    }

    function test_constructor_HappyPath() public {
        address withdrawalAddress = nextAddress("WITHDRAWAL_ADDRESS");
        bytes32 withdrawalCredentials = toWC(withdrawalAddress, WCType.Compounding);

        verifier = new CuratedVerifier({
            withdrawalCredentials: withdrawalCredentials,
            module: address(module),
            slotsPerEpoch: 32,
            firstSupportedSlot: Slot.wrap(100_500),
            gloasSlot: Slot.wrap(100_501),
            capellaSlot: Slot.wrap(8192),
            admin: admin
        });

        assertEq(verifier.WITHDRAWAL_CREDENTIALS(), withdrawalCredentials);
        assertEq(verifier.WITHDRAWAL_ADDRESS(), withdrawalAddress);
        assertEq(address(verifier.MODULE()), address(module));
        assertEq(verifier.SLOTS_PER_EPOCH(), 32);
        assertEq(verifier.SLOTS_PER_HISTORICAL_ROOT(), 8192);
        _assertEq(verifier.GI_VALIDATORS_PRE_GLOAS(), GIndices.VALIDATORS_ELECTRA);
        _assertEq(verifier.GI_VALIDATORS(), GIndices.VALIDATORS_GLOAS);
        _assertEq(verifier.GI_BALANCES_PRE_GLOAS(), GIndices.BALANCES_ELECTRA);
        _assertEq(verifier.GI_BALANCES(), GIndices.BALANCES_GLOAS);
        _assertEq(verifier.GI_BLOCK_ROOTS_PRE_GLOAS(), GIndices.BLOCK_ROOTS_ELECTRA);
        _assertEq(verifier.GI_BLOCK_ROOTS(), GIndices.BLOCK_ROOTS_GLOAS);
        _assertEq(verifier.GI_HISTORICAL_SUMMARIES_PRE_GLOAS(), GIndices.HISTORICAL_SUMMARIES_ELECTRA);
        _assertEq(verifier.GI_HISTORICAL_SUMMARIES(), GIndices.HISTORICAL_SUMMARIES_GLOAS);
        _assertEq(verifier.GI_BLOCK_ROOT_IN_SUMMARY(), GIndices.BLOCK_ROOT_IN_SUMMARY);
        assertEq(verifier.FIRST_SUPPORTED_SLOT().unwrap(), 100_500);
        assertEq(verifier.GLOAS_SLOT().unwrap(), 100_501);
        assertEq(verifier.CAPELLA_SLOT().unwrap(), 8192);
        assertTrue(verifier.hasRole(verifier.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_constructor_RevertWhen_InvalidChainConfig_SlotsPerEpoch() public {
        vm.expectRevert(ICuratedVerifier.InvalidChainConfig.selector);
        _newVerifier(someBytes32(), address(module), 0, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_InvalidGloasSlot() public {
        vm.expectRevert(ICuratedVerifier.InvalidGloasSlot.selector);
        _newVerifier(someBytes32(), address(module), 32, Slot.wrap(100), Slot.wrap(99), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_InvalidCapellaSlot() public {
        vm.expectRevert(ICuratedVerifier.InvalidCapellaSlot.selector);
        _newVerifier(someBytes32(), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(8192), admin);
    }

    function test_constructor_RevertWhen_UnalignedCapellaSlot() public {
        vm.expectRevert(ICuratedVerifier.InvalidCapellaSlot.selector);
        _newVerifier(someBytes32(), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(1), admin);
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(ICuratedVerifier.ZeroModuleAddress.selector);
        _newVerifier(someBytes32(), address(0), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_ZeroWithdrawalCredentials() public {
        vm.expectRevert(ICuratedVerifier.ZeroWithdrawalCredentials.selector);
        _newVerifier(bytes32(0), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), admin);
    }

    function test_constructor_RevertWhen_ZeroAdminAddress() public {
        vm.expectRevert(ICuratedVerifier.ZeroAdminAddress.selector);
        _newVerifier(someBytes32(), address(module), 32, Slot.wrap(100), Slot.wrap(100), Slot.wrap(0), address(0));
    }

    function _newVerifier(
        bytes32 withdrawalCredentials,
        address moduleAddress,
        uint64 slotsPerEpoch,
        Slot firstSupportedSlot,
        Slot gloasSlot,
        Slot capellaSlot,
        address adminAddress
    ) internal returns (CuratedVerifier) {
        return
            new CuratedVerifier({
                withdrawalCredentials: withdrawalCredentials,
                module: moduleAddress,
                slotsPerEpoch: slotsPerEpoch,
                firstSupportedSlot: firstSupportedSlot,
                gloasSlot: gloasSlot,
                capellaSlot: capellaSlot,
                admin: adminAddress
            });
    }

    function _assertEq(GIndex actual, GIndex expected) internal pure {
        assertEq(GIndex.unwrap(actual), GIndex.unwrap(expected));
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
        _loadFixture("gloas", EXITED_VALIDATOR);

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(toWC(FIXTURE_WITHDRAWAL_ADDRESS, WCType.Compounding), slot, slot);

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
        _loadFixture("gloas", CONSOLIDATED_VALIDATOR);
        _setMocks();

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_AtWithdrawableEpoch() public {
        _loadFixture("gloas", AT_WITHDRAWABLE_EPOCH_VALIDATOR);
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

    function test_processWithdrawnProof_HappyPath_ForkBeforeGloas() public {
        _loadFixture("electra", EXITED_VALIDATOR);
        _setMocks();

        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(toWC(FIXTURE_WITHDRAWAL_ADDRESS, WCType.Compounding), slot, slot.inc());

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_ForkAtGloas() public {
        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(toWC(FIXTURE_WITHDRAWAL_ADDRESS, WCType.Compounding), slot.dec(), slot);

        test_processWithdrawnProof_HappyPath();
    }

    function test_processWithdrawnProof_HappyPath_ForkAfterGloas() public {
        Slot slot = fixture.data.recentBlock.header.slot;
        _deployVerifier(toWC(FIXTURE_WITHDRAWAL_ADDRESS, WCType.Compounding), slot.dec(), slot.dec());

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

    function test_processWithdrawnProof_RevertWhen_InvalidWithdrawalCredentials() public {
        fixture.data.validator.object.withdrawalCredentials = someBytes32();

        vm.expectRevert(ICuratedVerifier.InvalidWithdrawalCredentials.selector);
        verifier.processWithdrawnProof(fixture.data);
    }

    function test_processWithdrawnProof_RevertWhen_InvalidWithdrawalCredentials_Eth1() public {
        fixture.data.validator.object.withdrawalCredentials = toWC(FIXTURE_WITHDRAWAL_ADDRESS, WCType.Eth1);

        vm.expectRevert(ICuratedVerifier.InvalidWithdrawalCredentials.selector);
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

    function test_processWithdrawnProof_RevertWhen_PreGloasProofAfterGloas() public {
        _loadFixture("electra", EXITED_VALIDATOR);
        _setMocks();

        // The Electra validators list proof is longer than the Gloas progressive list one.
        vm.expectRevert(SSZ.BranchHasExtraItem.selector);
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

    function _loadFixture(string memory fork, uint256 validator) internal {
        string[] memory cmd = new string[](5);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = "test/fixtures/CuratedVerifier/withdrawn.mjs";
        cmd[3] = fork;
        cmd[4] = vm.toString(validator);
        fixture = abi.decode(vm.ffi(cmd), (Fixture));
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
        _loadFixture();

        module = new Stub();
        admin = nextAddress("ADMIN");

        // The fixture is an Electra one, route through the pre-Gloas branch.
        _deployVerifier(someBytes32(), Slot.wrap(8192), fixture.data.recentBlock.header.slot.inc());

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

    function _loadFixture() internal {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        // The fixture shares the layout with `IVerifier.ProcessSlashedInput`.
        cmd[2] = "test/fixtures/Verifier/slashing.mjs";
        fixture = abi.decode(vm.ffi(cmd), (Fixture));
    }
}

contract CuratedVerifierBalanceProofTest is CuratedVerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture("gloas");

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.balanceBlock.header.slot;
        _deployVerifier(someBytes32(), slot.dec(), slot.dec());

        _setMocks();
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

    function test_processBalanceProof_HappyPath_ForkBeforeGloas() public {
        _loadFixture("electra");
        _deployVerifier(
            someBytes32(),
            fixture.data.balanceBlock.header.slot.dec(),
            fixture.data.recentBlock.header.slot.inc()
        );
        _setMocks();

        test_processBalanceProof_HappyPath();
    }

    function test_processBalanceProof_HappyPath_ForkAtGloas() public {
        Slot slot = fixture.data.balanceBlock.header.slot;
        _deployVerifier(someBytes32(), slot.dec(), slot);
        _setMocks();

        test_processBalanceProof_HappyPath();
    }

    function test_processBalanceProof_RevertWhen_UnsupportedSlot_BalanceBlock() public {
        fixture.data.balanceBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(ICuratedVerifier.UnsupportedSlot.selector, fixture.data.balanceBlock.header.slot)
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

    function test_processBalanceProof_RevertWhen_InvalidBalanceBlock() public {
        fixture.data.balanceBlock.header.parentRoot = someBytes32();

        vm.expectRevert(SSZ.InvalidProof.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_BlockRootNotInRange() public {
        _deployVerifier(someBytes32(), Slot.wrap(0), Slot.wrap(0));
        _setMocks();

        fixture.data.balanceBlock.header.slot = fixture.data.recentBlock.header.slot;
        vm.expectRevert(ICuratedVerifier.BlockRootNotInRange.selector);
        verifier.processBalanceProof(fixture.data);

        fixture.data.balanceBlock.header.slot = fixture.data.recentBlock.header.slot.inc();
        vm.expectRevert(ICuratedVerifier.BlockRootNotInRange.selector);
        verifier.processBalanceProof(fixture.data);

        fixture.data.balanceBlock.header.slot = Slot.wrap(fixture.data.recentBlock.header.slot.unwrap() - 8192 - 1);
        vm.expectRevert(ICuratedVerifier.BlockRootNotInRange.selector);
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
        fixture.data.validator.object.withdrawableEpoch = fixture.data.balanceBlock.header.slot.unwrap() / 32;

        vm.expectRevert(ICuratedVerifier.ValidatorIsWithdrawable.selector);
        verifier.processBalanceProof(fixture.data);
    }

    function test_processBalanceProof_RevertWhen_Paused() public {
        _pause();

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

    function _loadFixture(string memory fork) internal {
        string[] memory cmd = new string[](4);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        // The fixture shares the layout with `IVerifier.ProcessBalanceProofInput`.
        cmd[2] = "test/fixtures/Verifier/balance.mjs";
        cmd[3] = fork;
        fixture = abi.decode(vm.ffi(cmd), (Fixture));
    }
}

contract CuratedVerifierHistoricalBalanceProofTest is CuratedVerifierTestBase {
    struct Fixture {
        bytes32 blockRoot;
        ICuratedVerifier.ProcessHistoricalBalanceProofInput data;
    }

    Fixture internal fixture;

    function setUp() public {
        _loadFixture("gloas");

        module = new Stub();
        admin = nextAddress("ADMIN");

        Slot slot = fixture.data.historicalBlock.header.slot;
        _deployVerifier(someBytes32(), slot, slot);

        _setMocks();
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

    function test_processHistoricalBalanceProof_HappyPath_HistoricalBlockBeforeGloas() public {
        // The historical state is an Electra one, while the recent state is a Gloas one.
        _loadFixture("electra");
        _deployVerifier(someBytes32(), fixture.data.historicalBlock.header.slot, fixture.data.recentBlock.header.slot);
        _setMocks();

        test_processHistoricalBalanceProof_HappyPath();
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
        // The fixture shares the layout with `IVerifier.ProcessHistoricalBalanceProofInput`.
        cmd[2] = "test/fixtures/Verifier/historical_balance.mjs";
        cmd[3] = fork;
        fixture = abi.decode(vm.ffi(cmd), (Fixture));
    }
}
