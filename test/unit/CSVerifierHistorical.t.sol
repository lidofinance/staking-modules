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

contract CSVerifierHistoricalTest is Test, Utilities {
    using stdJson for string;

    struct HistoricalWithdrawalFixture {
        bytes32 _blockRoot;
        bytes _pubkey;
        ICSVerifier.RecentHeaderWitness beaconBlock;
        ICSVerifier.HistoricalHeaderWitness oldBlock;
        ICSVerifier.WithdrawalWitness witness;
    }

    CSVerifier public verifier;
    Stub public module;
    address public admin;

    bytes32 public pauseRole;
    bytes32 public resumeRole;

    HistoricalWithdrawalFixture public fixture;

    function setUp() public {
        _loadFixture();
        module = new Stub();
        admin = nextAddress("ADMIN");
        verifier = new CSVerifier({
            withdrawalAddress: 0xb3E29C46Ee1745724417C0C51Eb2351A1C01cF36,
            module: address(module),
            slotsPerEpoch: 32,
            slotsPerHistoricalRoot: 8192,
            gindices: ICSVerifier.GIndices({
                gIFirstWithdrawalPrev: pack(0x161c0, 4),
                gIFirstWithdrawalCurr: pack(0x161c0, 4),
                gIFirstValidatorPrev: pack(0x960000000000, 40),
                gIFirstValidatorCurr: pack(0x960000000000, 40),
                gIFirstHistoricalSummaryPrev: pack(0xb6000000, 24),
                gIFirstHistoricalSummaryCurr: pack(0xb6000000, 24),
                gIFirstBlockRootInSummaryPrev: pack(0x4000, 13),
                gIFirstBlockRootInSummaryCurr: pack(0x4000, 13),
                gIFirstBalanceNodePrev: pack(0x260000000000, 40),
                gIFirstBalanceNodeCurr: pack(0x260000000000, 40),
                gIFirstPendingConsolidationPrev: pack(0x3200000, 18),
                gIFirstPendingConsolidationCurr: pack(0x3200000, 18)
            }),
            firstSupportedSlot: fixture.oldBlock.header.slot,
            pivotSlot: fixture.oldBlock.header.slot,
            capellaSlot: fixture.oldBlock.header.slot,
            admin: admin
        });

        pauseRole = verifier.PAUSE_ROLE();
        resumeRole = verifier.RESUME_ROLE();

        vm.startPrank(admin);
        verifier.grantRole(pauseRole, admin);
        verifier.grantRole(resumeRole, admin);
        vm.stopPrank();
    }

    function _loadFixture() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/test/fixtures/CSVerifier/historicalWithdrawal.json"
        );
        string memory json = vm.readFile(path);
        bytes memory data = json.parseRaw("$");
        fixture = abi.decode(data, (HistoricalWithdrawalFixture));
    }

    function test_processWithdrawalProof_HappyPath() public {
        _setMocksWithdrawal(fixture);

        ValidatorWithdrawalInfo[]
            memory withdrawals = new ValidatorWithdrawalInfo[](1);
        withdrawals[0] = ValidatorWithdrawalInfo({
            nodeOperatorId: 0,
            keyIndex: 0,
            exitBalance: uint256(fixture.witness.amount) * 1e9,
            slashingPenalty: 0
        });

        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.submitWithdrawals.selector,
                withdrawals
            )
        );

        // solhint-disable-next-line func-named-parameters
        verifier.processHistoricalWithdrawalProof(
            fixture.beaconBlock,
            fixture.oldBlock,
            fixture.witness,
            0,
            0
        );
    }

    function test_processHistoricalWithdrawalProof_RevertWhen_ValidatorSlashed()
        public
    {
        fixture.witness.slashed = true;
        _setMocksWithdrawal(fixture);

        vm.expectRevert(ICSVerifier.ValidatorIsSlashed.selector);
        verifier.processHistoricalWithdrawalProof(
            fixture.beaconBlock,
            fixture.oldBlock,
            fixture.witness,
            0,
            0
        );
    }

    function test_processWithdrawalProof_RevertWhen_UnsupportedSlot() public {
        fixture.beaconBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();
        fixture.oldBlock.header.slot = fixture.beaconBlock.header.slot.dec();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICSVerifier.UnsupportedSlot.selector,
                fixture.beaconBlock.header.slot
            )
        );

        // solhint-disable-next-line func-named-parameters
        verifier.processHistoricalWithdrawalProof(
            fixture.beaconBlock,
            fixture.oldBlock,
            fixture.witness,
            0,
            0
        );
    }

    function test_processWithdrawalProof_RevertWhen_UnsupportedSlot_OldBlock()
        public
    {
        fixture.oldBlock.header.slot = verifier.FIRST_SUPPORTED_SLOT().dec();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICSVerifier.UnsupportedSlot.selector,
                fixture.oldBlock.header.slot
            )
        );

        // solhint-disable-next-line func-named-parameters
        verifier.processHistoricalWithdrawalProof(
            fixture.beaconBlock,
            fixture.oldBlock,
            fixture.witness,
            0,
            0
        );
    }

    function test_processWithdrawalProof_RevertWhen_InvalidBlockHeader()
        public
    {
        _setMocksWithdrawal(fixture);

        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(fixture.beaconBlock.rootsTimestamp),
            abi.encode("lol")
        );

        vm.expectRevert(ICSVerifier.InvalidBlockHeader.selector);
        // solhint-disable-next-line func-named-parameters
        verifier.processHistoricalWithdrawalProof(
            fixture.beaconBlock,
            fixture.oldBlock,
            fixture.witness,
            0,
            0
        );
    }

    function _setMocksWithdrawal(
        HistoricalWithdrawalFixture memory _fixture
    ) internal {
        vm.mockCall(
            verifier.BEACON_ROOTS(),
            abi.encode(_fixture.beaconBlock.rootsTimestamp),
            abi.encode(_fixture._blockRoot)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(ICSModule.getSigningKeys.selector, 0, 0),
            abi.encode(_fixture._pubkey)
        );

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(ICSModule.submitWithdrawals.selector),
            ""
        );
    }
}
