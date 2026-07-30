"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierSlashingTest from "../../../out/Verifier.t.sol/VerifierSlashingTest.json" assert { type: "json" };

const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {string} opts.address - Ethereum address for withdrawal credentials.
 * @param {number} opts.withdrawableEpoch - Epoch to calculate slot for withdrawable block.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ListCompositeType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const validator = Validator.defaultView();

  validator.slashed = true;
  validator.pubkey = new Uint8Array(48).fill(18);
  validator.effectiveBalance = 31e9;
  validator.withdrawableEpoch = opts.withdrawableEpoch;
  validator.withdrawalCredentials = new Uint8Array([
    ...new Uint8Array([0x01]),
    ...new Uint8Array(11), // gap
    ...hexStrToBytesArr(opts.address),
  ]);

  const state = Fork.BeaconState.defaultView();
  state.slot = opts.withdrawableEpoch * SLOTS_PER_EPOCH;

  while (state.validators.length < MAX_VALIDATORS) {
    state.validators.push(Validator.defaultView());
  }
  state.validators.set(opts.validatorIndex, validator);

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = state.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = state.hashTreeRoot();

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const fixture = {
    blockRoot: recentBlock.hashTreeRoot(),
    data: {
      validator: {
        index: opts.validatorIndex,
        nodeOperatorId: 0,
        keyIndex: 0,
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

  const ffi_interface = VerifierSlashingTest.abi.find((e) => e.name == "ffi_interface");
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
  validatorIndex: 17,
  address: "b3e29c46ee1745724417c0c51eb2351a1c01cf36",
  withdrawableEpoch: 100_500,
});
