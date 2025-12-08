// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "../../helpers/Utilities.sol";
import { DeploymentFixtures } from "../../helpers/Fixtures.sol";
import { MerkleTree } from "../../helpers/MerkleTree.sol";
import { VettedGate } from "../../../src/VettedGate.sol";

contract MiscTest is Test, Utilities, DeploymentFixtures {
    function setUp() public {
        Env memory env = envVars();
        vm.createSelectFork(env.RPC_URL);
        initializeFromDeployment();
    }
}

contract VettedGateFactoryTest is MiscTest {
    function test_deployNewVettedGate() public {
        MerkleTree merkleTree = new MerkleTree();
        merkleTree.pushLeaf(abi.encode(nextAddress()));

        uint256 curveId = 1;
        bytes32 root = merkleTree.root();
        string memory cid = "someOtherCid";

        vm.startSnapshotGas("VettedGateFactory.create");
        address instance = vettedGateFactory.create(
            curveId,
            root,
            cid,
            address(this)
        );
        vm.stopSnapshotGas();

        VettedGate gate = VettedGate(instance);
        assertEq(gate.curveId(), curveId);
        assertEq(address(gate.MODULE()), address(module));
        assertEq(gate.treeRoot(), root);
        assertEq(gate.treeCid(), cid);
        assertEq(gate.getRoleMemberCount(gate.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(gate.hasRole(gate.DEFAULT_ADMIN_ROLE(), address(this)));
    }
}
