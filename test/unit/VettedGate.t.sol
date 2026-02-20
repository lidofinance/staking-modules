// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { VettedGate } from "src/VettedGate.sol";
import { PausableUntil } from "src/lib/utils/PausableUntil.sol";
import { IVettedGate } from "src/interfaces/IVettedGate.sol";
import { IMerkleGate } from "src/interfaces/IMerkleGate.sol";
import { IBaseModule, NodeOperatorManagementProperties } from "src/interfaces/IBaseModule.sol";
import { IAccounting } from "src/interfaces/IAccounting.sol";

import { Utilities } from "../helpers/Utilities.sol";
import { MerkleTree } from "../helpers/MerkleTree.sol";
import { CSMMock } from "../helpers/mocks/CSMMock.sol";
import { Fixtures } from "../helpers/Fixtures.sol";

contract VettedGateTestBase is Test, Utilities, Fixtures {
    VettedGate internal vettedGate;
    CSMMock internal csm;

    address internal nodeOperator;
    address internal anotherNodeOperator;
    address internal stranger;
    address internal admin;
    uint256 internal curveId;
    MerkleTree internal merkleTree;
    bytes32 internal root;
    string internal cid;

    function setUp() public virtual {
        csm = new CSMMock();
        nodeOperator = nextAddress("NODE_OPERATOR");
        anotherNodeOperator = nextAddress("ANOTHER_NODE_OPERATOR");
        stranger = nextAddress("STRANGER");
        admin = nextAddress("ADMIN");

        merkleTree = new MerkleTree();
        merkleTree.pushLeaf(abi.encode(nodeOperator));
        merkleTree.pushLeaf(abi.encode(stranger));
        merkleTree.pushLeaf(abi.encode(anotherNodeOperator));
        root = merkleTree.root();
        cid = "someCid";

        curveId = 1;
        vettedGate = new VettedGate(address(csm));
        _enableInitializers(address(vettedGate));
        vettedGate.initialize(curveId, root, cid, admin);
    }

    function _addNodeOperator(
        address who,
        bytes32[] memory proof
    ) internal returns (uint256 nodeOperatorId, bytes memory keys, bytes memory signatures) {
        uint256 keysCount = 1;
        keys = randomBytes(48 * keysCount);
        signatures = randomBytes(96 * keysCount);

        vm.prank(who);
        nodeOperatorId = vettedGate.addNodeOperatorETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: proof,
            referrer: address(0)
        });
    }

    function _setNoOwner(address owner, bool extendedPermissions) internal {
        csm.mock_setNodeOperatorManagementProperties(
            NodeOperatorManagementProperties({
                managerAddress: owner,
                rewardAddress: owner,
                extendedManagerPermissions: extendedPermissions
            })
        );
    }
}

contract VettedGateTest_constructor is VettedGateTestBase {
    function test_constructor() public view {
        assertEq(address(vettedGate.MODULE()), address(csm));
        assertEq(address(vettedGate.ACCOUNTING()), address(csm.ACCOUNTING()));
    }

    function test_constructor_RevertWhen_ZeroModuleAddress() public {
        vm.expectRevert(IVettedGate.ZeroModuleAddress.selector);
        new VettedGate(address(0));
    }
}

contract VettedGateTest_initialize is VettedGateTestBase {
    function test_initialize() public {
        VettedGate gate = new VettedGate(address(csm));
        _enableInitializers(address(gate));

        vm.expectEmit();
        emit IMerkleGate.TreeSet(root, cid);
        gate.initialize(curveId, root, cid, admin);

        assertEq(gate.curveId(), curveId);
        assertEq(gate.treeRoot(), root);
        assertEq(keccak256(bytes(gate.treeCid())), keccak256(bytes(cid)));
        assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(gate.getRoleMember(gate.DEFAULT_ADMIN_ROLE(), 0), admin);
        assertEq(gate.getInitializedVersion(), 1);
    }

    function test_initialize_RevertWhen_InvalidCurveId() public {
        VettedGate gate = new VettedGate(address(csm));
        _enableInitializers(address(gate));
        uint256 defaultCurveId = csm.accounting().DEFAULT_BOND_CURVE_ID();

        vm.expectRevert(IVettedGate.InvalidCurveId.selector);
        gate.initialize(defaultCurveId, root, cid, admin);
    }

    function test_initialize_RevertWhen_InvalidTreeRoot() public {
        VettedGate gate = new VettedGate(address(csm));
        _enableInitializers(address(gate));

        vm.expectRevert(IMerkleGate.InvalidTreeRoot.selector);
        gate.initialize(curveId, bytes32(0), cid, admin);
    }

    function test_initialize_RevertWhen_InvalidTreeCid() public {
        VettedGate gate = new VettedGate(address(csm));
        _enableInitializers(address(gate));

        vm.expectRevert(IMerkleGate.InvalidTreeCid.selector);
        gate.initialize(curveId, root, "", admin);
    }

    function test_initialize_RevertWhen_ZeroAdminAddress() public {
        VettedGate gate = new VettedGate(address(csm));
        _enableInitializers(address(gate));

        vm.expectRevert(bytes4(keccak256("ZeroAdminAddress()")));
        gate.initialize(curveId, root, cid, address(0));
    }
}

contract VettedGateTest_pauseResume is VettedGateTestBase {
    function test_pauseFor() public {
        vm.startPrank(admin);
        vettedGate.grantRole(vettedGate.PAUSE_ROLE(), admin);

        vm.expectEmit(address(vettedGate));
        emit PausableUntil.Paused(100);
        vettedGate.pauseFor(100);
        vm.stopPrank();

        assertTrue(vettedGate.isPaused());
    }

    function test_pauseFor_revertWhen_NoRole() public {
        expectRoleRevert(admin, vettedGate.PAUSE_ROLE());
        vm.prank(admin);
        vettedGate.pauseFor(100);
    }

    function test_resume() public {
        vm.startPrank(admin);
        vettedGate.grantRole(vettedGate.PAUSE_ROLE(), admin);
        vettedGate.grantRole(vettedGate.RESUME_ROLE(), admin);
        vettedGate.pauseFor(100);

        vm.expectEmit(address(vettedGate));
        emit PausableUntil.Resumed();
        vettedGate.resume();
        vm.stopPrank();

        assertFalse(vettedGate.isPaused());
    }

    function test_resume_revertWhen_NoRole() public {
        expectRoleRevert(admin, vettedGate.RESUME_ROLE());
        vm.prank(admin);
        vettedGate.resume();
    }
}

contract VettedGateTest_merkle is VettedGateTestBase {
    function test_verifyProof() public view {
        assertTrue(vettedGate.verifyProof(nodeOperator, merkleTree.getProof(0)));
        assertFalse(vettedGate.verifyProof(stranger, merkleTree.getProof(0)));
    }

    function test_hashLeaf() public view {
        // keccak256(bytes.concat(keccak256(abi.encode(address(154))))) =
        // 0x0f7ac7a58332324fa3de7b7a4a05de303436d846e292fa579646a7496f0c2c1a
        assertEq(vettedGate.hashLeaf(address(154)), 0x0f7ac7a58332324fa3de7b7a4a05de303436d846e292fa579646a7496f0c2c1a);
    }

    function test_setTreeParams() public {
        MerkleTree newTree = new MerkleTree();
        newTree.pushLeaf(abi.encode(stranger));
        bytes32 newRoot = newTree.root();
        string memory newCid = "newCid";

        vm.startPrank(admin);
        vettedGate.grantRole(vettedGate.SET_TREE_ROLE(), admin);

        vm.expectEmit(address(vettedGate));
        emit IMerkleGate.TreeSet(newRoot, newCid);
        vettedGate.setTreeParams(newRoot, newCid);
        vm.stopPrank();

        assertEq(vettedGate.treeRoot(), newRoot);
        assertEq(keccak256(bytes(vettedGate.treeCid())), keccak256(bytes(newCid)));
    }
}

contract VettedGateTest_addNodeOperator is VettedGateTestBase {
    function test_addNodeOperatorETH() public {
        uint256 keysCount = 1;
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        address referrer = nextAddress("REFERRER");
        bytes32[] memory proof = merkleTree.getProof(0);

        NodeOperatorManagementProperties memory props = NodeOperatorManagementProperties({
            managerAddress: address(0x1111),
            rewardAddress: address(0x2222),
            extendedManagerPermissions: true
        });

        vm.expectCall(
            address(csm),
            abi.encodeWithSelector(IBaseModule.createNodeOperator.selector, nodeOperator, props, referrer)
        );
        vm.expectCall(address(csm.ACCOUNTING()), abi.encodeWithSelector(IAccounting.setBondCurve.selector, 0, curveId));
        vm.expectCall(
            address(csm),
            abi.encodeWithSelector(
                IBaseModule.addValidatorKeysETH.selector,
                nodeOperator,
                0,
                keysCount,
                keys,
                signatures
            )
        );

        vm.prank(nodeOperator);
        uint256 noId = vettedGate.addNodeOperatorETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: props,
            proof: proof,
            referrer: referrer
        });

        assertEq(noId, 0);
        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_addNodeOperatorETH_RevertWhen_InvalidProof() public {
        uint256 keysCount = 1;
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vm.prank(nodeOperator);
        vettedGate.addNodeOperatorETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: proof,
            referrer: address(0)
        });

        assertFalse(vettedGate.isConsumed(nodeOperator));
    }

    function test_addNodeOperatorETH_RevertWhen_AlreadyConsumed() public {
        bytes32[] memory proof = merkleTree.getProof(0);
        _addNodeOperator(nodeOperator, proof);

        vm.expectRevert(IMerkleGate.AlreadyConsumed.selector);
        vm.prank(nodeOperator);
        vettedGate.addNodeOperatorETH({
            keysCount: 1,
            publicKeys: randomBytes(48),
            signatures: randomBytes(96),
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            proof: proof,
            referrer: address(0)
        });
    }

    function test_addNodeOperatorStETH() public {
        uint256 keysCount = 1;
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectCall(
            address(csm),
            abi.encodeWithSelector(
                IBaseModule.addValidatorKeysStETH.selector,
                nodeOperator,
                0,
                keysCount,
                keys,
                signatures,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            )
        );

        vm.prank(nodeOperator);
        vettedGate.addNodeOperatorStETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 }),
            proof: proof,
            referrer: address(0)
        });

        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_addNodeOperatorWstETH() public {
        uint256 keysCount = 1;
        bytes memory keys = randomBytes(48 * keysCount);
        bytes memory signatures = randomBytes(96 * keysCount);
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectCall(
            address(csm),
            abi.encodeWithSelector(
                IBaseModule.addValidatorKeysWstETH.selector,
                nodeOperator,
                0,
                keysCount,
                keys,
                signatures,
                IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 })
            )
        );

        vm.prank(nodeOperator);
        vettedGate.addNodeOperatorWstETH({
            keysCount: keysCount,
            publicKeys: keys,
            signatures: signatures,
            managementProperties: NodeOperatorManagementProperties({
                managerAddress: address(0),
                rewardAddress: address(0),
                extendedManagerPermissions: false
            }),
            permit: IAccounting.PermitInput({ value: 0, deadline: 0, v: 0, r: 0, s: 0 }),
            proof: proof,
            referrer: address(0)
        });

        assertTrue(vettedGate.isConsumed(nodeOperator));
    }
}

contract VettedGateTest_claimBondCurve is VettedGateTestBase {
    function test_claimBondCurve() public {
        _setNoOwner(nodeOperator, false);
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectCall(address(csm.ACCOUNTING()), abi.encodeWithSelector(IAccounting.setBondCurve.selector, 0, curveId));

        vm.prank(nodeOperator);
        vettedGate.claimBondCurve(0, proof);

        assertTrue(vettedGate.isConsumed(nodeOperator));
    }

    function test_claimBondCurve_RevertWhen_NotAllowedToClaim() public {
        _setNoOwner(nodeOperator, false);
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectRevert(IVettedGate.NotAllowedToClaim.selector);
        vm.prank(stranger);
        vettedGate.claimBondCurve(0, proof);
    }

    function test_claimBondCurve_RevertWhen_NodeOperatorDoesNotExist() public {
        _setNoOwner(nodeOperator, false);
        bytes32[] memory proof = merkleTree.getProof(0);

        vm.expectRevert(IVettedGate.NodeOperatorDoesNotExist.selector);
        vm.prank(nodeOperator);
        vettedGate.claimBondCurve(1, proof);
    }

    function test_claimBondCurve_RevertWhen_InvalidProof() public {
        _setNoOwner(nodeOperator, false);
        bytes32[] memory proof = merkleTree.getProof(1);

        vm.expectRevert(IMerkleGate.InvalidProof.selector);
        vm.prank(nodeOperator);
        vettedGate.claimBondCurve(0, proof);
    }
}
