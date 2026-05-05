const fs = require("node:fs");
const readline = require("node:readline");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");

const csvFiles = [
  "sources.csv"
];


async function readCsvFiles(files) {
  const addresses = {};

  for (const file of files) {
    const fileStream = fs.createReadStream(file);
    const rl = readline.createInterface({
      input: fileStream,
      crlfDelay: Infinity,
    });

    for await (const line of rl) {
      let [address] = line.split(","); // Assuming CSV has only one column for addresses
      address = address.toLowerCase();
      if (addresses[address]) {
        addresses[address].sources.push(file);
      } else {
        addresses[address] = { sources: [file] };
      }
    }
  }

  return addresses;
}

function buildMerkleTree(addresses) {
  const tree = StandardMerkleTree.of(
    addresses.map((address) => [address]),
    ["address"],
  );
  return { tree };
}

(async function main() {
  const addresses = await readCsvFiles(csvFiles);

  console.log("Total addresses:", Object.keys(addresses).length);

  const { tree } = buildMerkleTree(Object.keys(addresses));
  console.log("Merkle Root:", tree.root);

  const proofs = {}
  for (const [i, v] of tree.entries()) {
    proofs[v[0]] = tree.getProof(i);
  }

  fs.writeFileSync("addresses.json", JSON.stringify(Object.keys(addresses), null, 2));
  fs.writeFileSync("merkle-tree.json", JSON.stringify(tree.dump()));
  fs.writeFileSync("merkle-proofs.json", JSON.stringify(proofs));
  console.log("Merkle tree and proofs have been written to files.");
})();
