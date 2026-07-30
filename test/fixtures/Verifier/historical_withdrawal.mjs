// Usage: node historical_withdrawal.mjs <fork_of_historical_withdrawal>

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType, concatGindices } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierHistoricalBase from "../../../out/VerifierHistorical.t.sol/VerifierHistoricalBase.json" assert { type: "json" };

const SLOTS_PER_HISTORICAL_ROOT = 8192;
const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;
const MAX_WITHDRAWALS = 16;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {string} opts.address - Ethereum address for the withdrawal credentials.
 * @param {number} opts.amount - Amount in gwei for the withdrawal.
 * @param {number} opts.withdrawableEpoch - Epoch used to calculate the slot for the withdrawable block.
 * @param {number} opts.withdrawalOffset - Offset of the withdrawal in the block.
 * @param {string} opts.fork - Fork from 'ssz' library.
 * @param {number} opts.capellaSlot - Slot of Cappela fork.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);
  assert(opts.withdrawalOffset < MAX_WITHDRAWALS);
  assert(["deneb", "electra"].includes(opts.fork));
  assert(opts.capellaSlot % SLOTS_PER_HISTORICAL_ROOT === 0);

  const faker = new Faker("seed sEed seEd");

  const LatestFork = ssz.fulu;
  /** @type {ssz.deneb | ssz.electra} */
  const WentByFork = ssz[opts.fork];

  const withdrawalState = WentByFork.BeaconState.defaultView();
  withdrawalState.slot = opts.withdrawableEpoch * SLOTS_PER_EPOCH;

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = WentByFork.BeaconState.getPathInfo(["validators", 0]).type;

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

  while (withdrawalState.validators.length < MAX_VALIDATORS) {
    withdrawalState.validators.push(Validator.defaultView());
  }
  withdrawalState.validators.set(opts.validatorIndex, validator);

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Withdrawal = WentByFork.BeaconBlock.getPathInfo([
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

  const withdrawalBlock = WentByFork.BeaconBlock.defaultView();

  while (withdrawalBlock.body.executionPayload.withdrawals.length < MAX_WITHDRAWALS) {
    withdrawalBlock.body.executionPayload.withdrawals.push(Withdrawal.defaultView());
  }
  withdrawalBlock.body.executionPayload.withdrawals.set(opts.withdrawalOffset, withdrawal);

  withdrawalState.latestExecutionPayloadHeader.withdrawalsRoot =
    withdrawalBlock.body.executionPayload.withdrawals.hashTreeRoot();

  withdrawalBlock.slot = withdrawalState.slot;
  withdrawalBlock.stateRoot = withdrawalState.hashTreeRoot();
  {
    const summaryIndex = Math.floor(withdrawalBlock.slot / SLOTS_PER_HISTORICAL_ROOT);
    const rootIndex = withdrawalBlock.slot % SLOTS_PER_HISTORICAL_ROOT;
    withdrawalBlock.meta = {
      summaryIndex,
      rootIndex,
    };
  }

  const validatorProof = createProof(withdrawalState.node, {
    type: ProofType.single,
    gindex: withdrawalState.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const pathFromStateToWithdrawals = withdrawalState.type.getPathInfo([
    "latestExecutionPayloadHeader",
    "withdrawalsRoot",
  ]);
  const withdrawals = withdrawalBlock.body.executionPayload.withdrawals;
  withdrawalState.tree.setNode(pathFromStateToWithdrawals.gindex, withdrawals.node);

  const withdrawalProof = createProof(withdrawalState.node, {
    type: ProofType.single,
    gindex: concatGindices([
      pathFromStateToWithdrawals.gindex,
      withdrawals.type.getPropertyGindex(opts.withdrawalOffset),
    ]),
  });

  const recentState = LatestFork.BeaconState.defaultView();
  recentState.slot = withdrawalState.slot + 0x421337;

  recentState.historicalSummaries.push(recentState.historicalSummaries.type.defaultView());

  for (let s = opts.capellaSlot; s < recentState.slot; s += SLOTS_PER_HISTORICAL_ROOT) {
    const summary = LatestFork.HistoricalSummary.defaultView();
    summary.blockSummaryRoot = faker.someBytes32();
    summary.stateSummaryRoot = faker.someBytes32();

    // This branch significantly improves performance.
    if (recentState.historicalSummaries.length == withdrawalBlock.meta.summaryIndex) {
      const BlockRoots = recentState.blockRoots.type;
      const blockRoots = BlockRoots.fromJson(
        new Array(8192).fill(faker.someBytes32().toString("hex")),
      );

      blockRoots[withdrawalBlock.meta.rootIndex] = withdrawalBlock.hashTreeRoot();

      const nav = recentState.type.getPathInfo([
        "historicalSummaries",
        recentState.historicalSummaries.length,
        "blockSummaryRoot",
      ]);
      summary.blockSummaryRoot = recentState.blockRoots.type.hashTreeRoot(blockRoots);
      summary.stateSummaryRoot = faker.someBytes32();
      recentState.historicalSummaries.push(summary);
      recentState.tree.setNode(nav.gindex, BlockRoots.toView(blockRoots).node);
    } else {
      recentState.historicalSummaries.push(summary);
    }
  }

  const withdrawalBlockProof = createProof(recentState.node, {
    type: ProofType.single,
    gindex: concatGindices([
      recentState.type.getPathInfo([
        "historicalSummaries",
        withdrawalBlock.meta.summaryIndex,
        "blockSummaryRoot",
      ]).gindex,
      recentState.blockRoots.type.getPropertyGindex(withdrawalBlock.meta.rootIndex),
    ]),
  });

  const recentBlock = LatestFork.BeaconBlock.defaultView();
  recentBlock.slot = recentState.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = recentState.hashTreeRoot();

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
        proof: withdrawalBlockProof.witnesses,
      },
    },
  };

  const ffi_interface = VerifierHistoricalBase.abi.find((e) => e.name == "ffi_interface");
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
  withdrawalOffset: 11,
  amount: 32e9,
  fork: process.argv[2],
  capellaSlot: 0,
});
