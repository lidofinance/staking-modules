// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test, StdStorage, Vm, stdStorage } from "forge-std/Test.sol";

import { FeeDistributor } from "src/FeeDistributor.sol";
import { IAssetRecovererLib } from "src/lib/AssetRecovererLib.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IFeeDistributor } from "src/interfaces/IFeeDistributor.sol";

import { Fixtures } from "../helpers/Fixtures.sol";
import { MerkleTree } from "../helpers/MerkleTree.sol";
import { StETHMock } from "../helpers/mocks/StETHMock.sol";
import { Stub } from "../helpers/mocks/Stub.sol";
import { ERC20Testable } from "../helpers/ERCTestable.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { InvariantAsserts } from "../helpers/InvariantAsserts.sol";

using stdStorage for StdStorage;

contract FeeDistributorTestBase is Test, Fixtures, Utilities, InvariantAsserts {
    StETHMock internal stETH;

    address internal stranger;
    address internal oracle;
    address internal rebateRecipient;
    FeeDistributor internal feeDistributor;
    Stub internal csm;
    Stub internal accounting;
    MerkleTree internal tree;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        assertFeeDistributorClaimableShares(stETH, feeDistributor);
        assertFeeDistributorTree(feeDistributor);
        vm.resumeGasMetering();
    }
}

contract FeeDistributorConstructorTest is FeeDistributorTestBase {
    function setUp() public {
        stranger = nextAddress("STRANGER");
        oracle = nextAddress("ORACLE");
        rebateRecipient = nextAddress("REBATE_RECIPIENT");
        csm = new Stub();
        accounting = new Stub();

        (, , stETH, , ) = initLido();
    }

    function test_constructor_happyPath() public {
        feeDistributor = new FeeDistributor(
            address(stETH),
            address(accounting),
            oracle
        );

        assertEq(feeDistributor.ACCOUNTING(), address(accounting));
        assertEq(address(feeDistributor.STETH()), address(stETH));
        assertEq(feeDistributor.ORACLE(), oracle);
    }

    function test_constructor_RevertWhen_InitOnImpl() public {
        feeDistributor = new FeeDistributor(
            address(stETH),
            address(accounting),
            oracle
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeDistributor.initialize(address(this), rebateRecipient);
    }

    function test_constructor_RevertWhen_ZeroAccountingAddress() public {
        vm.expectRevert(IFeeDistributor.ZeroAccountingAddress.selector);
        new FeeDistributor(address(stETH), address(0), oracle);
    }

    function test_constructor_RevertWhen_ZeroStEthAddress() public {
        vm.expectRevert(IFeeDistributor.ZeroStEthAddress.selector);
        new FeeDistributor(address(0), address(accounting), oracle);
    }

    function test_constructor_RevertWhen_ZeroOracleAddress() public {
        vm.expectRevert(IFeeDistributor.ZeroOracleAddress.selector);
        new FeeDistributor(address(stETH), address(accounting), address(0));
    }
}

contract FeeDistributorInitTest is FeeDistributorTestBase {
    function setUp() public {
        stranger = nextAddress("STRANGER");
        oracle = nextAddress("ORACLE");
        rebateRecipient = nextAddress("REBATE_RECIPIENT");
        csm = new Stub();
        accounting = new Stub();

        (, , stETH, , ) = initLido();

        feeDistributor = new FeeDistributor(
            address(stETH),
            address(accounting),
            oracle
        );
    }

    function test_initialize() public {
        _enableInitializers(address(feeDistributor));

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.RebateRecipientSet(rebateRecipient);
        feeDistributor.initialize(address(this), rebateRecipient);

        vm.assertTrue(
            feeDistributor.hasRole(
                feeDistributor.DEFAULT_ADMIN_ROLE(),
                address(this)
            )
        );
        assertEq(feeDistributor.rebateRecipient(), rebateRecipient);
        assertEq(feeDistributor.getInitializedVersion(), 2);
    }

    function test_initialize_RevertWhen_zeroAdmin() public {
        _enableInitializers(address(feeDistributor));

        vm.expectRevert(IFeeDistributor.ZeroAdminAddress.selector);
        feeDistributor.initialize(address(0), rebateRecipient);
    }

    function test_initialize_RevertWhen_zeroRebateRecipient() public {
        _enableInitializers(address(feeDistributor));

        vm.expectRevert(IFeeDistributor.ZeroRebateRecipientAddress.selector);
        feeDistributor.initialize(address(this), address(0));
    }

    function test_initialize_RevertWhen_calledTwice() public {
        _enableInitializers(address(feeDistributor));
        feeDistributor.initialize(address(this), rebateRecipient);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeDistributor.initialize(address(this), rebateRecipient);
    }

    function test_finalizeUpgradeV2() public {
        _enableInitializers(address(feeDistributor));

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.RebateRecipientSet(rebateRecipient);
        feeDistributor.finalizeUpgradeV2(rebateRecipient);

        assertEq(feeDistributor.rebateRecipient(), rebateRecipient);
        assertEq(feeDistributor.getInitializedVersion(), 2);
    }

    function test_finalizeUpgradeV2_RevertWhen_zeroRebateRecipient() public {
        _enableInitializers(address(feeDistributor));

        vm.expectRevert(IFeeDistributor.ZeroRebateRecipientAddress.selector);
        feeDistributor.finalizeUpgradeV2(address(0));
    }

    function test_finalizeUpgradeV2_RevertWhen_calledTwice() public {
        _enableInitializers(address(feeDistributor));
        feeDistributor.finalizeUpgradeV2(rebateRecipient);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        feeDistributor.finalizeUpgradeV2(rebateRecipient);
    }
}

contract FeeDistributorTest is FeeDistributorTestBase {
    function setUp() public {
        stranger = nextAddress("STRANGER");
        oracle = nextAddress("ORACLE");
        rebateRecipient = nextAddress("REBATE_RECIPIENT");
        csm = new Stub();
        accounting = new Stub();

        (, , stETH, , ) = initLido();

        feeDistributor = new FeeDistributor(
            address(stETH),
            address(accounting),
            oracle
        );

        _enableInitializers(address(feeDistributor));
        feeDistributor.initialize(address(this), rebateRecipient);

        tree = new MerkleTree();

        vm.label(address(accounting), "ACCOUNTING");
        vm.label(address(stETH), "STETH");
        vm.label(address(csm), "CSM");
    }

    function test_getInitializedVersion() public view {
        assertEq(feeDistributor.getInitializedVersion(), 2);
    }

    function test_distributeFeesHappyPath() public assertInvariants {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.OperatorFeeDistributed(nodeOperatorId, shares);

        vm.prank(address(accounting));
        uint256 returned = feeDistributor.distributeFees({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });

        assertEq(returned, shares);
        assertEq(stETH.sharesOf(address(accounting)), shares);
        assertEq(feeDistributor.distributedShares(nodeOperatorId), shares);
        assertEq(feeDistributor.totalClaimableShares(), 0);
        assertEq(feeDistributor.pendingSharesToDistribute(), 0);
    }

    function test_getFeesToDistribute_notDistributedYet()
        public
        assertInvariants
    {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        uint256 sharesToDistribute = feeDistributor.getFeesToDistribute({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });

        assertEq(sharesToDistribute, shares);
    }

    function test_getFeesToDistribute_alreadyDistributed()
        public
        assertInvariants
    {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        vm.prank(address(accounting));
        feeDistributor.distributeFees({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });

        uint256 sharesToDistribute = feeDistributor.getFeesToDistribute({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });

        assertEq(sharesToDistribute, 0);
    }

    function test_getFeesToDistribute_RevertWhenEmptyProof() public {
        uint256 shares = 1337;
        uint256 noId = 42;

        // Put a vulnerable `treeRoot` to make sure we provided the valid, but empty proof.
        stdstore
            .target(address(feeDistributor))
            .sig("treeRoot()")
            .checked_write(feeDistributor.hashLeaf(noId, shares));

        vm.expectRevert(IFeeDistributor.InvalidProof.selector);
        feeDistributor.getFeesToDistribute({
            proof: new bytes32[](0),
            nodeOperatorId: noId,
            cumulativeFeeShares: shares
        });
    }

    function test_getFeesToDistribute_RevertWhen_InvalidProofContents() public {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        // tamper the proof leaf by changing cumulativeFeeShares
        vm.expectRevert(IFeeDistributor.InvalidProof.selector);
        feeDistributor.getFeesToDistribute({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares + 1
        });
    }

    function test_getHistoricalDistributionData() public {
        uint256 shares = 100;
        uint256 rebate = 10;
        uint256 refSlot = 154;
        bytes32 root = someBytes32();
        string memory treeCid = someCIDv0();
        string memory logCid = someCIDv0();

        stETH.mintShares(address(feeDistributor), shares + rebate);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        IFeeDistributor.DistributionData memory data = feeDistributor
            .getHistoricalDistributionData(0);

        assertEq(data.refSlot, refSlot);
        assertEq(data.treeRoot, root);
        assertEq(data.treeCid, treeCid);
        assertEq(data.logCid, logCid);
        assertEq(data.distributed, shares);
        assertEq(data.rebate, rebate);
    }

    function test_getHistoricalDistributionData_multipleRecords() public {
        uint256 shares = 100;
        uint256 rebate = 0;
        uint256 refSlot = 154;
        bytes32 root = someBytes32();
        string memory treeCid = someCIDv0();
        string memory logCid = someCIDv0();
        stETH.mintShares(address(feeDistributor), shares + rebate);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        uint256 initialHistoryLength = feeDistributor
            .distributionDataHistoryCount();

        shares = 120;
        rebate = 10;
        refSlot = 155;
        root = someBytes32();
        treeCid = someCIDv0();
        logCid = someCIDv0();

        stETH.mintShares(address(feeDistributor), shares + rebate);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        uint256 historyLength = feeDistributor.distributionDataHistoryCount();
        assertEq(historyLength, initialHistoryLength + 1);

        IFeeDistributor.DistributionData memory data = feeDistributor
            .getHistoricalDistributionData(historyLength - 1);

        assertEq(data.refSlot, refSlot);
        assertEq(data.treeRoot, root);
        assertEq(data.treeCid, treeCid);
        assertEq(data.logCid, logCid);
        assertEq(data.distributed, shares);
        assertEq(data.rebate, rebate);

        // previous record remains intact
        data = feeDistributor.getHistoricalDistributionData(historyLength - 2);
        assertEq(data.refSlot, 154);
    }

    function test_hashLeaf() public assertInvariants {
        //  keccak256(bytes.concat(keccak256(abi.encode(1, 1000)))) == 0xe2ad525aaaf1fb7709959cc06e210437a97f34a5833e3a5c90d2099c5373116a
        assertEq(
            feeDistributor.hashLeaf(1, 1000),
            0xe2ad525aaaf1fb7709959cc06e210437a97f34a5833e3a5c90d2099c5373116a
        );
    }

    function test_distributeFees_RevertWhen_NotAccounting()
        public
        assertInvariants
    {
        vm.expectRevert(IFeeDistributor.SenderIsNotAccounting.selector);

        feeDistributor.distributeFees({
            proof: new bytes32[](1),
            nodeOperatorId: 0,
            cumulativeFeeShares: 0
        });
    }

    function test_distributeFees_RevertWhen_InvalidProof()
        public
        assertInvariants
    {
        vm.expectRevert(IFeeDistributor.InvalidProof.selector);

        vm.prank(address(accounting));
        feeDistributor.distributeFees({
            proof: new bytes32[](1),
            nodeOperatorId: 0,
            cumulativeFeeShares: 0
        });
    }

    function test_distributeFees_RevertWhen_InvalidShares()
        public
        assertInvariants
    {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        stdstore
            .target(address(feeDistributor))
            .sig("distributedShares(uint256)")
            .with_key(nodeOperatorId)
            .checked_write(shares + 99);

        vm.expectRevert(IFeeDistributor.FeeSharesDecrease.selector);
        vm.prank(address(accounting));
        feeDistributor.distributeFees({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });
    }

    function test_distributeFees_RevertWhen_NotEnoughShares()
        public
        assertInvariants
    {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares - 1);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares - 1,
            0,
            refSlot
        );

        vm.expectRevert(IFeeDistributor.NotEnoughShares.selector);
        vm.prank(address(accounting));
        feeDistributor.distributeFees({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });
    }

    function test_distributeFees_Returns0If_NothingToDistribute()
        public
        assertInvariants
    {
        uint256 nodeOperatorId = 42;
        uint256 shares = 100;
        uint256 refSlot = 154;
        tree.pushLeaf(abi.encode(nodeOperatorId, shares));
        tree.pushLeaf(abi.encode(type(uint64).max, 0));
        bytes32[] memory proof = tree.getProof(0);
        bytes32 root = tree.root();

        stETH.mintShares(address(feeDistributor), shares);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );

        stdstore
            .target(address(feeDistributor))
            .sig("distributedShares(uint256)")
            .with_key(nodeOperatorId)
            .checked_write(shares);

        vm.recordLogs();
        vm.prank(address(accounting));
        uint256 sharesToDistribute = feeDistributor.distributeFees({
            proof: proof,
            nodeOperatorId: nodeOperatorId,
            cumulativeFeeShares: shares
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // could be changed after resolving https://github.com/foundry-rs/foundry/issues/509
        assertEq(sharesToDistribute, 0);
    }

    function test_pendingSharesToDistribute() public assertInvariants {
        uint256 totalShares = 1000;
        uint256 refSlot = 154;
        stETH.mintShares(address(feeDistributor), totalShares);

        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            899,
            0,
            refSlot
        );

        assertEq(feeDistributor.pendingSharesToDistribute(), 101);
    }

    function test_processOracleReport_HappyPath() public assertInvariants {
        uint256 shares = 100;
        uint256 rebate = 10;
        uint256 refSlot = 154;
        stETH.mintShares(address(feeDistributor), shares + rebate);

        string memory treeCid = someCIDv0();
        string memory logCid = someCIDv0();
        bytes32 treeRoot = someBytes32();

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.DistributionDataUpdated(shares, treeRoot, treeCid);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.ModuleFeeDistributed(shares);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.RebateTransferred(rebate);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.DistributionLogUpdated(logCid);

        vm.prank(oracle);
        feeDistributor.processOracleReport(
            treeRoot,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        assertEq(feeDistributor.treeRoot(), treeRoot);
        assertEq(feeDistributor.treeCid(), treeCid);
        assertEq(feeDistributor.logCid(), logCid);
        assertEq(feeDistributor.pendingSharesToDistribute(), 0);
        assertEq(feeDistributor.totalClaimableShares(), shares);
        assertEq(stETH.sharesOf(rebateRecipient), rebate);
        assertEq(stETH.sharesOf(address(feeDistributor)), shares);
    }

    function test_processOracleReport_ZeroRebate() public assertInvariants {
        uint256 shares = 100;
        uint256 rebate = 0;
        uint256 refSlot = 154;
        stETH.mintShares(address(feeDistributor), shares + rebate);

        string memory treeCid = someCIDv0();
        string memory logCid = someCIDv0();
        bytes32 treeRoot = someBytes32();

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.DistributionDataUpdated(shares, treeRoot, treeCid);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.ModuleFeeDistributed(shares);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.DistributionLogUpdated(logCid);

        vm.recordLogs();
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            treeRoot,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3);

        assertEq(feeDistributor.treeRoot(), treeRoot);
        assertEq(feeDistributor.treeCid(), treeCid);
        assertEq(feeDistributor.logCid(), logCid);
        assertEq(feeDistributor.pendingSharesToDistribute(), 0);
        assertEq(feeDistributor.totalClaimableShares(), shares);
        assertEq(stETH.sharesOf(rebateRecipient), rebate);
        assertEq(stETH.sharesOf(address(feeDistributor)), shares);
    }

    function test_processOracleReport_ZeroDistributedAndRebate()
        public
        assertInvariants
    {
        uint256 shares = 0;
        uint256 rebate = 0;
        uint256 refSlot = 154;

        string memory treeCid = someCIDv0();
        string memory logCid = someCIDv0();
        bytes32 treeRoot = someBytes32();

        string memory treeCidOld = feeDistributor.treeCid();
        bytes32 treeRootOld = feeDistributor.treeRoot();

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.ModuleFeeDistributed(0);

        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.DistributionLogUpdated(logCid);

        vm.recordLogs();
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            treeRoot,
            treeCid,
            logCid,
            shares,
            rebate,
            refSlot
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        IFeeDistributor.DistributionData memory last = feeDistributor
            .getHistoricalDistributionData(
                feeDistributor.distributionDataHistoryCount() - 1
            );
        assertEq(last.treeRoot, treeRootOld);
        assertEq(last.treeCid, treeCidOld);
        assertEq(last.logCid, logCid);
        assertEq(last.distributed, shares);
        assertEq(last.rebate, rebate);
        assertEq(last.refSlot, refSlot);

        assertEq(feeDistributor.treeRoot(), treeRootOld);
        assertEq(feeDistributor.treeCid(), treeCidOld);
        assertEq(feeDistributor.logCid(), logCid);
        assertEq(feeDistributor.pendingSharesToDistribute(), 0);
        assertEq(feeDistributor.totalClaimableShares(), shares);
        assertEq(stETH.sharesOf(rebateRecipient), rebate);
        assertEq(stETH.sharesOf(address(feeDistributor)), shares);
    }

    function test_processOracleReport_EmptyInitialReport() public {
        string memory logCid = someCIDv0();
        uint256 refSlot = 154;

        vm.prank(oracle);
        feeDistributor.processOracleReport(
            bytes32(0),
            "",
            logCid,
            0,
            0,
            refSlot
        );

        assertEq(feeDistributor.treeRoot(), bytes32(0));
        assertEq(feeDistributor.treeCid(), "");
        assertEq(feeDistributor.logCid(), logCid);
    }

    function test_processOracleReport_EmptySubsequentReport() public {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        string memory lastTreeCid = feeDistributor.treeCid();
        bytes32 lastRoot = feeDistributor.treeRoot();
        string memory newLogCid = someCIDv0();

        vm.prank(oracle);
        feeDistributor.processOracleReport(
            lastRoot,
            lastTreeCid,
            newLogCid,
            0,
            0,
            refSlot
        );

        assertEq(feeDistributor.treeRoot(), lastRoot);
        assertEq(feeDistributor.treeCid(), lastTreeCid);
        assertEq(feeDistributor.logCid(), newLogCid);
        assertEq(feeDistributor.totalClaimableShares(), shares);
    }

    function test_processOracleReport_RevertWhen_ZeroDistributedButNonZeroRebate()
        public
        assertInvariants
    {
        uint256 shares = 0;
        uint256 rebate = 10;
        uint256 refSlot = 154;
        stETH.mintShares(address(feeDistributor), shares + rebate);

        stETH.mintShares(address(feeDistributor), shares);

        vm.expectRevert(IFeeDistributor.InvalidReportData.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            shares,
            rebate,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_InvalidShares_TooMuchDistributed()
        public
        assertInvariants
    {
        uint256 shares = 100;
        uint256 refSlot = 154;

        stETH.mintShares(address(feeDistributor), shares);

        vm.expectRevert(IFeeDistributor.InvalidShares.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            shares + 1,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_InvalidShares_NotEnoughForRebate()
        public
        assertInvariants
    {
        uint256 shares = 100;
        uint256 refSlot = 154;

        stETH.mintShares(address(feeDistributor), shares);

        vm.expectRevert(IFeeDistributor.InvalidShares.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            shares,
            1,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_TreeRootEmpty()
        public
        assertInvariants
    {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        stETH.mintShares(address(feeDistributor), shares);

        vm.expectRevert(IFeeDistributor.InvalidTreeRoot.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            bytes32(0),
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_SameRootNonZeroShares()
        public
        assertInvariants
    {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        stETH.mintShares(address(feeDistributor), shares);
        bytes32 root = feeDistributor.treeRoot();

        vm.expectRevert(IFeeDistributor.InvalidTreeRoot.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            root,
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_ZeroTreeCidNonZeroShares()
        public
        assertInvariants
    {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        stETH.mintShares(address(feeDistributor), shares);

        vm.expectRevert(IFeeDistributor.InvalidTreeCid.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            "",
            someCIDv0(),
            shares,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_SameTreeCidNonZeroShares()
        public
        assertInvariants
    {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        stETH.mintShares(address(feeDistributor), shares);
        string memory lastTreeCid = feeDistributor.treeCid();

        vm.expectRevert(IFeeDistributor.InvalidTreeCid.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            lastTreeCid,
            someCIDv0(),
            shares,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_ZeroLogCid() public {
        uint256 refSlot = 154;
        vm.expectRevert(IFeeDistributor.InvalidLogCID.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            "",
            0,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_SameLogCid() public {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        string memory lastLogCid = feeDistributor.logCid();

        vm.expectRevert(IFeeDistributor.InvalidLogCID.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            lastLogCid,
            0,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_MoreSharesThanBalance()
        public
        assertInvariants
    {
        uint256 shares = 1_000_000;
        uint256 refSlot = 154;
        _makeInitialReport(shares);

        vm.expectRevert(IFeeDistributor.InvalidShares.selector);
        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            1,
            0,
            refSlot
        );
    }

    function test_processOracleReport_RevertWhen_NotOracle()
        public
        assertInvariants
    {
        uint256 refSlot = 154;
        vm.expectRevert(IFeeDistributor.SenderIsNotOracle.selector);
        vm.prank(stranger);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            1,
            0,
            refSlot
        );
    }

    function test_setRebateRecipient() public {
        address recipient = nextAddress();
        vm.expectEmit(address(feeDistributor));
        emit IFeeDistributor.RebateRecipientSet(recipient);
        feeDistributor.setRebateRecipient(recipient);
        assertEq(feeDistributor.rebateRecipient(), recipient);
    }

    function test_setRebateRecipient_revertWhen_ZeroRebateRecipientAddress()
        public
    {
        vm.expectRevert(IFeeDistributor.ZeroRebateRecipientAddress.selector);
        feeDistributor.setRebateRecipient(address(0));
    }

    function test_setRebateRecipient_revertWhen_NotAdmin() public {
        address recipient = nextAddress();
        expectRoleRevert(stranger, feeDistributor.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        feeDistributor.setRebateRecipient(recipient);
    }

    function _makeInitialReport(uint256 shares) internal {
        stETH.mintShares(address(feeDistributor), shares);
        uint256 refSlot = 154;

        vm.prank(oracle);
        feeDistributor.processOracleReport(
            someBytes32(),
            someCIDv0(),
            someCIDv0(),
            shares,
            0,
            refSlot
        );
    }
}

contract FeeDistributorAssetRecovererTest is FeeDistributorTestBase {
    address internal recoverer;

    function setUp() public {
        Stub accounting = new Stub();

        (, , stETH, , ) = initLido();
        vm.label(address(stETH), "STETH");

        recoverer = nextAddress("RECOVERER");
        stranger = nextAddress("STRANGER");

        rebateRecipient = nextAddress("REBATE_RECIPIENT");

        feeDistributor = new FeeDistributor(
            address(stETH),
            address(accounting),
            nextAddress("ORACLE")
        );

        _enableInitializers(address(feeDistributor));

        feeDistributor.initialize(address(this), rebateRecipient);

        feeDistributor.grantRole(feeDistributor.RECOVERER_ROLE(), recoverer);
    }

    function test_recoverEtherHappyPath() public assertInvariants {
        uint256 amount = 42 ether;
        vm.deal(address(feeDistributor), amount);

        vm.expectEmit(address(feeDistributor));
        emit IAssetRecovererLib.EtherRecovered(recoverer, amount);

        vm.prank(recoverer);
        feeDistributor.recoverEther();

        assertEq(address(feeDistributor).balance, 0);
        assertEq(address(recoverer).balance, amount);
    }

    function test_recoverEther_RevertWhen_Unauthorized()
        public
        assertInvariants
    {
        expectRoleRevert(stranger, feeDistributor.RECOVERER_ROLE());
        vm.prank(stranger);
        feeDistributor.recoverEther();
    }

    function test_recoverERC20HappyPath() public assertInvariants {
        ERC20Testable token = new ERC20Testable();
        token.mint(address(feeDistributor), 1000);

        vm.prank(recoverer);
        vm.expectEmit(address(feeDistributor));
        emit IAssetRecovererLib.ERC20Recovered(address(token), recoverer, 1000);
        feeDistributor.recoverERC20(address(token), 1000);

        assertEq(token.balanceOf(address(feeDistributor)), 0);
        assertEq(token.balanceOf(recoverer), 1000);
    }

    function test_recoverERC20_RevertWhen_Unauthorized() public {
        ERC20Testable token = new ERC20Testable();
        token.mint(address(feeDistributor), 1000);

        expectRoleRevert(stranger, feeDistributor.RECOVERER_ROLE());
        vm.prank(stranger);
        feeDistributor.recoverERC20(address(token), 1000);
    }

    function test_recoverERC20_RevertWhen_StETH() public assertInvariants {
        vm.prank(recoverer);
        vm.expectRevert(IAssetRecovererLib.NotAllowedToRecover.selector);
        feeDistributor.recoverERC20(address(stETH), 1000);
    }

    function test_recoverERC721_RevertWhen_Unauthorized() public {
        expectRoleRevert(stranger, feeDistributor.RECOVERER_ROLE());
        vm.prank(stranger);
        feeDistributor.recoverERC721(address(1), 1);
    }

    function test_recoverERC1155_RevertWhen_Unauthorized() public {
        expectRoleRevert(stranger, feeDistributor.RECOVERER_ROLE());
        vm.prank(stranger);
        feeDistributor.recoverERC1155(address(1), 1);
    }
}
