// Usage: node withdrawn.mjs [validator=0]
//
// Builds a beacon state with several non-slashed validators that have reached their withdrawable epoch and provides
// a `ProcessWithdrawnInput` fixture for the selected one. See the `validators` list at the bottom of the file.

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import CuratedVerifierWithdrawnTest from "../../../out/CuratedVerifier.t.sol/CuratedVerifierWithdrawnTest.json" with { type: "json" };

const SLOTS_PER_EPOCH = 32;
const MIN_VALIDATOR_WITHDRAWABILITY_DELAY = 256;

const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {string} opts.address - Ethereum address for the withdrawal credentials.
 * @param {number} opts.stateEpoch - Epoch of the recent block's state.
 * @param {Array<{index: number, nodeOperatorId: number, keyIndex: number, credentialsPrefix: number, withdrawableEpoch: number, balanceGwei: number}>} opts.validators
 * @param {number} opts.selected - Position of the validator to provide the fixture for in the `validators` list.
 */
function main(opts) {
  assert(opts);
  assert(opts.selected < opts.validators.length);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  const state = Fork.BeaconState.defaultView();
  // A slot in the middle of the epoch to check the epoch computation.
  state.slot = opts.stateEpoch * SLOTS_PER_EPOCH + 7;

  while (state.validators.length < MAX_VALIDATORS) {
    state.validators.push(Validator.defaultView());
    state.balances.push(0);
  }

  const validators = opts.validators.map((v, i) => {
    assert(v.index < MAX_VALIDATORS);
    assert(v.withdrawableEpoch <= opts.stateEpoch);

    /** @type {import('@lodestar/types/lib/phase0').Validator} */
    const validator = Validator.defaultView();

    validator.slashed = false;
    validator.pubkey = new Uint8Array(48).fill(18 + i);
    validator.effectiveBalance = 32e9;
    validator.activationEligibilityEpoch = 1;
    validator.activationEpoch = 2;
    validator.exitEpoch = v.withdrawableEpoch - MIN_VALIDATOR_WITHDRAWABILITY_DELAY;
    validator.withdrawableEpoch = v.withdrawableEpoch;
    validator.withdrawalCredentials = new Uint8Array([
      ...new Uint8Array([v.credentialsPrefix]),
      ...new Uint8Array(11), // gap
      ...hexStrToBytesArr(opts.address),
    ]);

    state.validators.set(v.index, validator);
    // The balance is either left for the sweep or has been moved to the consolidation target. It's not proven.
    state.balances.set(v.index, v.balanceGwei);

    return { ...v, validator };
  });

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = state.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = state.hashTreeRoot();

  const { index, nodeOperatorId, keyIndex, validator } = validators[opts.selected];

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", index]).gindex,
  });

  const fixture = {
    blockRoot: recentBlock.hashTreeRoot(),
    data: {
      validator: {
        index,
        nodeOperatorId,
        keyIndex,
        object: {
          pubkey: validator.pubkey,
          withdrawalCredentials: validator.withdrawalCredentials,
          effectiveBalance: validator.effectiveBalance,
          slashed: validator.slashed,
          activationEligibilityEpoch: validator.activationEligibilityEpoch,
          activationEpoch: validator.activationEpoch,
          exitEpoch: validator.exitEpoch,
          withdrawableEpoch: validator.withdrawableEpoch,
        },
        proof: validatorProof.witnesses,
      },
      recentBlock: {
        header: {
          slot: recentBlock.slot,
          proposerIndex: recentBlock.proposerIndex,
          parentRoot: recentBlock.parentRoot,
          stateRoot: recentBlock.stateRoot,
          bodyRoot: recentBlock.body.hashTreeRoot(),
        },
        rootsTimestamp: 42,
      },
    },
  };

  const ffi_interface = CuratedVerifierWithdrawnTest.abi.find((e) => e.name == "ffi_interface");
  assert(ffi_interface);

  const calldata = encodeParameters(ffi_interface.inputs, [fixture]);
  console.log(calldata);
}

/**
 * @param {string} s
 * @returns {Uint8Array}
 */
function hexStrToBytesArr(s) {
  return Uint8Array.from(s.match(/.{1,2}/g).map((byte) => parseInt(byte, 16)));
}

class Faker {
  /**
   * @param {string|Buffer|Uint8Array} seed
   */
  constructor(seed) {
    this.seed = Buffer.from(seed);
  }

  /**
   * @returns {Buffer}
   */
  someBytes32() {
    const hash = createHash("sha256").update(this.seed).digest();
    this.seed = hash;
    return hash;
  }
}

main({
  address: "b3e29c46ee1745724417c0c51eb2351a1c01cf36",
  stateEpoch: 100_500,
  validators: [
    // An exited validator with the balance left for the sweep.
    {
      index: 17,
      nodeOperatorId: 0,
      keyIndex: 0,
      credentialsPrefix: 0x02,
      withdrawableEpoch: 100_495,
      balanceGwei: 33e9,
    },
    // A consolidated source: the effective balance has been moved to the target, the excess is left for the sweep.
    {
      index: 42,
      nodeOperatorId: 1,
      keyIndex: 3,
      credentialsPrefix: 0x02,
      withdrawableEpoch: 99_000,
      balanceGwei: 1e9,
    },
    // A validator reaching the withdrawable epoch exactly at the epoch of the state.
    {
      index: 513,
      nodeOperatorId: 0,
      keyIndex: 7,
      credentialsPrefix: 0x01,
      withdrawableEpoch: 100_500,
      balanceGwei: 32e9,
    },
  ],
  selected: Number(process.argv[2] || "0"),
});
