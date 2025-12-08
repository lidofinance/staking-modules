// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

import { Test } from "forge-std/Test.sol";

import { Utilities } from "./Utilities.sol";
import { MerkleTree } from "./MerkleTree.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleTreeTest is Test, Utilities {
    MerkleTree internal tree;

    function setUp() public {
        tree = new MerkleTree();
    }

    function test_treeRoot() public {
        tree.pushLeaf(
            abi.encode(
                address(0x1111111111111111111111111111111111111111),
                5000000000000000000
            )
        );
        tree.pushLeaf(
            abi.encode(
                address(0x2222222222222222222222222222222222222222),
                2500000000000000000
            )
        );
        tree.pushLeaf(
            abi.encode(
                address(0x3333333333333333333333333333333333333333),
                3500000000000000000
            )
        );
        tree.pushLeaf(
            abi.encode(
                address(0x4444444444444444444444444444444444444444),
                4500000000000000000
            )
        );
        tree.pushLeaf(
            abi.encode(
                address(0x5555555555555555555555555555555555555555),
                5500000000000000000
            )
        );

        assertEq(
            tree.root(),
            0x3b75a59075b62bc3a8647c5e576c8464cde52c84890afbaffa0c7e312009bea9
        );
    }

    function test_treeWithSingleElement() public {
        bytes memory leaf0 = abi.encode(42);
        tree.pushLeaf(leaf0);
        bytes32[] memory proof = tree.getProof(0);
        bool isValid = MerkleProof.verify(
            proof,
            tree.root(),
            tree.hashLeaf(leaf0)
        );
        assertTrue(isValid);
        assertEq(tree.root(), tree.hashLeaf(leaf0));
    }

    function test_treeWithTwoElements() public {
        bytes32[] memory proof;
        bool isValid;

        bytes memory leaf0 = abi.encode(42);
        bytes memory leaf1 = abi.encode(17);
        tree.pushLeaf(leaf0);
        tree.pushLeaf(leaf1);

        proof = tree.getProof(0);
        isValid = MerkleProof.verify(proof, tree.root(), tree.hashLeaf(leaf0));
        assertTrue(isValid);

        proof = tree.getProof(1);
        isValid = MerkleProof.verify(proof, tree.root(), tree.hashLeaf(leaf1));
        assertTrue(isValid);

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = tree.hashLeaf(leaf0);
        leaves[1] = tree.hashLeaf(leaf1);

        bool[] memory proofFlags;
        (proof, proofFlags) = tree.getMultiProof(UintArr(0, 1));
        isValid = MerkleProof.multiProofVerify(
            proof,
            proofFlags,
            tree.root(),
            leaves
        );
        assertTrue(isValid);
    }

    function test_treeWithThreeElements() public {
        bytes32[] memory proof;
        bool isValid;

        bytes memory leaf0 = abi.encode(42);
        bytes memory leaf1 = abi.encode(17);
        bytes memory leaf2 = abi.encode(13);
        tree.pushLeaf(leaf0);
        tree.pushLeaf(leaf1);
        tree.pushLeaf(leaf2);

        proof = tree.getProof(0);
        isValid = MerkleProof.verify(proof, tree.root(), tree.hashLeaf(leaf0));
        assertTrue(isValid);

        proof = tree.getProof(1);
        isValid = MerkleProof.verify(proof, tree.root(), tree.hashLeaf(leaf1));
        assertTrue(isValid);

        proof = tree.getProof(2);
        isValid = MerkleProof.verify(proof, tree.root(), tree.hashLeaf(leaf2));
        assertTrue(isValid);

        bytes32[] memory leaves;
        bool[] memory proofFlags;

        {
            leaves = new bytes32[](2);
            leaves[0] = tree.hashLeaf(leaf0);
            leaves[1] = tree.hashLeaf(leaf1);

            (proof, proofFlags) = tree.getMultiProof(UintArr(0, 1));
            isValid = MerkleProof.multiProofVerify(
                proof,
                proofFlags,
                tree.root(),
                leaves
            );
            assertTrue(isValid);
        }

        {
            leaves = new bytes32[](2);
            leaves[0] = tree.hashLeaf(leaf1);
            leaves[1] = tree.hashLeaf(leaf2);

            (proof, proofFlags) = tree.getMultiProof(UintArr(1, 2));
            isValid = MerkleProof.multiProofVerify(
                proof,
                proofFlags,
                tree.root(),
                leaves
            );
            assertTrue(isValid);
        }

        {
            leaves = new bytes32[](2);
            leaves[0] = tree.hashLeaf(leaf0);
            leaves[1] = tree.hashLeaf(leaf2);

            (proof, proofFlags) = tree.getMultiProof(UintArr(0, 2));
            isValid = MerkleProof.multiProofVerify(
                proof,
                proofFlags,
                tree.root(),
                leaves
            );
            assertTrue(isValid);
        }

        {
            leaves = new bytes32[](3);
            leaves[0] = tree.hashLeaf(leaf0);
            leaves[1] = tree.hashLeaf(leaf1);
            leaves[2] = tree.hashLeaf(leaf2);

            (proof, proofFlags) = tree.getMultiProof(UintArr(0, 1, 2));
            isValid = MerkleProof.multiProofVerify(
                proof,
                proofFlags,
                tree.root(),
                leaves
            );
            assertTrue(isValid);
        }
    }
}
