// Usage: node incoming_consolidation.mjs [balance] [effectiveBalance]

"use strict";

import assert from "node:assert";
import { createHash } from "crypto";

import { ssz } from "@lodestar/types";
import { concatGindices, createProof, ProofType } from "@chainsafe/persistent-merkle-tree";
import { encodeParameters } from "web3-eth-abi";

import VerifierModuleTargetConsolidationTest from "../../../out/Verifier.t.sol/VerifierModuleTargetConsolidationTest.json" with { type: "json" };

const MIN_VALIDATOR_WITHDRAWABILITY_DELAY = 256;
const SLOTS_PER_HISTORICAL_ROOT = 8192;
const SLOTS_PER_EPOCH = 32;

const MAX_VALIDATORS = 1_000;
const Fork = ssz.electra;

/**
 * @param {Object} opts
 * @param {number} opts.sourceValidatorIndex - Index of the source validator in the `validators` list.
 * @param {number} opts.targetValidatorIndex - Index of the target (module's) validator in the `validators` list.
 * @param {number} opts.consolidationOffset - Index of a consolidation in the `pending_consolidations` list.
 * @param {number} opts.balance - Source validator's balance before consolidation.
 * @param {number} opts.effectiveBalance - Source validator's effective balance.
 * @param {string} opts.address - Ethereum address for withdrawal credentials.
 * @param {number} opts.withdrawableEpoch - Epoch to calculate slot for withdrawable block.
 * @param {number} opts.capellaSlot - Slot of Capella fork.
 */
function main(opts) {
  assert(opts);
  assert(opts.sourceValidatorIndex < MAX_VALIDATORS);
  assert(opts.targetValidatorIndex < MAX_VALIDATORS);
  assert(opts.sourceValidatorIndex !== opts.targetValidatorIndex);
  assert(opts.withdrawableEpoch > MIN_VALIDATOR_WITHDRAWABILITY_DELAY);
  assert(opts.capellaSlot % SLOTS_PER_HISTORICAL_ROOT === 0);

  const faker = new Faker("seed sEed seEd");

  /** @type {import('@chainsafe/ssz').ListCompositeType} */
  const Validator = Fork.BeaconState.getPathInfo(["validators", 0]).type;

  /** @type {import('@chainsafe/ssz').ContainerType}  */
  const PendingConsolidation = Fork.BeaconState.getPathInfo(["pending_consolidations", 0]).type;

  // Source validator.
  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const sourceValidator = Validator.defaultView();
  sourceValidator.slashed = false;
  sourceValidator.pubkey = new Uint8Array(48).fill(18);
  sourceValidator.withdrawableEpoch = opts.withdrawableEpoch;
  sourceValidator.withdrawalCredentials = new Uint8Array([
    ...new Uint8Array([0x01]),
    ...new Uint8Array(11), // gap
    ...hexStrToBytesArr(opts.address),
  ]);
  sourceValidator.effectiveBalance = opts.effectiveBalance;

  // Target validator (module's validator) — different pubkey.
  /** @type {import('@lodestar/types/lib/phase0').Validator} */
  const targetValidator = Validator.defaultView();
  targetValidator.slashed = false;
  targetValidator.pubkey = new Uint8Array(48).fill(42);
  targetValidator.withdrawableEpoch = 0;
  targetValidator.withdrawalCredentials = new Uint8Array([
    ...new Uint8Array([0x02]),
    ...new Uint8Array(11), // gap
    ...hexStrToBytesArr(opts.address),
  ]);
  targetValidator.effectiveBalance = 32e9;

  const state = Fork.BeaconState.defaultView();

  while (state.validators.length < MAX_VALIDATORS) {
    state.validators.push(Validator.defaultView());
    state.balances.push(32e9);
  }

  // --- Pending block's state, the earliest state in the script.

  const consolidation = PendingConsolidation.defaultView();
  consolidation.sourceIndex = opts.sourceValidatorIndex;
  consolidation.targetIndex = opts.targetValidatorIndex;

  while (state.pendingConsolidations.length < opts.consolidationOffset) {
    state.pendingConsolidations.push(PendingConsolidation.defaultView());
  }

  state.balances.set(opts.sourceValidatorIndex, opts.balance);
  state.validators.set(opts.sourceValidatorIndex, sourceValidator);
  state.validators.set(opts.targetValidatorIndex, targetValidator);
  state.pendingConsolidations.push(consolidation);

  // We imagine that consolidation request was processed and the withdrawableEpoch was set without any delays.
  state.slot = (opts.withdrawableEpoch - MIN_VALIDATOR_WITHDRAWABILITY_DELAY) * SLOTS_PER_EPOCH;

  const pendingBlock = Fork.BeaconBlock.defaultView();
  pendingBlock.slot = state.slot;
  pendingBlock.parentRoot = faker.someBytes32();
  pendingBlock.stateRoot = state.hashTreeRoot();
  {
    const summaryIndex = Math.floor(pendingBlock.slot / SLOTS_PER_HISTORICAL_ROOT);
    const rootIndex = pendingBlock.slot % SLOTS_PER_HISTORICAL_ROOT;
    pendingBlock.meta = {
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
    gindex: state.type.getPathInfo(["balances", opts.sourceValidatorIndex]).gindex,
  });

  // Source validator proof against the pending block state (for effectiveBalance).
  const sourceAtPendingProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.sourceValidatorIndex]).gindex,
  });

  // --- Applied block's state here, the latest state in the script.

  state.slot = (opts.withdrawableEpoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY) * SLOTS_PER_EPOCH;

  // We assume Capella slot to be zero and fill in historical summaries list.
  for (let s = opts.capellaSlot; s < state.slot; s += SLOTS_PER_HISTORICAL_ROOT) {
    const summary = Fork.HistoricalSummary.defaultView();
    summary.blockSummaryRoot = faker.someBytes32();
    summary.stateSummaryRoot = faker.someBytes32();

    // This branch significantly improves performance.
    if (state.historicalSummaries.length == pendingBlock.meta.summaryIndex) {
      const BlockRoots = state.blockRoots.type;
      const blockRoots = BlockRoots.fromJson(
        new Array(8192).fill(faker.someBytes32().toString("hex")),
      );

      blockRoots[pendingBlock.meta.rootIndex] = pendingBlock.hashTreeRoot();

      const nav = state.type.getPathInfo([
        "historicalSummaries",
        state.historicalSummaries.length,
        "blockSummaryRoot",
      ]);
      summary.blockSummaryRoot = state.blockRoots.type.hashTreeRoot(blockRoots);
      summary.stateSummaryRoot = faker.someBytes32();
      state.historicalSummaries.push(summary);
      state.tree.setNode(nav.gindex, BlockRoots.toView(blockRoots).node);
    } else {
      state.historicalSummaries.push(summary);
    }
  }

  // Source validator proof against the applied block state (for slashed and withdrawableEpoch).
  const sourceAtAppliedProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.sourceValidatorIndex]).gindex,
  });

  // Target validator proof against the applied block state (for pubkey and index checks).
  const targetValidatorProof = createProof(state.node, {
    type: ProofType.single,
    gindex: state.type.getPathInfo(["validators", opts.targetValidatorIndex]).gindex,
  });

  const pendingBlockProof = createProof(state.node, {
    type: ProofType.single,
    gindex: concatGindices([
      state.type.getPathInfo([
        "historicalSummaries",
        pendingBlock.meta.summaryIndex,
        "blockSummaryRoot",
      ]).gindex,
      state.blockRoots.type.getPropertyGindex(pendingBlock.meta.rootIndex),
    ]),
  });

  const appliedBlock = Fork.BeaconBlock.defaultView();
  appliedBlock.slot = state.slot;
  appliedBlock.parentRoot = faker.someBytes32();
  appliedBlock.stateRoot = state.hashTreeRoot();

  const fixture = {
    blockRoot: appliedBlock.hashTreeRoot(),
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
      sourceAtPendingBlock: {
        index: opts.sourceValidatorIndex,
        object: {
          pubkey: sourceValidator.pubkey,
          withdrawalCredentials: sourceValidator.withdrawalCredentials,
          effectiveBalance: sourceValidator.effectiveBalance,
          slashed: false,
          activationEligibilityEpoch: sourceValidator.activationEligibilityEpoch,
          activationEpoch: sourceValidator.activationEpoch,
          exitEpoch: sourceValidator.exitEpoch,
          withdrawableEpoch: sourceValidator.withdrawableEpoch,
        },
        proof: sourceAtPendingProof.witnesses,
      },
      sourceAtAppliedBlock: {
        index: opts.sourceValidatorIndex,
        object: {
          pubkey: sourceValidator.pubkey,
          withdrawalCredentials: sourceValidator.withdrawalCredentials,
          effectiveBalance: sourceValidator.effectiveBalance,
          slashed: false,
          activationEligibilityEpoch: sourceValidator.activationEligibilityEpoch,
          activationEpoch: sourceValidator.activationEpoch,
          exitEpoch: sourceValidator.exitEpoch,
          withdrawableEpoch: sourceValidator.withdrawableEpoch,
        },
        proof: sourceAtAppliedProof.witnesses,
      },
      targetAtAppliedBlock: {
        index: opts.targetValidatorIndex,
        object: {
          pubkey: targetValidator.pubkey,
          withdrawalCredentials: targetValidator.withdrawalCredentials,
          effectiveBalance: targetValidator.effectiveBalance,
          slashed: false,
          activationEligibilityEpoch: targetValidator.activationEligibilityEpoch,
          activationEpoch: targetValidator.activationEpoch,
          exitEpoch: targetValidator.exitEpoch,
          withdrawableEpoch: targetValidator.withdrawableEpoch,
        },
        proof: targetValidatorProof.witnesses,
      },
      moduleKeyId: {
        nodeOperatorId: 0,
        keyIndex: 0,
      },
      balance: {
        node: balanceProof.leaf,
        proof: balanceProof.witnesses,
      },
      consolidationAppliedBlock: {
        header: {
          slot: appliedBlock.slot,
          proposerIndex: appliedBlock.proposerIndex,
          parentRoot: appliedBlock.parentRoot,
          stateRoot: appliedBlock.stateRoot,
          bodyRoot: appliedBlock.body.hashTreeRoot(),
        },
        rootsTimestamp: 42,
      },
      consolidationPendingBlock: {
        header: {
          slot: pendingBlock.slot,
          proposerIndex: pendingBlock.proposerIndex,
          parentRoot: pendingBlock.parentRoot,
          stateRoot: pendingBlock.stateRoot,
          bodyRoot: pendingBlock.body.hashTreeRoot(),
        },
        proof: pendingBlockProof.witnesses,
      },
    },
  };

  const ffi_interface = VerifierModuleTargetConsolidationTest.abi.find(
    (e) => e.name == "ffi_interface",
  );
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
  sourceValidatorIndex: 17,
  targetValidatorIndex: 18,
  consolidationOffset: 1,
  balance: parseFloat(process.argv[2]),
  effectiveBalance: parseFloat(process.argv[3]),
  address: "b3e29c46ee1745724417c0c51eb2351a1c01cf36",
  withdrawableEpoch: 100_500,
  capellaSlot: 0,
});
