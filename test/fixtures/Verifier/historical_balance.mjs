// Usage: node historical_balance.mjs <fork> [balance_gwei]

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { createProof, ProofType, concatGindices } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierHistoricalBalanceTest from "../../../out/VerifierHistorical.t.sol/VerifierHistoricalBalanceTest.json" assert { type: "json" };

const SLOTS_PER_HISTORICAL_ROOT = 8192;
const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex
 * @param {bigint} opts.balanceGwei
 * @param {string} opts.fork - Fork from 'ssz' library.
 * @param {number} opts.epoch
 * @param {number} opts.capellaSlot
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);
  assert(["deneb", "electra"].includes(opts.fork));
  assert(opts.capellaSlot % SLOTS_PER_HISTORICAL_ROOT === 0);

  const faker = new Faker("seed sEed seEd");

  const LatestFork = ssz.fulu;
  /** @type {ssz.deneb | ssz.electra} */
  const HistoricalFork = ssz[opts.fork];

  const historicalState = HistoricalFork.BeaconState.defaultView();
  historicalState.slot = opts.epoch * SLOTS_PER_EPOCH;

  /** @type {import('@chainsafe/ssz').ContainerType} */
  const Validator = HistoricalFork.BeaconState.getPathInfo(["validators", 0]).type;

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

  while (historicalState.validators.length < MAX_VALIDATORS) {
    historicalState.validators.push(Validator.defaultView());
  }
  historicalState.validators.set(opts.validatorIndex, validator);

  while (historicalState.balances.length < MAX_VALIDATORS) {
    historicalState.balances.push(0);
  }
  historicalState.balances.set(opts.validatorIndex, Number(opts.balanceGwei));

  const validatorProof = createProof(historicalState.node, {
    type: ProofType.single,
    gindex: historicalState.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  const balanceProof = createProof(historicalState.node, {
    type: ProofType.single,
    gindex: historicalState.type.getPathInfo(["balances", opts.validatorIndex]).gindex,
  });

  const historicalBlock = HistoricalFork.BeaconBlock.defaultView();
  historicalBlock.slot = historicalState.slot;
  historicalBlock.stateRoot = historicalState.hashTreeRoot();

  const summaryIndex = Math.floor(historicalBlock.slot / SLOTS_PER_HISTORICAL_ROOT);
  const rootIndex = historicalBlock.slot % SLOTS_PER_HISTORICAL_ROOT;

  const recentState = LatestFork.BeaconState.defaultView();
  recentState.slot = historicalState.slot + 0x421337;

  recentState.historicalSummaries.push(recentState.historicalSummaries.type.defaultView());

  for (let s = opts.capellaSlot; s < recentState.slot; s += SLOTS_PER_HISTORICAL_ROOT) {
    const summary = LatestFork.HistoricalSummary.defaultView();
    summary.blockSummaryRoot = faker.someBytes32();
    summary.stateSummaryRoot = faker.someBytes32();

    // This branch significantly improves performance.
    if (recentState.historicalSummaries.length == summaryIndex) {
      const BlockRoots = recentState.blockRoots.type;
      const blockRoots = BlockRoots.fromJson(
        new Array(8192).fill(faker.someBytes32().toString("hex")),
      );

      blockRoots[rootIndex] = historicalBlock.hashTreeRoot();

      summary.blockSummaryRoot = recentState.blockRoots.type.hashTreeRoot(blockRoots);
      summary.stateSummaryRoot = faker.someBytes32();

      // Patching the state tree.
      const nav = recentState.type.getPathInfo([
        "historicalSummaries",
        recentState.historicalSummaries.length,
        "blockSummaryRoot",
      ]);
      recentState.historicalSummaries.push(summary);
      recentState.tree.setNode(nav.gindex, BlockRoots.toView(blockRoots).node);
    } else {
      recentState.historicalSummaries.push(summary);
    }
  }

  const historicalBlockProof = createProof(recentState.node, {
    type: ProofType.single,
    gindex: concatGindices([
      recentState.type.getPathInfo(["historicalSummaries", summaryIndex, "blockSummaryRoot"])
        .gindex,
      recentState.blockRoots.type.getPropertyGindex(rootIndex),
    ]),
  });

  const recentBlock = LatestFork.BeaconBlock.defaultView();
  recentBlock.slot = recentState.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = recentState.hashTreeRoot();

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
      historicalBlock: {
        header: {
          slot: historicalBlock.slot,
          proposerIndex: historicalBlock.proposerIndex,
          parentRoot: historicalBlock.parentRoot,
          stateRoot: historicalBlock.stateRoot,
          bodyRoot: historicalBlock.body.hashTreeRoot(),
        },
        proof: historicalBlockProof.witnesses,
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

  const ffi_interface = VerifierHistoricalBalanceTest.abi.find((e) => e.name == "ffi_interface");
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
  balanceGwei: BigInt(process.argv[3] || "64000000000"),
  fork: process.argv[2],
  epoch: 100_500,
  capellaSlot: 0,
});
