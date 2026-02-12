// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { CuratedGate } from "src/CuratedGate.sol";
import { OperatorMetadata } from "src/interfaces/IMetaRegistry.sol";

import { MerkleTree } from "../../../helpers/MerkleTree.sol";
import { CuratedIntegrationBase } from "../common/ModuleTypeBase.sol";

contract CuratedGateCreateNodeOperatorTest is CuratedIntegrationBase {
    CuratedGate internal gate;

    function setUp() public {
        _setUpModule();

        assertGt(curatedGates.length, 0, "no curated gates");
        gate = CuratedGate(curatedGates[0]);

        address admin = gate.getRoleMember(gate.DEFAULT_ADMIN_ROLE(), 0);
        vm.startPrank(admin);
        gate.grantRole(gate.SET_TREE_ROLE(), address(this));
        gate.grantRole(gate.RESUME_ROLE(), address(this));
        vm.stopPrank();

        if (gate.isPaused()) gate.resume();
    }

    function test_createNodeOperator_setsMetadataAndCurve() public {
        address nodeOperator = nextAddress("NodeOperator");
        MerkleTree tree = new MerkleTree();
        tree.pushLeaf(abi.encode(nodeOperator));
        string memory cid = string.concat("cid-", vm.toString(uint256(uint160(nodeOperator))));
        gate.setTreeParams(tree.root(), cid);
        bytes32[] memory proof = tree.getProof(0);

        uint256 beforeCount = module.getNodeOperatorsCount();
        string memory name = "Operator";
        string memory description = "Curated operator";
        vm.prank(nodeOperator);
        uint256 noId = gate.createNodeOperator(name, description, address(0), address(0), proof);

        assertEq(module.getNodeOperatorsCount(), beforeCount + 1);

        OperatorMetadata memory info = metaRegistry.getOperatorMetadata(noId);
        assertEq(info.name, name);
        assertEq(info.description, description);
        assertEq(accounting.getBondCurveId(noId), gate.curveId());
        assertTrue(gate.isConsumed(nodeOperator));
    }
}
