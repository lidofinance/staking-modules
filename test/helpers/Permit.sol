// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.31;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// https://eips.ethereum.org/EIPS/eip-2612
contract PermitHelper {
    using ECDSA for bytes32;

    string internal STETH_NAME = "Liquid staked Ether 2.0";
    string internal STETH_VERSION = "2";

    string internal WSTETH_NAME = "Wrapped liquid staked Ether 2.0";
    string internal WSTETH_VERSION = "1";

    function stETHPermitDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        address token
    ) public view returns (bytes32) {
        return
            _preparePermitDigest(
                owner,
                spender,
                value,
                nonce,
                deadline,
                token,
                STETH_NAME,
                STETH_VERSION
            );
    }

    function wstETHPermitDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        address token
    ) public view returns (bytes32) {
        return
            _preparePermitDigest(
                owner,
                spender,
                value,
                nonce,
                deadline,
                token,
                WSTETH_NAME,
                WSTETH_VERSION
            );
    }

    // Prepare a permit digest for a specific ERC20 token
    function _preparePermitDigest(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        address token,
        string memory name,
        string memory version
    ) internal view returns (bytes32) {
        bytes32 encodeData = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                token
            )
        );

        // The final digest is created by prefixing the data with "\x19\x01" and hashing it
        return
            keccak256(
                abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, encodeData)
            );
    }
}
