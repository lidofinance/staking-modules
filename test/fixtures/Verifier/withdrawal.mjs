// Usage: node withdrawal.mjs [withdrawal_offset=0] [amount_gwei=32e9] [fork=electra]

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType, concatGindices } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierWithdrawalTest from "../../../out/Verifier.t.sol/VerifierWithdrawalTest.json" assert { type: "json" };

const SLOTS_PER_EPOCH = 32;
const SLOTS_PER_HISTORICAL_ROOT = 8192;

const MAX_VALIDATORS = 1_000;
const MAX_WITHDRAWALS = 16;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {string} opts.address - Ethereum address for the withdrawal credentials.
 * @param {number} opts.amount - Amount in gwei for the withdrawal.
 * @param {string} opts.fork - Fork from the `ssz` library.
 * @param {number} opts.withdrawableEpoch - Epoch used to calculate the slot for the withdrawable block.
 * @param {number} opts.withdrawalOffset - Offset of the withdrawal in the block.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);
  assert(opts.withdrawalOffset < MAX_WITHDRAWALS);
  assert(["electra", "gloas"].includes(opts.fork));

  const faker = new Faker("seed sEed seEd");
  const Fork = ssz[opts.fork];

  // -------------------------------------------------------------------------
  // Withdrawal block: validator + withdrawal pinned in its own state.
  // -------------------------------------------------------------------------

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

  const withdrawalState = Fork.BeaconState.defaultView();
  withdrawalState.slot = opts.withdrawableEpoch * SLOTS_PER_EPOCH;

  withdrawalState.validators = withdrawalState.validators.type.toView(
    Array.from({ length: MAX_VALIDATORS }, () => Validator.defaultValue()),
  );
  withdrawalState.validators.set(opts.validatorIndex, validator);

  const withdrawalBlock = Fork.BeaconBlock.defaultView();

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Withdrawal = Fork.Withdrawals.elementType;

  const withdrawal = Withdrawal.defaultValue();

  withdrawal.index = 42;
  withdrawal.validatorIndex = opts.validatorIndex;
  withdrawal.address = hexStrToBytesArr(opts.address);
  withdrawal.amount = BigInt(opts.amount);

  const withdrawalValues = Array.from({ length: opts.withdrawalOffset }, () =>
    Withdrawal.defaultValue(),
  );
  withdrawalValues.push(withdrawal);
  const withdrawals = Fork.Withdrawals.toView(withdrawalValues);

  let pathFromStateToWithdrawals;
  if (opts.fork === "gloas") {
    withdrawalState.payloadExpectedWithdrawals = withdrawals;
    pathFromStateToWithdrawals = withdrawalState.type.getPathInfo(["payloadExpectedWithdrawals"]);
  } else {
    withdrawalBlock.body.executionPayload.withdrawals = withdrawals;
    withdrawalState.latestExecutionPayloadHeader.withdrawalsRoot = withdrawals.hashTreeRoot();
    pathFromStateToWithdrawals = withdrawalState.type.getPathInfo([
      "latestExecutionPayloadHeader",
      "withdrawalsRoot",
    ]);
    withdrawalState.tree.setNode(pathFromStateToWithdrawals.gindex, withdrawals.node);
  }

  const validatorProof = createProof(withdrawalState.node, {
    type: ProofType.single,
    gindex: withdrawalState.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const withdrawalProof = createProof(withdrawalState.node, {
    type: ProofType.single,
    gindex: concatGindices([
      pathFromStateToWithdrawals.gindex,
      withdrawals.type.getPropertyGindex(opts.withdrawalOffset),
    ]),
  });

  withdrawalBlock.slot = withdrawalState.slot;
  withdrawalBlock.parentRoot = faker.someBytes32();
  withdrawalBlock.stateRoot = withdrawalState.hashTreeRoot();

  // -------------------------------------------------------------------------
  // Recent block: only thing we need from its state is a populated entry in
  // the `block_roots` ring buffer pointing at the withdrawal block root.
  // -------------------------------------------------------------------------

  const rootIndex = withdrawalBlock.slot % SLOTS_PER_HISTORICAL_ROOT;

  const recentState = Fork.BeaconState.defaultView();
  recentState.slot = withdrawalBlock.slot + 1;
  recentState.blockRoots.set(rootIndex, withdrawalBlock.hashTreeRoot());

  const blockRootsProof = createProof(recentState.node, {
    type: ProofType.single,
    gindex: recentState.type.getPathInfo(["blockRoots", rootIndex]).gindex,
  });

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = recentState.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = recentState.hashTreeRoot();

  // -------------------------------------------------------------------------
  // Assemble fixture in the shape expected by ProcessWithdrawalInput.
  // -------------------------------------------------------------------------

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
      withdrawalBlock: {
        header: {
          slot: withdrawalBlock.slot,
          proposerIndex: withdrawalBlock.proposerIndex,
          parentRoot: withdrawalBlock.parentRoot,
          stateRoot: withdrawalBlock.stateRoot,
          bodyRoot: withdrawalBlock.body.hashTreeRoot(),
        },
        proof: blockRootsProof.witnesses,
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
  fork: process.argv[4] || "electra",
});
