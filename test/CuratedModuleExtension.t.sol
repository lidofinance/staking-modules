// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "./helpers/Utilities.sol";
import { Fixtures } from "./helpers/Fixtures.sol";
import { CSMMock } from "./helpers/mocks/CSMMock.sol";
import { OperatorsDataMock } from "./helpers/mocks/OperatorsDataMock.sol";
import { PausableUntil } from "../src/lib/utils/PausableUntil.sol";
import { CuratedModuleExtension } from "../src/CuratedModuleExtension.sol";
import { ICuratedModuleExtension } from "../src/interfaces/ICuratedModuleExtension.sol";
import { IOperatorsData, OperatorInfo } from "../src/interfaces/IOperatorsData.sol";
import { ICSModule, NodeOperatorManagementProperties } from "../src/interfaces/ICSModule.sol";
import { ICSAccounting } from "../src/interfaces/ICSAccounting.sol";
import { MerkleTree } from "./helpers/MerkleTree.sol";

contract CuratedModuleExtensionTestBase is Test, Utilities, Fixtures {
    CSMMock public module;
    OperatorsDataMock public data;
    CuratedModuleExtension public ext;

    address public admin;
    address public member;
    address public member2;
    address public stranger;

    MerkleTree internal tree;
    bytes32 internal root;
    string internal cid;

    function setUp() public virtual {
        admin = nextAddress("ADMIN");
        member = nextAddress("MEMBER");
        member2 = nextAddress("MEMBER");
        stranger = nextAddress("STRANGER");

        module = new CSMMock();
        module.mock_setNodeOperatorsCount(1);
        module.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: member,
                rewardAddress: member,
                extendedManagerPermissions: true
            })
        );

        data = new OperatorsDataMock();

        tree = new MerkleTree();
        tree.pushLeaf(abi.encode(member));
        tree.pushLeaf(abi.encode(member2));
        root = tree.root();
        cid = someCIDv0();

        ext = new CuratedModuleExtension(address(module), address(data));
        _enableInitializers(address(ext));
        ext.initialize(1, root, cid, admin);

        vm.startPrank(admin);
        ext.grantRole(ext.SET_TREE_ROLE(), admin);
        vm.stopPrank();
    }
}

contract CuratedModuleExtensionTest_constructor is
    CuratedModuleExtensionTestBase
{
    function test_constructor() public {
        CuratedModuleExtension e = new CuratedModuleExtension(
            address(module),
            address(data)
        );
        assertEq(address(e.MODULE()), address(module));
        assertEq(address(e.OPERATORS_DATA()), address(data));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(ICuratedModuleExtension.ZeroModuleAddress.selector);
        new CuratedModuleExtension(address(0), address(data));
    }

    function test_constructor_RevertWhen_ZeroOperatorsData() public {
        vm.expectRevert(
            ICuratedModuleExtension.ZeroOperatorsDataAddress.selector
        );
        new CuratedModuleExtension(address(module), address(0));
    }
}

contract CuratedModuleExtensionTest_initialize is
    CuratedModuleExtensionTestBase
{
    function test_initialize() public {
        CuratedModuleExtension e = new CuratedModuleExtension(
            address(module),
            address(data)
        );
        _enableInitializers(address(e));
        e.initialize(1, root, cid, admin);
        assertEq(e.treeRoot(), root);
        assertEq(keccak256(bytes(e.treeCid())), keccak256(bytes(cid)));
        assertTrue(e.hasRole(e.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(e.curveId(), 1);
    }

    function test_initialize_RevertWhen_ZeroAdmin() public {
        CuratedModuleExtension e = new CuratedModuleExtension(
            address(module),
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(ICuratedModuleExtension.ZeroAdminAddress.selector);
        e.initialize(1, root, cid, address(0));
    }

    function test_initialize_RevertWhen_InvalidTreeRoot() public {
        CuratedModuleExtension e = new CuratedModuleExtension(
            address(module),
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeRoot.selector);
        e.initialize(1, bytes32(0), cid, admin);
    }

    function test_initialize_RevertWhen_InvalidTreeCid() public {
        CuratedModuleExtension e = new CuratedModuleExtension(
            address(module),
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeCid.selector);
        e.initialize(1, root, "", admin);
    }
}

contract CuratedModuleExtensionTest_setTreeParams is
    CuratedModuleExtensionTestBase
{
    function test_setTreeParams() public {
        bytes32 newRoot = keccak256(abi.encodePacked("root2"));
        string memory newCid = someCIDv0();

        vm.expectEmit(address(ext));
        emit ICuratedModuleExtension.TreeSet(newRoot, newCid);
        vm.prank(admin);
        ext.setTreeParams(newRoot, newCid);

        assertEq(ext.treeRoot(), newRoot);
        assertEq(keccak256(bytes(ext.treeCid())), keccak256(bytes(newCid)));
    }

    function test_setTreeParams_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, ext.SET_TREE_ROLE());
        vm.prank(stranger);
        ext.setTreeParams(keccak256("x"), "cid");
    }

    function test_setTreeParams_RevertWhen_EmptyTreeRoot() public {
        vm.prank(admin);
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeRoot.selector);
        ext.setTreeParams(bytes32(0), "cid");
    }

    function test_setTreeParams_RevertWhen_EmptyTreeCid() public {
        vm.prank(admin);
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeCid.selector);
        ext.setTreeParams(keccak256("y"), "");
    }

    function test_setTreeParams_RevertWhen_SameTreeRoot() public {
        bytes32 root = ext.treeRoot();
        vm.prank(admin);
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeRoot.selector);
        ext.setTreeParams(root, someCIDv0());
    }

    function test_setTreeParams_RevertWhen_SameTreeCid() public {
        string memory cid = ext.treeCid();
        vm.prank(admin);
        vm.expectRevert(ICuratedModuleExtension.InvalidTreeCid.selector);
        ext.setTreeParams(keccak256("z"), cid);
    }

    function test_setTreeParams_MakesNewMemberEligible() public {
        MerkleTree newTree = new MerkleTree();
        newTree.pushLeaf(abi.encode(stranger));
        newTree.pushLeaf(abi.encode(member2));
        bytes32 newRoot = newTree.root();
        string memory newCid = someCIDv0();
        bytes32[] memory proof = newTree.getProof(0);

        assertFalse(ext.verifyProof(stranger, proof));

        vm.prank(admin);
        ext.setTreeParams(newRoot, newCid);

        assertTrue(ext.verifyProof(stranger, proof));

        vm.prank(stranger);
        uint256 id = ext.createNodeOperator(
            "Name2",
            "Desc2",
            address(0),
            address(0),
            proof
        );

        assertEq(id, 0);
        assertTrue(ext.isConsumed(stranger));
    }
}

contract CuratedModuleExtensionTest_pauseResume is
    CuratedModuleExtensionTestBase
{
    function test_pause_RevertWhen_NoRole() public {
        vm.expectRevert();
        ext.pauseFor(1);
    }

    function test_resume_RevertWhen_NoRole() public {
        vm.expectRevert();
        ext.resume();
    }

    function test_pause_HappyPath() public {
        vm.startPrank(admin);
        ext.grantRole(ext.PAUSE_ROLE(), admin);
        ext.pauseFor(1);
        vm.stopPrank();

        assertTrue(ext.isPaused());
    }

    function test_resume_HappyPath() public {
        vm.startPrank(admin);
        ext.grantRole(ext.PAUSE_ROLE(), admin);
        ext.grantRole(ext.RESUME_ROLE(), admin);
        ext.pauseFor(type(uint256).max);

        ext.resume();
        vm.stopPrank();

        assertFalse(ext.isPaused());
    }
}

contract CuratedModuleExtensionTest_createNodeOperator is
    CuratedModuleExtensionTestBase
{
    function test_createNodeOperator() public {
        bytes32[] memory proof = tree.getProof(0);

        vm.expectCall(
            address(data),
            abi.encodeWithSelector(
                IOperatorsData.set.selector,
                0,
                "Name",
                "Description"
            )
        );
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                ICSModule.createNodeOperator.selector,
                member,
                NodeOperatorManagementProperties({
                    managerAddress: address(0x1111),
                    rewardAddress: address(0x2222),
                    extendedManagerPermissions: true
                }),
                address(0)
            )
        );
        vm.expectCall(
            address(module.ACCOUNTING()),
            abi.encodeWithSelector(ICSAccounting.setBondCurve.selector, 0, 1)
        );
        vm.expectEmit(address(ext));
        emit ICuratedModuleExtension.Consumed(member);
        vm.prank(member);
        uint256 id = ext.createNodeOperator(
            "Name",
            "Description",
            address(0x1111),
            address(0x2222),
            proof
        );

        assertEq(id, 0);
        assertTrue(ext.isConsumed(member));
    }

    function test_createNodeOperator_RevertWhen_InvalidProof() public {
        bytes32[] memory emptyProof;
        vm.prank(member);
        vm.expectRevert(ICuratedModuleExtension.InvalidProof.selector);
        ext.createNodeOperator("N", "D", address(0), address(0), emptyProof);
    }

    function test_createNodeOperator_RevertWhen_AlreadyConsumed() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.prank(member);
        ext.createNodeOperator("A", "B", address(0), address(0), proof);

        vm.prank(member);
        vm.expectRevert(ICuratedModuleExtension.AlreadyConsumed.selector);
        ext.createNodeOperator("A", "B", address(0), address(0), proof);
    }

    function test_createNodeOperator_RevertWhen_NotMember() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.prank(stranger);
        vm.expectRevert(ICuratedModuleExtension.InvalidProof.selector);
        ext.createNodeOperator("N", "D", address(0), address(0), proof);
    }

    function test_createNodeOperator_RevertWhen_Paused() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.startPrank(admin);
        ext.grantRole(ext.PAUSE_ROLE(), admin);
        ext.pauseFor(1);
        vm.stopPrank();

        vm.prank(member);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        ext.createNodeOperator("N", "D", address(0), address(0), proof);
    }
}
