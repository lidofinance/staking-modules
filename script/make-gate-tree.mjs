// Build a Merkle tree of member addresses for a MerkleGate and pin it to IPFS.
//
//   node script/make-gate-tree.mjs 0xabc... 0xdef...   # addresses inline
//   node script/make-gate-tree.mjs addresses.txt       # one per line, `#` comments
//   printf '%s\n' 0xabc... | node script/make-gate-tree.mjs -
//
// Prints `Root:` and `CID:` — the same output contract as the `csm-test-tree`
// package, which this replaces; unlike it, pinning goes to any IPFS node
// exposing the kubo RPC API (IPFS_API_URL) instead of Pinata.
//
// Leaves match MerkleGate.hashLeaf: keccak(bytes.concat(keccak(abi.encode(member)))),
// i.e. a single-column StandardMerkleTree of `address`.

import { existsSync, readFileSync } from "node:fs";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

const IPFS_API_URL = (process.env.IPFS_API_URL ?? "http://127.0.0.1:5001").replace(/\/+$/, "");
const IPFS_GATEWAY_URL = (process.env.IPFS_GATEWAY_URL ?? "http://127.0.0.1:8080").replace(
  /\/+$/,
  "",
);
const IPFS_TIMEOUT_MS = 10_000;
const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;

// --- read input ---

const args = process.argv.slice(2);
const noUpload = args.includes("--no-upload");
const positional = args.filter((a) => !a.startsWith("--"));

// A lone `-` or a readable file means the addresses come from there, one per
// line; anything else is taken as inline addresses.
let lines;
if (positional.length === 1 && positional[0] === "-") {
  lines = readFileSync(0, "utf8").split("\n");
} else if (positional.length === 1 && existsSync(positional[0])) {
  lines = readFileSync(positional[0], "utf8").split("\n");
} else {
  lines = positional;
}

const members = lines.map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));

if (members.length === 0) {
  console.error("Usage: make-gate-tree.mjs <address...|file|-> [--no-upload]");
  process.exit(1);
}

const invalid = members.filter((m) => !ADDRESS_RE.test(m));
if (invalid.length > 0) {
  console.error(`Not an address: ${invalid.join(", ")}`);
  process.exit(1);
}

// Duplicates would silently produce two identical leaves, so reject them.
const seen = new Set();
const dupes = members.filter((m) => {
  const key = m.toLowerCase();
  if (seen.has(key)) return true;
  seen.add(key);
  return false;
});
if (dupes.length > 0) {
  console.error(`Duplicate addresses: ${dupes.join(", ")}`);
  process.exit(1);
}

// --- build tree ---

const tree = StandardMerkleTree.of(
  members.map((m) => [m]),
  ["address"],
);
console.log("Root:", tree.root);

if (noUpload) {
  process.exit(0);
}

// --- pin to IPFS ---

// /api/v0/add streams one JSON object per line; the last one is the root entry.
const form = new FormData();
const treeStr = JSON.stringify(tree.dump(), null, 2);
form.append("file", new Blob([treeStr], { type: "application/json" }), "merkle-tree.json");

let res;
try {
  res = await fetch(`${IPFS_API_URL}/api/v0/add?pin=true&cid-version=0&quieter=true`, {
    method: "POST",
    body: form,
    signal: AbortSignal.timeout(IPFS_TIMEOUT_MS),
  });
} catch (e) {
  console.error(`IPFS node at ${IPFS_API_URL} unreachable: ${e.message}`);
  process.exit(1);
}

const body = await res.text();
if (!res.ok) {
  console.error(`IPFS add failed: ${res.status} ${body}`);
  process.exit(1);
}

const { Hash } = JSON.parse(body.trim().split("\n").filter(Boolean).at(-1));
console.log("CID:", Hash);
console.log("Pinned:", `${IPFS_GATEWAY_URL}/ipfs/${Hash}`);
