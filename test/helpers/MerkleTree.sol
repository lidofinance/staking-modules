// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.31;

/// @dev There's no leaves sorting for simplicity.
contract MerkleTree {
    bytes32[] internal tree;
    bytes32[] internal leaves;

    uint256 internal constant BUFFER_SIZE = 256;

    function root() external view returns (bytes32) {
        return tree.length == 0 ? bytes32(0) : tree[0];
    }

    function getProof(
        uint256 index
    ) public view returns (bytes32[] memory proof) {
        if (tree.length == 1) {
            return proof;
        }

        uint256 i = tree.length - 1 - index;
        uint256 proofLength = _log2(i + 1);
        proof = new bytes32[](proofLength);
        uint256 p = 0;

        while (i > 0) {
            if (i % 2 == 0) {
                proof[p] = tree[i - 1];
            } else {
                proof[p] = tree[i + 1];
            }
            i = (i - 1) / 2;
            p++;
        }

        return proof;
    }

    function getMultiProof(
        uint256[] memory indicies
    ) public view returns (bytes32[] memory proof, bool[] memory proofFlags) {
        uint256[] memory stack = new uint256[](BUFFER_SIZE);
        for (uint256 i; i < indicies.length; ++i) {
            stack[i] = tree.length - 1 - indicies[i];
        }
        uint256 stackPos;
        uint256 stackLen = indicies.length;

        proofFlags = new bool[](BUFFER_SIZE);
        uint256 proofFlagsLen;

        proof = new bytes32[](BUFFER_SIZE);
        uint256 proofLen;

        while (stackPos < stackLen && stack[stackPos] > 0) {
            uint256 j = stack[stackPos++];

            uint256 s = j % 2 == 0 ? j - 1 : j + 1;
            uint256 p = (j - 1) / 2;

            if (s == stack[stackPos]) {
                proofFlags[proofFlagsLen++] = true;
                stackPos++;
            } else {
                proofFlags[proofFlagsLen++] = false;
                proof[proofLen++] = tree[s];
            }

            stack[stackLen++] = p;
        }

        assembly ("memory-safe") {
            mstore(proofFlags, proofFlagsLen)
            mstore(proof, proofLen)
        }
    }

    function pushLeaf(bytes memory leafBytes) external {
        bytes32 leaf = this.hashLeaf(leafBytes);
        leaves.push(leaf);
        _buildTree();
    }

    function _buildTree() internal {
        delete tree;

        if (leaves.length == 1) {
            tree.push(leaves[0]);
            return;
        }

        for (uint256 i = 0; i < 2 * leaves.length - 1; ++i) {
            tree.push(bytes32(0));
        }

        for (uint256 i = 0; i < leaves.length; ++i) {
            tree[tree.length - 1 - i] = leaves[i];
        }

        for (uint256 i = tree.length - 1 - leaves.length; ; --i) {
            tree[i] = _hashPair(tree[2 * i + 1], tree[2 * i + 2]);

            if (i == 0) {
                break;
            }
        }
    }

    function _log2(uint256 x) private pure returns (uint256 y) {
        require(x != 0);
        while (x > 1) {
            x >>= 1;
            y += 1;
        }
        return y;
    }

    function hashLeaf(bytes memory d) external pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(d)));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return
            a < b
                ? keccak256(bytes.concat(a, b))
                : keccak256(bytes.concat(b, a));
    }
}
