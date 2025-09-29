"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { concatGindices, createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import CSVerifierConsolidationTest from "../../../out/CSVerifier.t.sol/CSVerifierConsolidationTest.json" assert { type: "json" };

const MIN_VALIDATOR_WITHDRAWABILITY_DELAY = 256;
const SLOTS_PER_HISTORICAL_ROOT = 8192;
const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {number} opts.validatorIndex - Index of a validator in the `validators` list.
 * @param {number} opts.consolidationOffset - Index of a consolidation in the `pending_consolidations` list.
 * @param {bigint} opts.balance - Validator's balance before consolidation.
 * @param {string} opts.address - Ethereum address for withdrawal credentials.
 * @param {number} opts.withdrawableEpoch - Epoch to calculate slot for withdrawable block.
 * @param {number} opts.capellaSlot - Slot of Cappela fork.
 */
function main(opts) {
  assert(opts);
  assert(opts.validatorIndex < MAX_VALIDATORS);
  assert(opts.withdrawableEpoch > MIN_VALIDATOR_WITHDRAWABILITY_DELAY);
  assert(opts.capellaSlot % SLOTS_PER_HISTORICAL_ROOT == 0);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ListCompositeType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@chainsafe/ssz').ContainerType}  */
  const PendingConsolidation = Fork.BeaconState.getPathInfo(["pending_consolidations", 0]).type;

  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const validator = Validator.defaultView();

  validator.slashed = false;
  validator.pubkey = new Uint8Array(48).fill(18);
  validator.withdrawableEpoch = opts.withdrawableEpoch;
  validator.withdrawalCredentials = new Uint8Array([
    ...new Uint8Array([0x01]),
    ...new Uint8Array(11), // gap
    ...hexStrToBytesArr(opts.address),
  ]);

  const state = Fork.BeaconState.defaultView();

  while (state.validators.length < MAX_VALIDATORS) {
    state.validators.push(Validator.defaultView());
    state.balances.push(32e9);
  }

  // --- Consolidation block's state, the earliest state in the script.

  const consolidation = PendingConsolidation.defaultView();
  consolidation.sourceIndex = opts.validatorIndex;
  consolidation.targetIndex = opts.validatorIndex + 1;

  while (state.pendingConsolidations.length < opts.consolidationOffset) {
    state.pendingConsolidations.push(PendingConsolidation.defaultView());
  }

  state.balances.set(opts.validatorIndex, opts.balance);
  state.validators.set(opts.validatorIndex, validator);
  state.pendingConsolidations.push(consolidation);

  // We imagine that consolidation request was processed and the withdrawableEpoch was set without any delays.
  state.slot = (opts.withdrawableEpoch - MIN_VALIDATOR_WITHDRAWABILITY_DELAY) * SLOTS_PER_EPOCH;

  const consolidationBlock = Fork.BeaconBlock.defaultView();
  consolidationBlock.slot = state.slot;
  consolidationBlock.parentRoot = faker.someBytes32();
  consolidationBlock.stateRoot = state.hashTreeRoot();
  {
    const summaryIndex = Math.floor(consolidationBlock.slot / SLOTS_PER_HISTORICAL_ROOT);
    const rootIndex = consolidationBlock.slot % SLOTS_PER_HISTORICAL_ROOT;
    consolidationBlock.meta = {
      summaryIndex,
      rootIndex,
    };
  }

  const consolidationProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["pending_consolidations", opts.consolidationOffset]).gindex,
  });
  const balanceProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["balances", opts.validatorIndex]).gindex,
  });

  // --- "withdrawable" block's state.

  state.pendingConsolidations = state.pendingConsolidations.type.defaultView();
  state.slot = opts.withdrawableEpoch * SLOTS_PER_EPOCH;

  const withdrawableBlock = Fork.BeaconBlock.defaultView();
  withdrawableBlock.slot = state.slot;
  withdrawableBlock.parentRoot = faker.someBytes32();
  withdrawableBlock.stateRoot = state.hashTreeRoot();
  {
    const summaryIndex = Math.floor(withdrawableBlock.slot / SLOTS_PER_HISTORICAL_ROOT);
    const rootIndex = withdrawableBlock.slot % SLOTS_PER_HISTORICAL_ROOT;
    withdrawableBlock.meta = {
      summaryIndex,
      rootIndex,
    };
  }

  const validatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.validatorIndex]).gindex,
  });

  // --- Final state here, for the "recent" block.

  state.slot = (opts.withdrawableEpoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY) * SLOTS_PER_EPOCH;

  // We assume Cappela slot to be zero and fill in historical summaries list.
  for (let s = opts.capellaSlot; s < state.slot; s += SLOTS_PER_HISTORICAL_ROOT) {
    const summary = ssz.electra.HistoricalSummary.defaultView();
    summary.blockSummaryRoot = faker.someBytes32();
    summary.stateSummaryRoot = faker.someBytes32();

    const isSummaryWithConsolidationBlock = state.historicalSummaries.length == consolidationBlock.meta.summaryIndex;
    const isSummaryWithWithdrawableBlock = state.historicalSummaries.length == withdrawableBlock.meta.summaryIndex;
    const shouldPatchSummary = isSummaryWithConsolidationBlock || isSummaryWithWithdrawableBlock;

    // This branch significantly improves performance.
    if (shouldPatchSummary) {
      const BlockRoots = state.blockRoots.type;
      const blockRoots = BlockRoots.fromJson(new Array(8192).fill(faker.someBytes32().toString("hex")));

      if (isSummaryWithConsolidationBlock)
        blockRoots[consolidationBlock.meta.rootIndex] = consolidationBlock.hashTreeRoot();
      if (isSummaryWithWithdrawableBlock)
        blockRoots[withdrawableBlock.meta.rootIndex] = withdrawableBlock.hashTreeRoot();

      const nav = state.type.getPathInfo(["historicalSummaries", state.historicalSummaries.length, "blockSummaryRoot"]);
      summary.blockSummaryRoot = state.blockRoots.type.hashTreeRoot(blockRoots);
      summary.stateSummaryRoot = faker.someBytes32();
      state.historicalSummaries.push(summary);
      state.tree.setNode(nav.gindex, BlockRoots.toView(blockRoots).node);
    } else {
      state.historicalSummaries.push(summary);
    }
  }

  const consolidationBlockProof = createProof(state.node, {
    type: ProofType.single,
    gindex: concatGindices([
      state.type.getPathInfo(["historicalSummaries", consolidationBlock.meta.summaryIndex, "blockSummaryRoot"]).gindex,
      state.blockRoots.type.getPropertyGindex(consolidationBlock.meta.rootIndex),
    ]),
  });

  const withdrawableBlockProof = createProof(state.node, {
    type: ProofType.single,
    gindex: concatGindices([
      state.type.getPathInfo(["historicalSummaries", withdrawableBlock.meta.summaryIndex, "blockSummaryRoot"]).gindex,
      state.blockRoots.type.getPropertyGindex(withdrawableBlock.meta.rootIndex),
    ]),
  });

  const recentBlock = Fork.BeaconBlock.defaultView();
  recentBlock.slot = state.slot;
  recentBlock.parentRoot = faker.someBytes32();
  recentBlock.stateRoot = state.hashTreeRoot();

  const fixture = {
    blockRoot: recentBlock.hashTreeRoot(),
    balanceWei: opts.balance * 1e9,
    data: {
      consolidation: {
        object: {
          sourceIndex: consolidation.sourceIndex,
          targetIndex: consolidation.targetIndex,
        },
        offset: opts.consolidationOffset,
        proof: consolidationProof.witnesses,
      },
      validator: {
        index: opts.validatorIndex,
        nodeOperatorId: 0,
        keyIndex: 0,
        object: {
          pubkey: validator.pubkey,
          withdrawalCredentials: validator.withdrawalCredentials,
          effectiveBalance: opts.balance - (opts.balance % 1e18),
          slashed: false,
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
      withdrawableBlock: {
        header: {
          slot: withdrawableBlock.slot,
          proposerIndex: withdrawableBlock.proposerIndex,
          parentRoot: withdrawableBlock.parentRoot,
          stateRoot: withdrawableBlock.stateRoot,
          bodyRoot: withdrawableBlock.body.hashTreeRoot(),
        },
        proof: withdrawableBlockProof.witnesses,
      },
      consolidationBlock: {
        header: {
          slot: consolidationBlock.slot,
          proposerIndex: consolidationBlock.proposerIndex,
          parentRoot: consolidationBlock.parentRoot,
          stateRoot: consolidationBlock.stateRoot,
          bodyRoot: consolidationBlock.body.hashTreeRoot(),
        },
        proof: consolidationBlockProof.witnesses,
      },
    },
  };

  const ffi_interface = CSVerifierConsolidationTest.abi.find((e) => e.name == "ffi_interface");
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
  consolidationOffset: 1,
  balance: 31e9,
  address: "b3e29c46ee1745724417c0c51eb2351a1c01cf36",
  withdrawableEpoch: 100_500,
  capellaSlot: 0,
});
