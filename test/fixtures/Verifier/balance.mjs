// Usage: node balance.mjs [balance_gwei]

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierBalanceProofTest from "../../../out/Verifier.t.sol/VerifierBalanceProofTest.json" assert { type: "json" };

const SLOTS_PER_EPOCH = 32;
const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {bigint} opts.balanceGwei - The validator's balance in gwei.
 * @param {number} opts.epoch - Epoch for the state slot.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const validator = Validator.defaultView();

  validator.slashed = false;
  validator.pubkey = new Uint8Array(48).fill(18);
  validator.effectiveBalance = 32e9;
  validator.withdrawalCredentials = new Uint8Array([
    ...new Uint8Array([0x01]),
    ...new Uint8Array(11),
    ...hexStrToBytesArr("b3e29c46ee1745724417c0c51eb2351a1c01cf36"),
  ]);
  validator.exitEpoch = Number.MAX_SAFE_INTEGER;
  validator.withdrawableEpoch = Number.MAX_SAFE_INTEGER;

  const state = Fork.BeaconState.defaultView();
  state.slot = opts.epoch * SLOTS_PER_EPOCH;

  while (state.validators.length < MAX_VALIDATORS) {
    state.validators.push(Validator.defaultView());
  }
  state.validators.set(opts.validatorIndex, validator);

  while (state.balances.length < MAX_VALIDATORS) {
    state.balances.push(0);
  }
  state.balances.set(opts.validatorIndex, Number(opts.balanceGwei));

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const balanceProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["balances", opts.validatorIndex]).gindex,
  });

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = state.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = state.hashTreeRoot();

  const fixture = {
    blockRoot: recentBlock.hashTreeRoot(),
    data: {
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
      balance: {
        node: balanceProof.leaf,
        proof: balanceProof.witnesses,
      },
    },
  };

  const ffi_interface = VerifierBalanceProofTest.abi.find((e) => e.name == "ffi_interface");
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
  balanceGwei: BigInt(process.argv[2] || "64000000000"), // default 64 ETH in gwei
  epoch: 100_500,
});
