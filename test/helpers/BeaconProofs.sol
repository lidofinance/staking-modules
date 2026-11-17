// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { BeaconBlockHeader, Slot, Validator, Withdrawal } from "src/lib/Types.sol";

/// @notice Beacon state proofs for verifiers deployed on a fork. The fork has no consensus layer, so the proofs come
///         from synthetic beacon states built by `test/fixtures/BeaconProofs/*.mjs`. The block roots of these states
///         are written to the EIP-4788 contract.
library BeaconProofs {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // See `BEACON_ROOTS_ADDRESS` and `HISTORY_BUFFER_LENGTH` in the EIP-4788.
    address internal constant BEACON_ROOTS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;
    uint256 internal constant HISTORY_BUFFER_LENGTH = 8191;

    enum ValidatorStatus {
        Active,
        Slashed,
        // Reached the withdrawable epoch, the balance is swept by a full withdrawal in the block.
        Withdrawn
    }

    struct ValidatorProof {
        bytes32 blockRoot;
        BeaconBlockHeader header;
        uint64 validatorIndex;
        Validator validator;
        bytes32[] validatorProof;
        bytes32 balanceNode;
        bytes32[] balanceProof;
        // Empty unless the validator is withdrawn.
        uint8 withdrawalOffset;
        Withdrawal withdrawal;
        bytes32[] withdrawalProof;
    }

    /// @dev Used by `test/fixtures/BeaconProofs/validator.mjs` to encode the proof.
    function ffi_interface(ValidatorProof memory) external pure {}

    /// @dev Returns proofs of a validator with `pubkey` and its `balance` in a state at `slot`.
    ///      The root of the block is available at the current block timestamp.
    function validatorProof(
        bytes memory pubkey,
        address withdrawalAddress,
        Slot slot,
        uint256 balance,
        ValidatorStatus status
    ) internal returns (ValidatorProof memory proof) {
        string[] memory statuses = new string[](3);
        statuses[uint256(ValidatorStatus.Active)] = "active";
        statuses[uint256(ValidatorStatus.Slashed)] = "slashed";
        statuses[uint256(ValidatorStatus.Withdrawn)] = "withdrawn";

        string[] memory args = new string[](5);
        args[0] = vm.toString(pubkey);
        args[1] = vm.toString(withdrawalAddress);
        args[2] = vm.toString(Slot.unwrap(slot));
        args[3] = vm.toString(balance / 1 gwei);
        args[4] = statuses[uint256(status)];

        proof = abi.decode(_runFixtureScript("test/fixtures/BeaconProofs/validator.mjs", args), (ValidatorProof));
        _setBeaconRoot(proof.blockRoot);
    }

    function _runFixtureScript(string memory script, string[] memory args) private returns (bytes memory) {
        string[] memory cmd = new string[](args.length + 3);
        cmd[0] = "node";
        cmd[1] = "--no-warnings";
        cmd[2] = script;
        for (uint256 i; i < args.length; ++i) {
            cmd[i + 3] = args[i];
        }
        return vm.ffi(cmd);
    }

    function _setBeaconRoot(bytes32 root) private {
        // The EIP-4788 contract keeps the timestamp and the root in a ring buffer.
        uint256 bufferIndex = block.timestamp % HISTORY_BUFFER_LENGTH;
        vm.store(BEACON_ROOTS, bytes32(bufferIndex), bytes32(block.timestamp));
        vm.store(BEACON_ROOTS, bytes32(bufferIndex + HISTORY_BUFFER_LENGTH), root);
    }
}
