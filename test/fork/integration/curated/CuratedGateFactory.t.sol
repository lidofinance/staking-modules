// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CuratedGate } from "../../../../src/CuratedGate.sol";
import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract CuratedGateFactoryTest is CuratedIntegrationBase {
    function setUp() public {
        _setUpModule();
    }

    function test_createCuratedGate() public {
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(nextAddress()));
        bytes32 root = tree.root();
        string memory cid = "curatedCid";
        uint256 curveId = 1;
        address admin = nextAddress("GateAdmin");

        vm.startSnapshotGas("CuratedGateFactory.createCurated");
        address instance = curatedGateFactory.create(curveId, root, cid, admin);
        vm.stopSnapshotGas();

        CuratedGate gate = CuratedGate(instance);
        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(module));
        assertEq(address(gate.ACCOUNTING()), address(accounting));
        assertEq(address(gate.META_REGISTRY()), address(metaRegistry));
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);
        assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), admin));
    }
}
