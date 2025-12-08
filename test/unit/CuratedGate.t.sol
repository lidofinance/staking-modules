// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";
import { Utilities } from "../helpers/Utilities.sol";
import { Fixtures } from "../helpers/Fixtures.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { OperatorsDataMock } from "../helpers/mocks/OperatorsDataMock.sol";
import { PausableUntil } from "../../src/lib/utils/PausableUntil.sol";
import { CuratedGate } from "../../src/CuratedGate.sol";
import { ICuratedGate } from "../../src/interfaces/ICuratedGate.sol";
import { IMerkleGate } from "../../src/interfaces/IMerkleGate.sol";
import { IOperatorsData, OperatorInfo } from "../../src/interfaces/IOperatorsData.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "../../src/interfaces/IBaseModule.sol";
import { IAccounting } from "../../src/interfaces/IAccounting.sol";
import { MerkleTree } from "../helpers/MerkleTree.sol";
import { IAssetRecovererLib } from "../../src/lib/AssetRecovererLib.sol";

contract CuratedGateTestBase is Test, Utilities, Fixtures {
    CSMMock public module;
    OperatorsDataMock public data;
    CuratedGate public gate;
    uint256 internal constant MODULE_ID = 1;

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

        gate = new CuratedGate(address(module), MODULE_ID, address(data));
        _enableInitializers(address(gate));
        gate.initialize(curveId(), root, cid, admin);

        vm.startPrank(admin);
        gate.grantRole(gate.SET_TREE_ROLE(), admin);
        vm.stopPrank();
    }

    function curveId() internal view virtual returns (uint256) {
        return 1;
    }
}

contract CuratedGateTestBaseDefaultCurve is CuratedGateTestBase {
    function curveId() internal view override returns (uint256) {
        return module.ACCOUNTING().DEFAULT_BOND_CURVE_ID();
    }
}

contract CuratedGateTest_constructor is CuratedGateTestBase {
    function test_constructor() public {
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
            address(data)
        );
        assertEq(address(e.MODULE()), address(module));
        assertEq(e.MODULE_ID(), MODULE_ID);
        assertEq(address(e.OPERATORS_DATA()), address(data));
    }

    function test_constructor_RevertWhen_ZeroModule() public {
        vm.expectRevert(ICuratedGate.ZeroModuleAddress.selector);
        new CuratedGate(address(0), MODULE_ID, address(data));
    }

    function test_constructor_RevertWhen_ZeroModuleId() public {
        vm.expectRevert(ICuratedGate.ZeroModuleId.selector);
        new CuratedGate(address(module), 0, address(data));
    }

    function test_constructor_RevertWhen_ZeroOperatorsData() public {
        vm.expectRevert(ICuratedGate.ZeroOperatorsDataAddress.selector);
        new CuratedGate(address(module), MODULE_ID, address(0));
    }
}

contract CuratedGateTest_initialize is CuratedGateTestBase {
    function test_initialize() public {
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
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
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(ICuratedGate.ZeroAdminAddress.selector);
        e.initialize(1, root, cid, address(0));
    }

    function test_initialize_RevertWhen_InvalidTreeRoot() public {
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(IMerkleGate.InvalidTreeRoot.selector);
        e.initialize(1, bytes32(0), cid, admin);
    }

    function test_initialize_RevertWhen_InvalidTreeCid() public {
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
            address(data)
        );
        _enableInitializers(address(e));
        vm.expectRevert(IMerkleGate.InvalidTreeCid.selector);
        e.initialize(1, root, "", admin);
    }

    function test_initialize_AllowsDefaultCurveId() public {
        CuratedGate e = new CuratedGate(
            address(module),
            MODULE_ID,
            address(data)
        );
        _enableInitializers(address(e));
        uint256 defaultCurveId = module.ACCOUNTING().DEFAULT_BOND_CURVE_ID();
        e.initialize(defaultCurveId, root, cid, admin);
        assertEq(e.curveId(), defaultCurveId);
    }
}

contract CuratedGateTest_setTreeParams is CuratedGateTestBase {
    function test_setTreeParams() public {
        bytes32 newRoot = keccak256(abi.encodePacked("root2"));
        string memory newCid = someCIDv0();

        vm.expectEmit(address(gate));
        emit IMerkleGate.TreeSet(newRoot, newCid);
        vm.prank(admin);
        gate.setTreeParams(newRoot, newCid);

        assertEq(gate.treeRoot(), newRoot);
        assertEq(keccak256(bytes(gate.treeCid())), keccak256(bytes(newCid)));
    }

    function test_setTreeParams_RevertWhen_NoRole() public {
        expectRoleRevert(stranger, gate.SET_TREE_ROLE());
        vm.prank(stranger);
        gate.setTreeParams(keccak256("x"), "cid");
    }

    function test_setTreeParams_RevertWhen_EmptyTreeRoot() public {
        vm.prank(admin);
        vm.expectRevert(IMerkleGate.InvalidTreeRoot.selector);
        gate.setTreeParams(bytes32(0), "cid");
    }

    function test_setTreeParams_RevertWhen_EmptyTreeCid() public {
        vm.prank(admin);
        vm.expectRevert(IMerkleGate.InvalidTreeCid.selector);
        gate.setTreeParams(keccak256("y"), "");
    }

    function test_setTreeParams_RevertWhen_SameTreeRoot() public {
        bytes32 root = gate.treeRoot();
        vm.prank(admin);
        vm.expectRevert(IMerkleGate.InvalidTreeRoot.selector);
        gate.setTreeParams(root, someCIDv0());
    }

    function test_setTreeParams_RevertWhen_SameTreeCid() public {
        string memory cid = gate.treeCid();
        vm.prank(admin);
        vm.expectRevert(IMerkleGate.InvalidTreeCid.selector);
        gate.setTreeParams(keccak256("z"), cid);
    }

    function test_setTreeParams_MakesNewMemberEligible() public {
        MerkleTree newTree = new MerkleTree();
        newTree.pushLeaf(abi.encode(stranger));
        newTree.pushLeaf(abi.encode(member2));
        bytes32 newRoot = newTree.root();
        string memory newCid = someCIDv0();
        bytes32[] memory proof = newTree.getProof(0);

        assertFalse(gate.verifyProof(stranger, proof));

        vm.prank(admin);
        gate.setTreeParams(newRoot, newCid);

        assertTrue(gate.verifyProof(stranger, proof));

        vm.prank(stranger);
        uint256 id = gate.createNodeOperator(
            "Name2",
            "Desc2",
            address(0),
            address(0),
            proof
        );

        assertEq(id, 0);
        assertTrue(gate.isConsumed(stranger));
    }
}

contract CuratedGateTest_getInitializedVersion is CuratedGateTestBase {
    function test_getInitializedVersion() public {
        assertEq(gate.getInitializedVersion(), 1);
    }
}

contract CuratedGateTest_hashLeaf is CuratedGateTestBase {
    function test_hashLeaf() public {
        bytes32 expected = keccak256(
            bytes.concat(keccak256(abi.encode(member)))
        );
        assertEq(gate.hashLeaf(member), expected);
    }
}

contract CuratedGateTest_pauseResume is CuratedGateTestBase {
    function test_pause_RevertWhen_NoRole() public {
        vm.expectRevert();
        gate.pauseFor(1);
    }

    function test_resume_RevertWhen_NoRole() public {
        vm.expectRevert();
        gate.resume();
    }

    function test_pause_HappyPath() public {
        vm.startPrank(admin);
        gate.grantRole(gate.PAUSE_ROLE(), admin);
        gate.pauseFor(1);
        vm.stopPrank();

        assertTrue(gate.isPaused());
    }

    function test_resume_HappyPath() public {
        vm.startPrank(admin);
        gate.grantRole(gate.PAUSE_ROLE(), admin);
        gate.grantRole(gate.RESUME_ROLE(), admin);
        gate.pauseFor(type(uint256).max);

        gate.resume();
        vm.stopPrank();

        assertFalse(gate.isPaused());
    }
}

contract CuratedGateTest_createNodeOperator is CuratedGateTestBase {
    function test_createNodeOperator() public {
        bytes32[] memory proof = tree.getProof(0);

        vm.expectCall(
            address(data),
            abi.encodeWithSelector(
                IOperatorsData.set.selector,
                MODULE_ID,
                0,
                OperatorInfo({
                    name: "Name",
                    description: "Description",
                    ownerEditsRestricted: false
                })
            )
        );
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.createNodeOperator.selector,
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
            abi.encodeWithSelector(IAccounting.setBondCurve.selector, 0, 1)
        );
        vm.expectEmit(address(gate));
        emit IMerkleGate.Consumed(member);
        vm.prank(member);
        uint256 id = gate.createNodeOperator(
            "Name",
            "Description",
            address(0x1111),
            address(0x2222),
            proof
        );

        assertEq(id, 0);
        assertTrue(gate.isConsumed(member));
    }

    function test_createNodeOperator_RevertWhen_InvalidProof() public {
        bytes32[] memory emptyProof;
        vm.prank(member);
        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        gate.createNodeOperator("N", "D", address(0), address(0), emptyProof);
    }

    function test_createNodeOperator_RevertWhen_AlreadyConsumed() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.prank(member);
        gate.createNodeOperator("A", "B", address(0), address(0), proof);

        vm.prank(member);
        vm.expectRevert(IMerkleGate.AlreadyConsumed.selector);
        gate.createNodeOperator("A", "B", address(0), address(0), proof);
    }

    function test_createNodeOperator_RevertWhen_NotMember() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.prank(stranger);
        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        gate.createNodeOperator("N", "D", address(0), address(0), proof);
    }

    function test_createNodeOperator_RevertWhen_Paused() public {
        bytes32[] memory proof = tree.getProof(0);
        vm.startPrank(admin);
        gate.grantRole(gate.PAUSE_ROLE(), admin);
        gate.pauseFor(1);
        vm.stopPrank();

        vm.prank(member);
        vm.expectRevert(PausableUntil.ResumedExpected.selector);
        gate.createNodeOperator("N", "D", address(0), address(0), proof);
    }
}

contract CuratedGateTest_createNodeOperator_DefaultCurve is
    CuratedGateTestBaseDefaultCurve
{
    function test_createNodeOperator_DoesNotSetCurveWhenDefault() public {
        bytes32[] memory proof = tree.getProof(0);

        expectNoCall(
            address(module.ACCOUNTING()),
            abi.encodeWithSelector(
                IAccounting.setBondCurve.selector,
                0,
                curveId()
            )
        );
        vm.expectCall(
            address(module),
            abi.encodeWithSelector(
                IBaseModule.createNodeOperator.selector,
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
            address(data),
            abi.encodeWithSelector(
                IOperatorsData.set.selector,
                MODULE_ID,
                0,
                OperatorInfo({
                    name: "Name",
                    description: "Description",
                    ownerEditsRestricted: false
                })
            )
        );

        vm.prank(member);
        uint256 id = gate.createNodeOperator(
            "Name",
            "Description",
            address(0x1111),
            address(0x2222),
            proof
        );

        assertEq(id, 0);
        assertTrue(gate.isConsumed(member));
    }
}

contract CuratedGateTest_recover is CuratedGateTestBase {
    function test_recoverEther_RevertWhen_NoRecovererRole() public {
        expectRoleRevert(stranger, gate.RECOVERER_ROLE());
        vm.prank(stranger);
        gate.recoverEther();
    }

    function test_recoverEther_HappyPath() public {
        uint256 amount = 1 ether;
        vm.deal(address(gate), amount);
        uint256 adminBalanceBefore = admin.balance;

        bytes32 role = gate.RECOVERER_ROLE();
        vm.prank(admin);
        gate.grantRole(role, admin);

        vm.expectEmit(address(gate));
        emit IAssetRecovererLib.EtherRecovered(admin, amount);

        vm.prank(admin);
        gate.recoverEther();

        assertEq(address(gate).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + amount);
    }
}
