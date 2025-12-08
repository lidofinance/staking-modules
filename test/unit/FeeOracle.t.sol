// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test, StdStorage, stdStorage } from "forge-std/Test.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { UnstructuredStorage } from "src/lib/UnstructuredStorage.sol";
import { HashConsensus } from "src/lib/base-oracle/HashConsensus.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { DistributorMock } from "../helpers/mocks/DistributorMock.sol";
import { ValidatorStrikesMock } from "../helpers/mocks/ValidatorStrikesMock.sol";
import { FeeOracle } from "src/FeeOracle.sol";
import { IFeeOracle } from "src/interfaces/IFeeOracle.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { InvariantAsserts } from "../helpers/InvariantAsserts.sol";

contract FeeOracleForTest is FeeOracle {
    using UnstructuredStorage for bytes32;

    constructor(
        address feeDistributor,
        address strikes,
        uint256 secondsPerSlot,
        uint256 genesisTime
    ) FeeOracle(feeDistributor, strikes, secondsPerSlot, genesisTime) {
        // Version.sol constructor sets the storage value to uint256.max and effectively
        // prevents the deployed contract from being initialized. To be able to use the
        // contract in tests with no proxy above, we need to set the version to 0.
        CONTRACT_VERSION_POSITION.setStorageUint256(0);
    }

    function mock_setContractVersion(uint256 version) external {
        CONTRACT_VERSION_POSITION.setStorageUint256(version);
    }
}

contract FeeOracleTest is Test, Utilities, InvariantAsserts {
    using stdStorage for StdStorage;
    using Strings for uint256;

    struct ChainConfig {
        uint256 secondsPerSlot;
        uint256 slotsPerEpoch;
        uint256 genesisTime;
    }

    address internal constant ORACLE_ADMIN =
        address(uint160(uint256(keccak256("ORACLE_ADMIN"))));

    uint256 internal constant CONSENSUS_VERSION = 1;
    uint256 internal constant INITIAL_EPOCH = 17;

    FeeOracleForTest public oracle;
    HashConsensus public consensus;
    ChainConfig public chainConfig;
    address[] public members;
    address public stranger;
    uint256 public quorum;
    DistributorMock public distributor;
    ValidatorStrikesMock public strikes;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        assertFeeOracleUnusedStorageSlots(oracle);
        vm.resumeGasMetering();
    }

    function setUp() public {
        chainConfig = ChainConfig({
            secondsPerSlot: 12,
            slotsPerEpoch: 32,
            genesisTime: 0
        });

        vm.label(ORACLE_ADMIN, "ORACLE_ADMIN");
        _vmSetEpoch(INITIAL_EPOCH);
        stranger = nextAddress();

        distributor = new DistributorMock(address(0));
        strikes = new ValidatorStrikesMock();
    }

    function test_getContractVersion() public {
        _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));

        assertEq(oracle.getContractVersion(), 2);
    }

    function test_happyPath() public assertInvariants {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
            _seedMembers(3);
        }

        uint256 startSlot;
        uint256 refSlot;

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        // INITIAL_EPOCH is far above the lastProcessingRefSlot's epoch
        assertNotEq(startSlot, refSlot);

        IFeeOracle.ReportData memory data = IFeeOracle.ReportData({
            consensusVersion: oracle.getConsensusVersion(),
            refSlot: refSlot,
            treeRoot: keccak256("root"),
            treeCid: someCIDv0(),
            logCid: someCIDv0(),
            distributed: 1337,
            rebate: 154,
            strikesTreeRoot: keccak256("strikesRoot"),
            strikesTreeCid: someCIDv0()
        });

        bytes32 reportHash = keccak256(abi.encode(data));
        _reachConsensus(refSlot, reportHash);

        vm.prank(members[0]);
        oracle.submitReportData({ data: data, contractVersion: 2 });

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertEq(startSlot, refSlot);

        // Advance block.timestamp to the middle of the frame
        _vmSetEpoch(INITIAL_EPOCH + _epochsInDays(14));
        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertEq(startSlot, refSlot);

        // Advance block.timestamp to the end of the frame
        _vmSetEpoch(INITIAL_EPOCH + _epochsInDays(28));
        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertLt(startSlot, refSlot);
    }

    function test_submitReportData_RevertWhen_InvalidReportSender()
        public
        assertInvariants
    {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
            _seedMembers(3);
        }

        uint256 startSlot;
        uint256 refSlot;

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        // INITIAL_EPOCH is far above the lastProcessingRefSlot's epoch
        assertNotEq(startSlot, refSlot);

        IFeeOracle.ReportData memory data = IFeeOracle.ReportData({
            consensusVersion: oracle.getConsensusVersion(),
            refSlot: refSlot,
            treeRoot: keccak256("root"),
            treeCid: someCIDv0(),
            logCid: someCIDv0(),
            distributed: 1337,
            rebate: 154,
            strikesTreeRoot: keccak256("strikesRoot"),
            strikesTreeCid: someCIDv0()
        });

        bytes32 reportHash = keccak256(abi.encode(data));
        _reachConsensus(refSlot, reportHash);

        vm.expectRevert(IFeeOracle.SenderNotAllowed.selector);
        vm.prank(stranger);
        oracle.submitReportData({ data: data, contractVersion: 2 });
    }

    function test_submitReport_RevertWhen_PausedFor() public assertInvariants {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
            _seedMembers(3);
        }

        vm.prank(ORACLE_ADMIN);
        oracle.pauseFor(1000);

        uint256 startSlot;
        uint256 refSlot;

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        // INITIAL_EPOCH is far above the lastProcessingRefSlot's epoch
        assertNotEq(startSlot, refSlot);

        IFeeOracle.ReportData memory data = IFeeOracle.ReportData({
            consensusVersion: oracle.getConsensusVersion(),
            refSlot: refSlot,
            treeRoot: keccak256("root"),
            treeCid: someCIDv0(),
            logCid: someCIDv0(),
            distributed: 1337,
            rebate: 154,
            strikesTreeRoot: keccak256("strikesRoot"),
            strikesTreeCid: someCIDv0()
        });

        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        vm.prank(members[0]);
        oracle.submitReportData({ data: data, contractVersion: 2 });
    }

    function test_happyPath_whenResumed() public assertInvariants {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
            _seedMembers(3);
        }

        vm.startPrank(ORACLE_ADMIN);
        oracle.pauseFor(1000);
        oracle.resume();
        vm.stopPrank();

        uint256 startSlot;
        uint256 refSlot;

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        // INITIAL_EPOCH is far above the lastProcessingRefSlot's epoch
        assertNotEq(startSlot, refSlot);

        IFeeOracle.ReportData memory data = IFeeOracle.ReportData({
            consensusVersion: oracle.getConsensusVersion(),
            refSlot: refSlot,
            treeRoot: keccak256("root"),
            treeCid: someCIDv0(),
            logCid: someCIDv0(),
            distributed: 1337,
            rebate: 154,
            strikesTreeRoot: keccak256("strikesRoot"),
            strikesTreeCid: someCIDv0()
        });

        bytes32 reportHash = keccak256(abi.encode(data));
        _reachConsensus(refSlot, reportHash);

        vm.prank(members[0]);
        oracle.submitReportData({ data: data, contractVersion: 2 });

        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertEq(startSlot, refSlot);

        // Advance block.timestamp to the middle of the frame
        _vmSetEpoch(INITIAL_EPOCH + _epochsInDays(14));
        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertEq(startSlot, refSlot);

        // Advance block.timestamp to the end of the frame
        _vmSetEpoch(INITIAL_EPOCH + _epochsInDays(28));
        (, startSlot, , ) = oracle.getConsensusReport();
        (refSlot, ) = consensus.getCurrentFrame();
        assertLt(startSlot, refSlot);
    }

    function test_resumeWhenNotPaused() public assertInvariants {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(1));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
            _seedMembers(3);
        }

        vm.expectRevert(PausableUntil.PausedExpected.selector);
        vm.prank(ORACLE_ADMIN);
        oracle.resume();
    }

    function test_constructor() public assertInvariants {
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });

        assertEq(address(oracle.FEE_DISTRIBUTOR()), address(distributor));
        assertEq(address(oracle.STRIKES()), address(strikes));
    }

    function test_constructor_revertWhen_ZeroFeeDistributorAddress() public {
        vm.expectRevert(IFeeOracle.ZeroFeeDistributorAddress.selector);
        oracle = new FeeOracleForTest({
            feeDistributor: address(0),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });
    }

    function test_constructor_revertWhen_ZeroStrikesAddress() public {
        vm.expectRevert(IFeeOracle.ZeroStrikesAddress.selector);
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(0),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });
    }

    function test_initialize() public assertInvariants {
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });

        consensus = new HashConsensus({
            slotsPerEpoch: chainConfig.slotsPerEpoch,
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime,
            epochsPerFrame: _epochsInDays(28),
            fastLaneLengthSlots: 0,
            admin: ORACLE_ADMIN,
            reportProcessor: address(oracle)
        });

        oracle.initialize(address(this), address(consensus), CONSENSUS_VERSION);

        vm.assertTrue(
            oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), address(this))
        );
        assertEq(oracle.getContractVersion(), 2);
    }

    function test_initialize_RevertWhen_AdminCannotBeZero() public {
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });

        consensus = new HashConsensus({
            slotsPerEpoch: chainConfig.slotsPerEpoch,
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime,
            epochsPerFrame: _epochsInDays(28),
            fastLaneLengthSlots: 0,
            admin: ORACLE_ADMIN,
            reportProcessor: address(oracle)
        });

        vm.expectRevert(IFeeOracle.ZeroAdminAddress.selector);
        oracle.initialize(address(0), address(consensus), CONSENSUS_VERSION);
    }

    function test_finalizeUpgradeV2() public assertInvariants {
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });
        oracle.mock_setContractVersion(1);

        oracle.finalizeUpgradeV2(CONSENSUS_VERSION);
        assertEq(oracle.getContractVersion(), 2);
    }

    function test_recovererRole() public assertInvariants {
        {
            _deployFeeOracleAndHashConsensus(_lastSlotOfEpoch(INITIAL_EPOCH));
            _grantAllRolesToAdmin();
            _assertNoReportOnInit();
            _setInitialEpoch();
        }
        bytes32 role = oracle.RECOVERER_ROLE();
        vm.prank(ORACLE_ADMIN);
        oracle.grantRole(role, address(1337));

        vm.prank(address(1337));
        oracle.recoverEther();
    }

    function _deployFeeOracleAndHashConsensus(
        uint256 /* lastProcessingRefSlot */
    ) internal {
        oracle = new FeeOracleForTest({
            feeDistributor: address(distributor),
            strikes: address(strikes),
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime
        });

        consensus = new HashConsensus({
            slotsPerEpoch: chainConfig.slotsPerEpoch,
            secondsPerSlot: chainConfig.secondsPerSlot,
            genesisTime: chainConfig.genesisTime,
            epochsPerFrame: _epochsInDays(28),
            fastLaneLengthSlots: 0,
            admin: ORACLE_ADMIN,
            reportProcessor: address(oracle)
        });

        oracle.initialize(ORACLE_ADMIN, address(consensus), CONSENSUS_VERSION);
    }

    function _grantAllRolesToAdmin() internal {
        vm.startPrank(ORACLE_ADMIN);
        /* prettier-ignore */
        {
            consensus.grantRole(consensus.MANAGE_MEMBERS_AND_QUORUM_ROLE(), ORACLE_ADMIN);
            consensus.grantRole(consensus.DISABLE_CONSENSUS_ROLE(), ORACLE_ADMIN);
            consensus.grantRole(consensus.MANAGE_FRAME_CONFIG_ROLE(), ORACLE_ADMIN);
            consensus.grantRole(consensus.MANAGE_FAST_LANE_CONFIG_ROLE(), ORACLE_ADMIN);
            consensus.grantRole(consensus.MANAGE_REPORT_PROCESSOR_ROLE(), ORACLE_ADMIN);

            oracle.grantRole(oracle.MANAGE_CONSENSUS_CONTRACT_ROLE(), ORACLE_ADMIN);
            oracle.grantRole(oracle.MANAGE_CONSENSUS_VERSION_ROLE(), ORACLE_ADMIN);
            oracle.grantRole(oracle.PAUSE_ROLE(), ORACLE_ADMIN);
            oracle.grantRole(oracle.RESUME_ROLE(), ORACLE_ADMIN);
        }
        vm.stopPrank();
    }

    function _seedMembers(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            uint256 q = (members.length + 1) / 2 + 1; // 50% + 1
            address newMember = nextAddress();
            vm.label(newMember, string.concat("MEMBER", i.toString()));
            vm.startPrank(ORACLE_ADMIN);
            {
                consensus.addMember(newMember, q);
                oracle.grantRole(oracle.SUBMIT_DATA_ROLE(), newMember);
            }
            vm.stopPrank();
            members.push(newMember);
            quorum = q;
        }
    }

    function _assertNoReportOnInit() internal view {
        (
            bytes32 hash, // refSlot
            ,
            uint256 processingDeadlineTime,
            bool processingStarted
        ) = oracle.getConsensusReport();

        // Skips the check for refSlot, see test_reportFrame
        assertEq(hash, bytes32(0));
        assertEq(processingDeadlineTime, 0);
        assertEq(processingStarted, false);
    }

    function _setInitialEpoch() internal {
        vm.prank(ORACLE_ADMIN);
        consensus.updateInitialEpoch(INITIAL_EPOCH);
    }

    function _reachConsensus(uint256 refSlot, bytes32 hash) internal {
        for (uint256 i; i < quorum; i++) {
            vm.expectEmit(address(consensus));
            emit HashConsensus.ReportReceived(refSlot, members[i], hash);

            vm.prank(members[i]);
            consensus.submitReport(refSlot, hash, CONSENSUS_VERSION);
        }

        (uint256 _refSlot, bytes32 _hash, ) = consensus.getConsensusState();
        assertEq(_refSlot, refSlot, "_reachConsensus: refSlot mismatch");
        assertEq(_hash, hash, "_reachConsensus: hash mismatch");
    }

    function _epochsInDays(uint256 daysCount) internal view returns (uint256) {
        return
            (daysCount * 24 * 60 * 60) /
            chainConfig.secondsPerSlot /
            chainConfig.slotsPerEpoch;
    }

    function _lastSlotOfEpoch(uint256 epoch) internal pure returns (uint256) {
        require(epoch > 0, "epoch must be greater than 0");
        return epoch * 32 - 1;
    }

    function _vmSetEpoch(uint256 epoch) internal {
        /* prettier-ignore */
        vm.warp(
            epoch *
            chainConfig.secondsPerSlot *
            chainConfig.slotsPerEpoch
        );
    }
}
