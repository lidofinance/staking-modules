// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { EjectorMock } from "../helpers/mocks/EjectorMock.sol";

import { Test, Vm } from "forge-std/Test.sol";
import { CSStrikes } from "src/CSStrikes.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { ICSEjector } from "src/interfaces/ICSEjector.sol";
import { ICSExitPenalties } from "src/interfaces/ICSExitPenalties.sol";

import { ICSModule } from "src/interfaces/ICSModule.sol";
import { ICSStrikes } from "src/interfaces/ICSStrikes.sol";
import { InvariantAsserts } from "../helpers/InvariantAsserts.sol";
import { MerkleTree } from "../helpers/MerkleTree.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { ExitPenaltiesMock } from "../helpers/mocks/ExitPenaltiesMock.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";

contract CSStrikesTestBase is Test, Fixtures, Utilities, InvariantAsserts {
    address internal admin;
    address internal stranger;
    address internal refundRecipient;
    address internal oracle;
    CSMMock internal module;
    address internal exitPenalties;
    address internal ejector;
    CSStrikes internal strikes;
    MerkleTree internal tree;

    modifier assertInvariants() {
        _;
        vm.pauseGasMetering();
        assertStrikesTree(strikes);
        vm.resumeGasMetering();
    }

    // A bunch of wrapper to test functions with calldata arguments.

    function hashLeaf(
        ICSStrikes.KeyStrikes calldata keyStrikes,
        bytes memory pubkey
    ) external view returns (bytes32) {
        return strikes.hashLeaf(keyStrikes, pubkey);
    }

    function verifyProof(
        ICSStrikes.KeyStrikes[] calldata keyStrikesList,
        bytes[] memory pubkeys,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external view returns (bool) {
        return strikes.verifyProof(keyStrikesList, pubkeys, proof, proofFlags);
    }

    function processBadPerformanceProof(
        ICSStrikes.KeyStrikes[] calldata keyStrikesList,
        bytes32[] calldata proof,
        bool[] calldata proofFlags,
        address _refundRecipient
    ) external payable {
        strikes.processBadPerformanceProof{ value: msg.value }(
            keyStrikesList,
            proof,
            proofFlags,
            _refundRecipient
        );
    }
}

contract CSStrikesConstructorTest is CSStrikesTestBase {
    function setUp() public {
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");
        oracle = nextAddress("ORACLE");
        module = new CSMMock();
        exitPenalties = address(new ExitPenaltiesMock());
        ejector = address(new EjectorMock(address(module)));
    }

    function test_constructor_happyPath() public {
        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        assertEq(address(strikes.MODULE()), address(module));
        assertEq(strikes.ORACLE(), oracle);
        assertEq(address(strikes.EXIT_PENALTIES()), exitPenalties);
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        address parametersRegistry = address(module.PARAMETERS_REGISTRY());
        vm.expectRevert(ICSStrikes.ZeroModuleAddress.selector);
        new CSStrikes(address(0), oracle, exitPenalties, parametersRegistry);
    }

    function test_constructor_RevertWhen_ZeroExitPenaltiesAddress() public {
        address parametersRegistry = address(module.PARAMETERS_REGISTRY());
        vm.expectRevert(ICSStrikes.ZeroExitPenaltiesAddress.selector);
        new CSStrikes(address(module), oracle, address(0), parametersRegistry);
    }

    function test_constructor_RevertWhen_ZeroParametersRegistryAddress()
        public
    {
        vm.expectRevert(ICSStrikes.ZeroParametersRegistryAddress.selector);
        new CSStrikes(exitPenalties, oracle, exitPenalties, address(0));
    }

    function test_constructor_RevertWhen_ZeroOracleAddress() public {
        address parametersRegistry = address(module.PARAMETERS_REGISTRY());
        vm.expectRevert(ICSStrikes.ZeroOracleAddress.selector);
        new CSStrikes(
            exitPenalties,
            address(0),
            exitPenalties,
            parametersRegistry
        );
    }

    function test_initialize_happyPath() public {
        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        _enableInitializers(address(strikes));

        vm.expectEmit(address(strikes));
        emit ICSStrikes.EjectorSet(ejector);
        strikes.initialize(admin, ejector);

        assertEq(address(strikes.ejector()), ejector);
        assertTrue(strikes.hasRole(strikes.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(strikes.getInitializedVersion(), 1);
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        _enableInitializers(address(strikes));

        vm.expectRevert(ICSStrikes.ZeroAdminAddress.selector);
        strikes.initialize(address(0), ejector);
    }

    function test_initialize_RevertWhen_ZeroEjectorAddress() public {
        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        _enableInitializers(address(strikes));

        vm.expectRevert(ICSStrikes.ZeroEjectorAddress.selector);
        strikes.initialize(admin, address(0));
    }
}

contract CSStrikesTest is CSStrikesTestBase {
    function setUp() public {
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");
        refundRecipient = nextAddress("REFUND_RECIPIENT");
        oracle = nextAddress("ORACLE");
        module = new CSMMock();
        exitPenalties = address(new ExitPenaltiesMock());
        ejector = address(new EjectorMock(address(module)));

        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        _enableInitializers(address(strikes));
        strikes.initialize(admin, ejector);

        tree = new MerkleTree();

        vm.label(address(strikes), "STRIKES");
    }

    function test_setEjector() public {
        ejector = address(new EjectorMock(address(module)));

        vm.expectEmit(address(strikes));
        emit ICSStrikes.EjectorSet(ejector);

        vm.prank(admin);
        strikes.setEjector(ejector);
        assertEq(address(strikes.ejector()), ejector);
    }

    function test_setEjector_RevertWhen_ZeroEjectorAddress() public {
        vm.expectRevert(ICSStrikes.ZeroEjectorAddress.selector);
        vm.prank(admin);
        strikes.setEjector(address(0));
    }

    function test_processOracleReport() public assertInvariants {
        string memory treeCid = someCIDv0();
        bytes32 treeRoot = someBytes32();

        vm.expectEmit(address(strikes));
        emit ICSStrikes.StrikesDataUpdated(treeRoot, treeCid);

        vm.prank(oracle);
        strikes.processOracleReport(treeRoot, treeCid);

        assertEq(strikes.treeRoot(), treeRoot);
        assertEq(strikes.treeCid(), treeCid);
    }

    function test_processOracleReport_EmptyInitialReport() public {
        vm.recordLogs();
        vm.prank(oracle);
        strikes.processOracleReport(bytes32(0), "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function test_processOracleReport_EmptySubsequentReport() public {
        vm.prank(oracle);
        strikes.processOracleReport(someBytes32(), someCIDv0());

        vm.expectEmit(address(strikes));
        emit ICSStrikes.StrikesDataWiped();

        vm.prank(oracle);
        strikes.processOracleReport(bytes32(0), "");

        assertEq(strikes.treeRoot(), bytes32(0));
        assertEq(strikes.treeCid(), "");
    }

    function test_processOracleReport_NonEmptySubsequentReport()
        public
        assertInvariants
    {
        string memory treeCid = someCIDv0();
        bytes32 treeRoot = someBytes32();
        vm.prank(oracle);
        strikes.processOracleReport(treeRoot, treeCid);

        string memory newTreeCid = someCIDv0();
        bytes32 newTreeRoot = someBytes32();

        vm.expectEmit(address(strikes));
        emit ICSStrikes.StrikesDataUpdated(newTreeRoot, newTreeCid);

        vm.prank(oracle);
        strikes.processOracleReport(newTreeRoot, newTreeCid);

        assertEq(strikes.treeRoot(), newTreeRoot);
        assertEq(strikes.treeCid(), newTreeCid);
    }

    function test_processOracleReport_NothingUpdated() public assertInvariants {
        bytes32 root = someBytes32();
        string memory treeCid = someCIDv0();

        vm.prank(oracle);
        strikes.processOracleReport(root, treeCid);

        vm.recordLogs();
        {
            vm.prank(oracle);
            strikes.processOracleReport(root, treeCid);
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);

        assertEq(strikes.treeRoot(), root);
        assertEq(strikes.treeCid(), treeCid);
    }

    function test_processOracleReport_RevertWhen_NotOracle()
        public
        assertInvariants
    {
        vm.expectRevert(ICSStrikes.SenderIsNotOracle.selector);
        strikes.processOracleReport(bytes32(0), someCIDv0());
    }

    function test_processOracleReport_RevertWhen_OnlyTreeRootEmpty()
        public
        assertInvariants
    {
        vm.prank(oracle);
        strikes.processOracleReport(someBytes32(), someCIDv0());

        vm.expectRevert(ICSStrikes.InvalidReportData.selector);
        vm.prank(oracle);
        strikes.processOracleReport(bytes32(0), someCIDv0());
    }

    function test_processOracleReport_RevertWhen_OnlyTreeCidEmpty()
        public
        assertInvariants
    {
        vm.prank(oracle);
        strikes.processOracleReport(someBytes32(), someCIDv0());

        vm.expectRevert(ICSStrikes.InvalidReportData.selector);
        vm.prank(oracle);
        strikes.processOracleReport(someBytes32(), "");
    }

    function test_processOracleReport_RevertWhen_OnlyRootUpdated()
        public
        assertInvariants
    {
        bytes32 root = someBytes32();
        string memory treeCid = someCIDv0();

        vm.prank(oracle);
        strikes.processOracleReport(root, treeCid);

        vm.expectRevert(ICSStrikes.InvalidReportData.selector);
        vm.prank(oracle);
        strikes.processOracleReport(someBytes32(), treeCid);
    }

    function test_processOracleReport_RevertWhen_OnlyCidUpdated()
        public
        assertInvariants
    {
        bytes32 root = someBytes32();
        string memory treeCid = someCIDv0();

        vm.prank(oracle);
        strikes.processOracleReport(root, treeCid);

        vm.expectRevert(ICSStrikes.InvalidReportData.selector);
        vm.prank(oracle);
        strikes.processOracleReport(root, someCIDv0());
    }
}

contract CSStrikesProofTest is CSStrikesTestBase {
    using DeepCopy for *;

    struct Leaf {
        ICSStrikes.KeyStrikes keyStrikes;
        bytes pubkey;
    }

    Leaf[] internal leaves;

    function setUp() public {
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");
        refundRecipient = nextAddress("REFUND_RECIPIENT");
        oracle = nextAddress("ORACLE");
        module = new CSMMock();
        exitPenalties = address(new ExitPenaltiesMock());
        ejector = address(new EjectorMock(address(module)));

        strikes = new CSStrikes(
            address(module),
            oracle,
            exitPenalties,
            address(module.PARAMETERS_REGISTRY())
        );
        _enableInitializers(address(strikes));
        strikes.initialize(admin, ejector);

        tree = new MerkleTree();

        vm.label(address(strikes), "STRIKES");
    }

    modifier withTreeOfLeavesCount(uint256 leavesCount) {
        vm.pauseGasMetering();
        for (uint256 i; i < leavesCount; ++i) {
            uint256[] memory strikesData = UintArr(100500, 0, 0);
            (bytes memory pubkey, ) = keysSignatures(1, i);
            leaves.push(
                Leaf(
                    ICSStrikes.KeyStrikes({
                        nodeOperatorId: i,
                        keyIndex: 0,
                        data: strikesData
                    }),
                    pubkey
                )
            );
            tree.pushLeaf(abi.encode(i, pubkey, strikesData));
        }
        vm.resumeGasMetering();

        bytes32 root = tree.root();
        vm.prank(oracle);
        strikes.processOracleReport(root, someCIDv0());

        _;
    }

    function test_hashLeaf() public view {
        (bytes memory pubkey, ) = keysSignatures(1);
        assertEq(
            this.hashLeaf(
                ICSStrikes.KeyStrikes({
                    nodeOperatorId: 42,
                    keyIndex: 0,
                    data: UintArr(100500)
                }),
                pubkey
            ),
            // keccak256(bytes.concat(keccak256(abi.encode(42, pubkey, [100500])))) = 0x3a1e33fb3e7fe10371e522cee19c593a324542e57e4da98719979d7490d2eed7
            0x3a1e33fb3e7fe10371e522cee19c593a324542e57e4da98719979d7490d2eed7
        );
    }

    function test_verifyProofOneLeaf() public withTreeOfLeavesCount(7) {
        for (uint256 i; i < leaves.length; i++) {
            Leaf memory leaf = leaves[i];

            ICSStrikes.KeyStrikes[]
                memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
            keyStrikesList[0] = leaf.keyStrikes;

            bytes[] memory pubkeys = new bytes[](1);
            pubkeys[0] = leaf.pubkey;

            bytes32[] memory proof = tree.getProof(i);
            bool[] memory proofFlags = new bool[](proof.length);

            bool isValid = this.verifyProof(
                keyStrikesList,
                pubkeys,
                proof,
                proofFlags
            );
            assertTrue(isValid);
        }
    }

    function test_verifyProofAllLeaves() public withTreeOfLeavesCount(7) {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](leaves.length);
        bytes[] memory pubkeys = new bytes[](leaves.length);

        for (uint256 i; i < leaves.length; ++i) {
            keyStrikesList[i] = leaves[i].keyStrikes;
            pubkeys[i] = leaves[i].pubkey;
        }

        bool[] memory proofFlags = new bool[](leaves.length - 1);
        for (uint256 i; i < proofFlags.length; ++i) {
            proofFlags[i] = true;
        }

        bool isValid = this.verifyProof(
            keyStrikesList,
            pubkeys,
            new bytes32[](0),
            proofFlags
        );
        assertTrue(isValid);
    }

    function test_verifyProofTwoSiblings() public withTreeOfLeavesCount(7) {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](2);
        keyStrikesList[0] = leaves[0].keyStrikes;
        keyStrikesList[1] = leaves[1].keyStrikes;

        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = leaves[0].pubkey;
        pubkeys[1] = leaves[1].pubkey;

        bytes32[] memory singleLeafProof = tree.getProof(0);
        bytes32[] memory proof = new bytes32[](singleLeafProof.length - 1);
        for (uint256 i; i < proof.length; ++i) {
            proof[i] = singleLeafProof[i + 1];
        }

        bool[] memory proofFlags = new bool[](singleLeafProof.length);
        proofFlags[0] = true; // Start from the sibling leaves
        for (uint256 i = 1; i < proofFlags.length; ++i) {
            proofFlags[i] = false; // The rest from the proof
        }

        bool isValid = this.verifyProof(
            keyStrikesList,
            pubkeys,
            proof,
            proofFlags
        );
        assertTrue(isValid);
    }

    function test_verifyProof_RevertWhen_WrongFlagsLength()
        public
        withTreeOfLeavesCount(7)
    {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
        keyStrikesList[0] = leaves[0].keyStrikes;

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = leaves[0].pubkey;

        bytes32[] memory proof = tree.getProof(0);

        // Just right
        {
            bool[] memory proofFlags = new bool[](proof.length);
            for (uint256 i; i < proofFlags.length; ++i) {
                proofFlags[i] = false;
            }

            bool isValid = this.verifyProof(
                keyStrikesList,
                pubkeys,
                proof,
                proofFlags
            );
            assertTrue(isValid);
        }

        // Not enough
        {
            bool[] memory proofFlags = new bool[](proof.length - 1);
            for (uint256 i; i < proofFlags.length; ++i) {
                proofFlags[i] = false;
            }

            vm.expectRevert(MerkleProof.MerkleProofInvalidMultiproof.selector);
            this.verifyProof(keyStrikesList, pubkeys, proof, proofFlags);
        }

        // Too much
        {
            bool[] memory proofFlags = new bool[](proof.length + 1);
            for (uint256 i; i < proofFlags.length; ++i) {
                proofFlags[i] = false;
            }

            vm.expectRevert(MerkleProof.MerkleProofInvalidMultiproof.selector);
            this.verifyProof(keyStrikesList, pubkeys, proof, proofFlags);
        }
    }

    function test_verifyProofFails_InvalidProof()
        public
        withTreeOfLeavesCount(7)
    {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
        keyStrikesList[0] = leaves[0].keyStrikes;

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = leaves[0].pubkey;

        bytes32[] memory proof = tree.getProof(0);
        assertGt(proof.length, 0);
        proof[0] = bytes32(0);

        bool[] memory proofFlags = new bool[](proof.length);
        for (uint256 i; i < proofFlags.length; ++i) {
            proofFlags[i] = false;
        }

        bool isValid = this.verifyProof(
            keyStrikesList,
            pubkeys,
            proof,
            proofFlags
        );
        assertFalse(isValid);
    }

    function test_verifyProofFails_InvalidLeaf()
        public
        withTreeOfLeavesCount(7)
    {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
        keyStrikesList[0] = leaves[0].keyStrikes;

        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = leaves[1].pubkey; // <-- error

        bytes32[] memory proof = tree.getProof(0);

        bool[] memory proofFlags = new bool[](proof.length);
        for (uint256 i; i < proofFlags.length; ++i) {
            proofFlags[i] = false;
        }

        bool isValid = this.verifyProof(
            keyStrikesList,
            pubkeys,
            proof,
            proofFlags
        );
        assertFalse(isValid);
    }

    function testFuzz_processBadPerformanceProof_HappyPath(
        uint256 a,
        uint256 s
    ) public withTreeOfLeavesCount(99) {
        // ----------------------------| indicies.length
        // <----------->| a
        // <---->| s
        // to make a+s+s < indicies.length
        a = bound(a, 0, leaves.length / 2);
        s = bound(s, 1, a / 2 == 0 ? 1 : a / 2);
        uint256[] memory indicies = UintArr(a, a + s, a + s + s);

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](
                indicies.length
            );
        (bytes32[] memory proof, bool[] memory proofFlags) = tree.getMultiProof(
            indicies
        );

        for (uint256 i; i < indicies.length; i++) {
            Leaf memory leaf = leaves[indicies[i]];
            keyStrikesList[i] = leaf.keyStrikes;
            vm.mockCall(
                address(module),
                abi.encodeWithSelector(
                    ICSModule.getSigningKeys.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex
                ),
                abi.encode(leaf.pubkey)
            );
            vm.expectCall(
                address(ejector),
                abi.encodeWithSelector(
                    ICSEjector.ejectBadPerformer.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex,
                    refundRecipient
                )
            );
            vm.expectCall(
                address(exitPenalties),
                abi.encodeWithSelector(
                    ICSExitPenalties.processStrikesReport.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.pubkey
                )
            );
        }
        this.processBadPerformanceProof{ value: keyStrikesList.length }(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }

    function test_processBadPerformanceProof_DefaultRefundRecipient()
        public
        withTreeOfLeavesCount(3)
    {
        Leaf memory leaf = leaves[0];

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
        keyStrikesList[0] = leaf.keyStrikes;

        bytes32[] memory proof = tree.getProof(0);
        bool[] memory proofFlags = new bool[](proof.length);

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.getSigningKeys.selector,
                leaf.keyStrikes.nodeOperatorId,
                leaf.keyStrikes.keyIndex
            ),
            abi.encode(leaf.pubkey)
        );
        vm.expectCall(
            address(ejector),
            abi.encodeWithSelector(
                ICSEjector.ejectBadPerformer.selector,
                leaf.keyStrikes.nodeOperatorId,
                leaf.keyStrikes.keyIndex,
                address(this)
            )
        );

        this.processBadPerformanceProof{ value: 1 }(
            keyStrikesList,
            proof,
            proofFlags,
            address(0)
        );
    }

    function testFuzz_processBadPerformanceProof_RevertWhen_InvalidProof(
        uint256 a,
        uint256 s
    ) public withTreeOfLeavesCount(99) {
        // ----------------------------| indicies.length
        // <----------->| a
        // <---->| s
        // to make a+s+s < indicies.length
        a = bound(a, 0, leaves.length / 2);
        s = bound(s, 1, a / 2 == 0 ? 1 : a / 2);
        uint256[] memory indicies = UintArr(a, a + s, a + s + s);

        (bytes32[] memory proof, bool[] memory proofFlags) = tree.getMultiProof(
            indicies
        );

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](
                indicies.length
            );
        for (uint256 i; i < indicies.length; i++) {
            Leaf memory leaf = leaves[indicies[i]];
            keyStrikesList[i] = leaf.keyStrikes;
            vm.mockCall(
                address(module),
                abi.encodeWithSelector(
                    ICSModule.getSigningKeys.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex
                ),
                abi.encode(leaf.pubkey)
            );
        }

        {
            ICSStrikes.KeyStrikes[] memory brokenStrikesList = keyStrikesList
                .copy();
            brokenStrikesList[0].nodeOperatorId++;

            vm.expectRevert(ICSStrikes.InvalidProof.selector);
            this.processBadPerformanceProof{ value: keyStrikesList.length }(
                brokenStrikesList,
                proof,
                proofFlags,
                refundRecipient
            );
        }

        {
            bytes32[] memory brokenProof = proof.copy();
            brokenProof[0] = bytes32(uint256(1));

            vm.expectRevert(ICSStrikes.InvalidProof.selector);
            this.processBadPerformanceProof{ value: keyStrikesList.length }(
                keyStrikesList,
                brokenProof,
                proofFlags,
                refundRecipient
            );
        }

        this.processBadPerformanceProof{ value: keyStrikesList.length }(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }

    function test_processBadPerformanceProof_RevertWhen_NotEnoughStrikesToEject()
        public
        withTreeOfLeavesCount(3)
    {
        Leaf memory leaf = leaves[0];

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](1);
        keyStrikesList[0] = leaf.keyStrikes;

        bytes32[] memory proof = tree.getProof(0);
        bool[] memory proofFlags = new bool[](proof.length);

        module.PARAMETERS_REGISTRY().setStrikesParams(0, 6, 100501);

        vm.mockCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.getSigningKeys.selector,
                leaf.keyStrikes.nodeOperatorId,
                leaf.keyStrikes.keyIndex
            ),
            abi.encode(leaf.pubkey)
        );

        vm.expectRevert(ICSStrikes.NotEnoughStrikesToEject.selector);
        this.processBadPerformanceProof{ value: 1 }(
            keyStrikesList,
            proof,
            proofFlags,
            address(0)
        );
    }

    function test_processBadPerformanceProof_RevertWhen_EmptyKeyStrikesList()
        public
    {
        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](0);
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.expectRevert(ICSStrikes.EmptyKeyStrikesList.selector);
        this.processBadPerformanceProof(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }

    function test_processBadPerformanceProof_RevertWhen_ValueNotEvenlyDivisible()
        public
        withTreeOfLeavesCount(3)
    {
        uint256[] memory indicies = UintArr(1, 2);

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](
                indicies.length
            );
        (bytes32[] memory proof, bool[] memory proofFlags) = tree.getMultiProof(
            indicies
        );

        for (uint256 i; i < indicies.length; i++) {
            Leaf memory leaf = leaves[indicies[i]];
            keyStrikesList[i] = leaf.keyStrikes;
            vm.mockCall(
                address(module),
                abi.encodeWithSelector(
                    ICSModule.getSigningKeys.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex
                ),
                abi.encode(leaf.pubkey)
            );
        }
        vm.expectRevert(ICSStrikes.ValueNotEvenlyDivisible.selector);
        this.processBadPerformanceProof{ value: 11 wei }(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }

    function test_processBadPerformanceProof_RevertWhen_ZeroMsgValue()
        public
        withTreeOfLeavesCount(3)
    {
        uint256[] memory indicies = UintArr(1, 2);

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](
                indicies.length
            );
        (bytes32[] memory proof, bool[] memory proofFlags) = tree.getMultiProof(
            indicies
        );

        for (uint256 i; i < indicies.length; i++) {
            Leaf memory leaf = leaves[indicies[i]];
            keyStrikesList[i] = leaf.keyStrikes;
            vm.mockCall(
                address(module),
                abi.encodeWithSelector(
                    ICSModule.getSigningKeys.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex
                ),
                abi.encode(leaf.pubkey)
            );
        }
        vm.expectRevert(ICSStrikes.ZeroMsgValue.selector);
        this.processBadPerformanceProof{ value: 0 }(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }

    function test_processBadPerformanceProof_okValue()
        public
        withTreeOfLeavesCount(3)
    {
        uint256[] memory indicies = UintArr(1, 2);

        ICSStrikes.KeyStrikes[]
            memory keyStrikesList = new ICSStrikes.KeyStrikes[](
                indicies.length
            );
        (bytes32[] memory proof, bool[] memory proofFlags) = tree.getMultiProof(
            indicies
        );

        for (uint256 i; i < indicies.length; i++) {
            Leaf memory leaf = leaves[indicies[i]];
            keyStrikesList[i] = leaf.keyStrikes;
            vm.mockCall(
                address(module),
                abi.encodeWithSelector(
                    ICSModule.getSigningKeys.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex
                ),
                abi.encode(leaf.pubkey)
            );
            vm.expectCall(
                address(ejector),
                abi.encodeWithSelector(
                    ICSEjector.ejectBadPerformer.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.keyStrikes.keyIndex,
                    refundRecipient
                )
            );
            vm.expectCall(
                address(exitPenalties),
                abi.encodeWithSelector(
                    ICSExitPenalties.processStrikesReport.selector,
                    leaf.keyStrikes.nodeOperatorId,
                    leaf.pubkey
                )
            );
        }
        this.processBadPerformanceProof{ value: 10 wei }(
            keyStrikesList,
            proof,
            proofFlags,
            refundRecipient
        );
    }
}

library DeepCopy {
    function copy(
        ICSStrikes.KeyStrikes[] memory arr
    ) internal pure returns (ICSStrikes.KeyStrikes[] memory buf) {
        buf = new ICSStrikes.KeyStrikes[](arr.length);
        for (uint256 i; i < buf.length; ++i) {
            buf[i] = ICSStrikes.KeyStrikes({
                nodeOperatorId: arr[i].nodeOperatorId,
                keyIndex: arr[i].keyIndex,
                data: copy(arr[i].data)
            });
        }
    }

    function copy(
        bytes32[] memory arr
    ) internal pure returns (bytes32[] memory buf) {
        buf = new bytes32[](arr.length);
        for (uint256 i; i < buf.length; ++i) {
            buf[i] = arr[i];
        }
    }

    function copy(
        uint256[] memory arr
    ) internal pure returns (uint256[] memory buf) {
        buf = new uint256[](arr.length);
        for (uint256 i; i < buf.length; ++i) {
            buf[i] = arr[i];
        }
    }
}
