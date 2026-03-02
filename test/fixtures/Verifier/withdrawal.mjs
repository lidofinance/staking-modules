// Usage: node withdrawal.mjs [withdrawal_offset=0] [amount_gwei=32e9]

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType, concatGindices } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierWithdrawalTest from "../../../out/Verifier.t.sol/VerifierWithdrawalTest.json" assert { type: "json" };

const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {string} opts.address - Ethereum address for the withdrawal credentials.
 * @param {number} opts.amount - Amount in gwei for the withdrawal.
 * @param {number} opts.withdrawableEpoch - Epoch used to calculate the slot for the withdrawable block.
 * @param {number} opts.withdrawalOffset - Offset of the withdrawal in the block.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);
  assert(opts.withdrawalOffset < 16);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const validator = Validator.defaultView();

  validator.slashed = false;
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

  const withdrawalBlock = Fork.BeaconBlock.defaultView();

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Withdrawal = Fork.BeaconBlock.getPathInfo([
    "body",
    "executionPayload",
    "withdrawals",
    0,
  ]).type;

  /** @type {import('@chainsafe/ssz').CompositeView} */
  const withdrawal = Withdrawal.defaultView();

  withdrawal.index = 42;
  withdrawal.validatorIndex = opts.validatorIndex;
  withdrawal.address = hexStrToBytesArr(opts.address);
  withdrawal.amount = BigInt(opts.amount);

  for (let i = 0; i != opts.withdrawalOffset; i++)
    withdrawalBlock.body.executionPayload.withdrawals.push(Withdrawal.defaultView());
  withdrawalBlock.body.executionPayload.withdrawals.push(withdrawal);

  state.latestExecutionPayloadHeader.withdrawalsRoot =
    withdrawalBlock.body.executionPayload.withdrawals.hashTreeRoot();

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const pathFromStateToWithdrawals = state.type.getPathInfo([
    "latestExecutionPayloadHeader",
    "withdrawalsRoot",
  ]);
  const withdrawals = withdrawalBlock.body.executionPayload.withdrawals;
  state.tree.setNode(pathFromStateToWithdrawals.gindex, withdrawals.node);

  const withdrawalProof = createProof(state.node, {
    type: ProofType.single,
    gindex: concatGindices([
      pathFromStateToWithdrawals.gindex,
      withdrawals.type.getPropertyGindex(opts.withdrawalOffset),
    ]),
  });

  withdrawalBlock.slot = state.slot;
  withdrawalBlock.parentRoot = faker.someBytes32();
  withdrawalBlock.stateRoot = state.hashTreeRoot();

  const fixture = {
    blockRoot: withdrawalBlock.hashTreeRoot(),
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
      withdrawal: {
        offset: opts.withdrawalOffset,
        object: {
          index: withdrawal.index,
          validatorIndex: opts.validatorIndex,
          withdrawalAddress: opts.address,
          amount: opts.amount,
        },
        proof: withdrawalProof.witnesses,
      },
      withdrawalBlock: {
        header: {
          slot: withdrawalBlock.slot,
          proposerIndex: withdrawalBlock.proposerIndex,
          parentRoot: withdrawalBlock.parentRoot,
          stateRoot: withdrawalBlock.stateRoot,
          bodyRoot: withdrawalBlock.body.hashTreeRoot(),
        },
        rootsTimestamp: 42,
      },
    },
  };

  const ffi_interface = VerifierWithdrawalTest.abi.find((e) => e.name == "ffi_interface");
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
  withdrawalOffset: parseInt(process.argv[2]) || 0,
  amount: Number(process.argv[3]) || 32e9,
});
