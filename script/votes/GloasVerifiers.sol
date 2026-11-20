// SPDX-FileCopyrightText: 2026 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { JsonBindings } from "../utils/JsonBindings.sol";

/// @dev Moves the verifier roles of the module and the CircuitBreaker pauser from `oldVerifier` to `newVerifier`.
struct VerifierSwap {
    address module;
    address circuitBreaker;
    address oldVerifier;
    address newVerifier;
    address pauser;
}

/// @dev The vote replacing the Verifiers of the modules with the Gloas-aware ones, a `VerifierSwap` per module
///      under `.<module>.verifier`.
library GloasVerifiers {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant NAME = "gloas-verifiers";

    function read(
        string memory json,
        string memory moduleKey
    ) internal view returns (bool found, VerifierSwap memory swap) {
        string memory key = _key(moduleKey);
        if (!vm.keyExistsJson(json, key)) return (false, swap);
        return (true, JsonBindings.deserializeVerifierSwap(json, key));
    }

    /// @dev Field by field, since `serializeJsonType` orders the keys at random in scripts.
    function write(string memory file, string memory moduleKey, VerifierSwap memory swap) internal {
        string memory key = _key(moduleKey);
        vm.writeJson(vm.toString(swap.module), file, string.concat(key, ".module"));
        vm.writeJson(vm.toString(swap.circuitBreaker), file, string.concat(key, ".circuitBreaker"));
        vm.writeJson(vm.toString(swap.oldVerifier), file, string.concat(key, ".oldVerifier"));
        vm.writeJson(vm.toString(swap.newVerifier), file, string.concat(key, ".newVerifier"));
        vm.writeJson(vm.toString(swap.pauser), file, string.concat(key, ".pauser"));
    }

    function _key(string memory moduleKey) private pure returns (string memory) {
        return string.concat(".", moduleKey, ".verifier");
    }
}
