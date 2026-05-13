import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const RPC_URL = process.env.ANVIL_RPC_URL ?? "http://127.0.0.1:8545";
const DEPLOY_CONFIG = process.env.DEPLOY_CONFIG;
const ARTIFACTS_DIR = `${process.env.ARTIFACTS_DIR ?? "./artifacts/local/"}rewards/`;

if (!DEPLOY_CONFIG) {
  console.error("DEPLOY_CONFIG is not set");
  process.exit(1);
}

// Mock report parameters
const REWARD_MIN_WEI = 100_000_000_000_000_000n; // 0.1 ETH
const REWARD_MAX_WEI = 200_000_000_000_000_000n; // 0.2 ETH
const REWARD_SPAN = REWARD_MAX_WEI - REWARD_MIN_WEI; // 1e15, fits in Number
const FULL_SHARE_VALIDATORS = 10; // first N validators per operator get rewards_share = 1
const PARTIAL_SHARE = 0.5834; // rewards_share for the rest
const FRAME_START_EPOCH = 300000;
const FRAME_END_EPOCH = 300225;
const REF_SLOT = 9607200n;
const REF_EPOCH = 300225n;
const VALIDATOR_INDEX_OFFSET = 900000;
const THRESHOLD = 0.9;
const PERF_MIN = 0.8;
const PERF_MAX = 1.0;
const FRAME_EPOCHS = FRAME_END_EPOCH - FRAME_START_EPOCH; // attestation slots per frame

// --- helpers ---

function castCall(address, sig, args = []) {
  const result = execFileSync(
    "cast",
    ["call", "--rpc-url", RPC_URL, address, sig, ...args.map(String)],
    { encoding: "utf8" },
  );
  return result.trim();
}

function latestBlockHash() {
  return execFileSync("cast", ["block", "latest", "--field", "hash", "--rpc-url", RPC_URL], {
    encoding: "utf8",
  }).trim();
}

function randFloat(min, max) {
  return min + Math.random() * (max - min);
}

function randReward() {
  const delta = BigInt(Math.floor(Math.random() * Number(REWARD_SPAN)));
  return REWARD_MIN_WEI + delta;
}

function jsonParse(text) {
  // Wrap bare integers that exceed Number.MAX_SAFE_INTEGER as strings before parsing,
  // then revive them back to BigInt.
  const safe = text.replace(/(?<=[:,\[]\s*)-?\d{16,}/g, '"__BI__$&"');
  return JSON.parse(safe, (_, v) =>
    typeof v === "string" && v.startsWith("__BI__") ? BigInt(v.slice(6)) : v,
  );
}

function jsonStringify(obj, space) {
  const S = "__BI__";
  const raw = JSON.stringify(
    obj,
    (_, v) => (typeof v === "bigint" ? S + v.toString() + S : v),
    space,
  );
  return raw.replace(new RegExp(`"${S}(-?\\d+)${S}"`, "g"), "$1");
}

// --- read on-chain state ---

const config = JSON.parse(readFileSync(DEPLOY_CONFIG, "utf8"));
const module = config.CSModule ?? config.CuratedModule;
if (!module) {
  console.error(`CSModule or CuratedModule address not found in ${DEPLOY_CONFIG}`);
  process.exit(1);
}

const feeDistributor = config.FeeDistributor;
if (!feeDistributor) {
  console.error(`FeeDistributor address not found in ${DEPLOY_CONFIG}`);
  process.exit(1);
}

const count = Number(castCall(module, "getNodeOperatorsCount()(uint256)"));
console.log(`Operators: ${count}`);

// Collect active operators
const operators = [];
for (let noId = 0; noId < count; noId++) {
  const raw = castCall(
    module,
    "getNodeOperator(uint256)(uint32,uint32,uint32,uint32,uint32,uint32,uint32,uint8,uint32,uint32,address,address,address,address,bool,bool)",
    [noId],
  );
  const lines = raw.split("\n");
  const totalDepositedKeys = Number(lines[2]);
  const totalWithdrawnKeys = Number(lines[1]);
  const activeKeys = totalDepositedKeys - totalWithdrawnKeys;
  if (activeKeys > 0) {
    operators.push({ noId, activeKeys });
  }
}

if (operators.length === 0) {
  console.log("No active keys found across any operator. Emitting empty report.");
}

const totalActiveKeys = operators.reduce((s, o) => s + o.activeKeys, 0);
console.log(`Active operators: ${operators.length}, total active keys: ${totalActiveKeys}`);

// --- generate mock validator data ---

let globalValIdx = VALIDATOR_INDEX_OFFSET;
const reportOperators = {};
let distributed = 0n;

for (const { noId, activeKeys } of operators) {
  const validators = {};
  let opDistributed = 0n;

  for (let k = 0; k < activeKeys; k++) {
    const valIdx = globalValIdx++;
    const perf = randFloat(PERF_MIN, PERF_MAX);
    const slashed = Math.random() < 0.02;
    const attAssigned = FRAME_EPOCHS;
    const attIncluded = Math.round(perf * attAssigned);
    const propAssigned = Math.random() < 0.1 ? 1 : 0;
    const propIncluded = propAssigned && perf > 0.95 ? 1 : 0;
    const syncAssigned = Math.random() < 0.05 ? 512 : 0;
    const syncIncluded = Math.round(perf * syncAssigned);

    const reward = randReward();
    opDistributed += reward;

    validators[String(valIdx)] = {
      attestation_duty: { assigned: attAssigned, included: attIncluded },
      distributed_rewards: reward,
      performance: perf,
      proposal_duty: { assigned: propAssigned, included: propIncluded },
      rewards_share: k < FULL_SHARE_VALIDATORS ? 1 : PARTIAL_SHARE,
      slashed,
      strikes: slashed ? 1 : 0,
      sync_duty: { assigned: syncAssigned, included: syncIncluded },
      threshold: THRESHOLD,
    };
  }

  reportOperators[String(noId)] = {
    distributed_rewards: opDistributed,
    performance_coefficients: {
      attestations_weight: 54,
      blocks_weight: 4,
      sync_weight: 2,
    },
    validators,
  };

  distributed += opDistributed;
}

const rebate = 0n;

// --- load previous merkle tree ---

const PAD_NO_ID = (1n << 64n) - 1n; // type(uint64).max, matches test suite convention
const ZERO_ROOT = "0x" + "00".repeat(32);

const prevTreePath = `${ARTIFACTS_DIR}merkle-tree.json`;
const prevCumulatives = new Map();

const onChainRoot = castCall(feeDistributor, "treeRoot()(bytes32)");
console.log(`On-chain tree root: ${onChainRoot}`);

if (onChainRoot === ZERO_ROOT) {
  console.log("No on-chain reports yet, starting fresh");
} else {
  let loaded = false;

  // Try local file first
  if (existsSync(prevTreePath)) {
    const prevDump = jsonParse(readFileSync(prevTreePath, "utf8"));
    if (prevDump.values) {
      const prevTree = StandardMerkleTree.load(prevDump);
      if (prevTree.root.toLowerCase() === onChainRoot.toLowerCase()) {
        for (const [, [noId, shares]] of prevTree.entries()) {
          prevCumulatives.set(BigInt(noId), BigInt(shares));
        }
        loaded = true;
        console.log(`Local tree matches on-chain root (${prevCumulatives.size} leaves)`);
      } else {
        console.log("Local tree root mismatch, fetching from IPFS...");
      }
    }
  }

  // Fetch from IPFS using on-chain treeCid
  if (!loaded) {
    const treeCid = castCall(feeDistributor, "treeCid()(string)").replace(/^"|"$/g, "");
    console.log(`On-chain tree CID: ${treeCid}`);
    const ipfsUrls = [
      `https://ipfs.io/ipfs/${treeCid}`,
      `https://gateway.pinata.cloud/ipfs/${treeCid}`,
    ];

    let fetched = false;
    for (const url of ipfsUrls) {
      try {
        const res = await fetch(url);
        if (!res.ok) {
          console.warn(`IPFS gateway ${url} returned ${res.status}`);
          continue;
        }
        const dump = jsonParse(await res.text());
        const tree = StandardMerkleTree.load(dump);
        if (tree.root.toLowerCase() !== onChainRoot.toLowerCase()) {
          console.warn(`IPFS tree root mismatch at ${url}, trying next...`);
          continue;
        }
        for (const [, [noId, shares]] of tree.entries()) {
          prevCumulatives.set(BigInt(noId), BigInt(shares));
        }
        fetched = true;
        console.log(`Fetched tree from IPFS (${prevCumulatives.size} leaves)`);
        break;
      } catch (e) {
        console.warn(`Failed to fetch from ${url}: ${e.message}`);
      }
    }

    if (!fetched) {
      console.error("Failed to fetch previous tree from any IPFS gateway");
      process.exit(1);
    }
  }
}

// --- build cumulative merkle tree ---

const cumulativeLeaves = new Map();

// Carry forward all previous operators (including removed ones)
for (const [noId, shares] of prevCumulatives) {
  if (noId !== PAD_NO_ID) cumulativeLeaves.set(noId, shares);
}

// Add current frame deltas
for (const [noId, op] of Object.entries(reportOperators)) {
  const prev = cumulativeLeaves.get(BigInt(noId)) ?? 0n;
  cumulativeLeaves.set(BigInt(noId), prev + op.distributed_rewards);
}

const leaves = [...cumulativeLeaves.entries()].map(([noId, shares]) => [noId, shares]);

// FeeDistributor rejects empty proofs (=> needs >= 2 leaves); pad a lone real operator.
if (leaves.length === 1) {
  leaves.push([PAD_NO_ID, 0n]);
}

const tree = leaves.length > 0 ? StandardMerkleTree.of(leaves, ["uint256", "uint256"]) : null;
const treeRoot = tree ? tree.root : ZERO_ROOT;
console.log(`Merkle tree root: ${treeRoot}`);

// --- build V2 report ---

const report = {
  blockstamp: {
    block_hash: latestBlockHash(),
    block_number: 20000000n,
    block_timestamp: Math.floor(Date.now() / 1000),
    ref_epoch: REF_EPOCH,
    ref_slot: REF_SLOT,
    slot_number: REF_SLOT,
    state_root: "0x" + "cd".repeat(32),
  },
  distributable: distributed,
  distributed_rewards: distributed,
  rebate_to_protocol: rebate,
  frame: [FRAME_START_EPOCH, FRAME_END_EPOCH],
  operators: reportOperators,
};

// --- write output ---

mkdirSync(ARTIFACTS_DIR, { recursive: true });

const treeStr = tree ? jsonStringify(tree.dump(), 2) : "{}";
const reportStr = jsonStringify([report], 2);

const treePath = `${ARTIFACTS_DIR}merkle-tree.json`;
writeFileSync(treePath, treeStr + "\n");
console.log(`Written: ${treePath}`);

const reportPath = `${ARTIFACTS_DIR}report.json`;
writeFileSync(reportPath, reportStr + "\n");
console.log(`Written: ${reportPath}`);

// --- pin to IPFS via Pinata ---

const PINATA_API_KEY = process.env.PINATA_API_KEY;
const PINATA_API_SECRET = process.env.PINATA_API_SECRET;

let treeCid;
let logCid;

if (!tree) {
  treeCid = "";
  logCid = "";
  console.log("Empty report, skipping IPFS pinning");
} else if (PINATA_API_KEY && PINATA_API_SECRET) {
  async function pinJson(name, jsonStr) {
    const blob = new Blob([jsonStr], { type: "application/json" });
    const form = new FormData();
    form.append("file", blob, name);
    form.append("pinataMetadata", JSON.stringify({ name }));
    const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
      method: "POST",
      headers: {
        pinata_api_key: PINATA_API_KEY,
        pinata_secret_api_key: PINATA_API_SECRET,
      },
      body: form,
    });
    if (!res.ok) {
      throw new Error(`Pinata ${name}: ${res.status} ${await res.text()}`);
    }
    const { IpfsHash } = await res.json();
    return IpfsHash;
  }

  [treeCid, logCid] = await Promise.all([
    pinJson("merkle-tree.json", treeStr),
    pinJson("report.json", reportStr),
  ]);
  console.log(`Pinned merkle-tree: ${treeCid}`);
  console.log(`Pinned report:      ${logCid}`);
} else {
  const ts = Math.floor(Date.now() / 1000);
  treeCid = `local-tree-${ts}`;
  logCid = `local-log-${ts}`;
  console.log("PINATA_API_KEY/SECRET not set, using local CIDs");
}

// --- write oracle report data artifact ---

const oracleReportData = {
  treeRoot,
  treeCid,
  logCid,
  distributed: distributed.toString(),
  rebate: rebate.toString(),
};

const oracleReportDataPath = `${ARTIFACTS_DIR}oracle-report-data.json`;
writeFileSync(oracleReportDataPath, JSON.stringify(oracleReportData, null, 2) + "\n");
console.log(`Written: ${oracleReportDataPath}`);
