// Usage: node validator.mjs <pubkey> <withdrawal_address> <slot> <balance_gwei> <active|slashed|withdrawn>
//
// Builds a beacon state with a single validator and provides proofs of the validator and its balance. A withdrawn
// validator has its balance swept by a full withdrawal in the block, with a proof of the withdrawal.
// Used by `BeaconProofs.mockBeaconRootAndGetValidatorProof`: the key, the withdrawal address and the slot come from
// the forked deployment.

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { concatGindices, createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import BeaconProofs from "../../../out/BeaconProofs.sol/BeaconProofs.json" with { type: "json" };

const SLOTS_PER_EPOCH = 32;
const EPOCHS_PER_SLASHINGS_VECTOR = 8192;
const MIN_VALIDATOR_WITHDRAWABILITY_DELAY = 256;
const MAX_EFFECTIVE_BALANCE_GWEI = 2048e9;
const EFFECTIVE_BALANCE_INCREMENT_GWEI = 1e9;
const COMPOUNDING_WITHDRAWAL_PREFIX = 0x02;

const VALIDATOR_INDEX = 17;
const WITHDRAWAL_INDEX = 42;
const WITHDRAWAL_OFFSET = 0;
const Fork = ssz.fulu;

/**
 * @param {Object} opts
 * @param {string} opts.pubkey - Validator's public key, 0x-prefixed.
 * @param {string} opts.withdrawalAddress - Address for the withdrawal credentials, 0x-prefixed.
 * @param {number} opts.slot - Slot of the state.
 * @param {number} opts.balanceGwei - The validator's balance in gwei.
 * @param {"active"|"slashed"|"withdrawn"} opts.status - Status of the validator.
 */
function main(opts) {
  assert(opts);
  assert(["active", "slashed", "withdrawn"].includes(opts.status));

  const faker = new Faker("seed sEed seEd");
  const stateEpoch = Math.floor(opts.slot / SLOTS_PER_EPOCH);

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const validator = Validator.defaultView();

  validator.slashed = opts.status == "slashed";
  validator.pubkey = hexStrToBytesArr(opts.pubkey);
  validator.effectiveBalance = Math.min(
    opts.balanceGwei - (opts.balanceGwei % EFFECTIVE_BALANCE_INCREMENT_GWEI),
    MAX_EFFECTIVE_BALANCE_GWEI,
  );
  validator.withdrawalCredentials = new Uint8Array([
    COMPOUNDING_WITHDRAWAL_PREFIX,
    ...new Uint8Array(11), // gap
    ...hexStrToBytesArr(opts.withdrawalAddress),
  ]);
  validator.activationEligibilityEpoch = 1;
  validator.activationEpoch = 2;
  validator.exitEpoch = Number.MAX_SAFE_INTEGER;
  validator.withdrawableEpoch = Number.MAX_SAFE_INTEGER;
  if (opts.status == "slashed") {
    // A slashed validator is exited and becomes withdrawable after the slashings vector.
    validator.exitEpoch = stateEpoch;
    validator.withdrawableEpoch = stateEpoch + EPOCHS_PER_SLASHINGS_VECTOR;
  }
  if (opts.status == "withdrawn") {
    // The validator becomes withdrawable exactly at the epoch of the state.
    validator.exitEpoch = stateEpoch - MIN_VALIDATOR_WITHDRAWABILITY_DELAY;
    validator.withdrawableEpoch = stateEpoch;
  }

  const state = Fork.BeaconState.defaultView();
  state.slot = opts.slot;
  assert(stateEpoch - MIN_VALIDATOR_WITHDRAWABILITY_DELAY > validator.activationEpoch);

  while (state.validators.length <= VALIDATOR_INDEX) {
    state.validators.push(Validator.defaultView());
    state.balances.push(0);
  }
  state.validators.set(VALIDATOR_INDEX, validator);
  // The withdrawal sweeps the whole balance.
  state.balances.set(VALIDATOR_INDEX, opts.status == "withdrawn" ? 0 : opts.balanceGwei);

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = state.slot;
  recentBlock.parentRoot = faker.someBytes32();

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Withdrawal = Fork.BeaconBlock.getPathInfo([
    "body",
    "executionPayload",
    "withdrawals",
    0,
  ]).type;
  const withdrawal = Withdrawal.defaultView();
  let withdrawalProof = { witnesses: [] };

  if (opts.status == "withdrawn") {
    withdrawal.index = WITHDRAWAL_INDEX;
    withdrawal.validatorIndex = VALIDATOR_INDEX;
    withdrawal.address = hexStrToBytesArr(opts.withdrawalAddress);
    withdrawal.amount = BigInt(opts.balanceGwei);

    const withdrawals = recentBlock.body.executionPayload.withdrawals;
    for (let i = 0; i != WITHDRAWAL_OFFSET; i++) withdrawals.push(Withdrawal.defaultView());
    withdrawals.push(withdrawal);

    // The state keeps the root of the withdrawals of the latest block. Attach the list itself to prove its items.
    const withdrawalsRootPath = state.type.getPathInfo([
      "latestExecutionPayloadHeader",
      "withdrawalsRoot",
    ]);
    state.latestExecutionPayloadHeader.withdrawalsRoot = withdrawals.hashTreeRoot();
    state.tree.setNode(withdrawalsRootPath.gindex, withdrawals.node);

    withdrawalProof = createProof(state.node, {
      type: ProofType.single,
      gindex: concatGindices([
        withdrawalsRootPath.gindex,
        withdrawals.type.getPropertyGindex(WITHDRAWAL_OFFSET),
      ]),
    });
  }

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", VALIDATOR_INDEX]).gindex,
  });

  const balanceProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["balances", VALIDATOR_INDEX]).gindex,
  });

  recentBlock.stateRoot = state.hashTreeRoot();

  const proof = {
    blockRoot: recentBlock.hashTreeRoot(),
    header: {
      slot: recentBlock.slot,
      proposerIndex: recentBlock.proposerIndex,
      parentRoot: recentBlock.parentRoot,
      stateRoot: recentBlock.stateRoot,
      bodyRoot: recentBlock.body.hashTreeRoot(),
    },
    validatorIndex: VALIDATOR_INDEX,
    validator: {
      pubkey: validator.pubkey,
      withdrawalCredentials: validator.withdrawalCredentials,
      effectiveBalance: validator.effectiveBalance,
      slashed: validator.slashed,
      activationEligibilityEpoch: validator.activationEligibilityEpoch,
      activationEpoch: validator.activationEpoch,
      exitEpoch: validator.exitEpoch,
      withdrawableEpoch: validator.withdrawableEpoch,
    },
    validatorProof: validatorProof.witnesses,
    balanceNode: balanceProof.leaf,
    balanceProof: balanceProof.witnesses,
    withdrawalOffset: WITHDRAWAL_OFFSET,
    withdrawal: {
      index: withdrawal.index,
      validatorIndex: withdrawal.validatorIndex,
      withdrawalAddress: "0x" + Buffer.from(withdrawal.address).toString("hex"),
      amount: withdrawal.amount,
    },
    withdrawalProof: withdrawalProof.witnesses,
  };

  const ffi_interface = BeaconProofs.abi.find((e) => e.name == "ffi_interface");
  assert(ffi_interface);

  const calldata = encodeParameters(ffi_interface.inputs, [proof]);
  console.log(calldata);
}

/**
 * @param {string} s - 0x-prefixed hex string.
 * @returns {Uint8Array}
 */
function hexStrToBytesArr(s) {
  return Uint8Array.from(Buffer.from(s.replace(/^0x/, ""), "hex"));
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
  pubkey: process.argv[2],
  withdrawalAddress: process.argv[3],
  slot: Number(process.argv[4]),
  balanceGwei: Number(process.argv[5]),
  status: process.argv[6],
});
