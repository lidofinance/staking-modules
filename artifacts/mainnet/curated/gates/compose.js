const fs = require("node:fs");
const readline = require("node:readline");
const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");

const csvFiles = [
  "pto.csv",
  "pgo.csv",
  "iodvtc.csv",
];


async function readCsvFile(file) {
  const addresses = [];

  const fileStream = fs.createReadStream(file);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    let [name, address] = line.split(",");
    address = address.toLowerCase();
    addresses.push(address);
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
  for (const file of csvFiles) {
    const addresses = await readCsvFile(file);

    console.log(`Total addresses in ${file}:`, addresses.length);

    const { tree } = buildMerkleTree(addresses);
    console.log("Merkle Root:", tree.root);

    const proofs = {}
    for (const [i, v] of tree.entries()) {
      proofs[v[0]] = tree.getProof(i);
    }

    const folderName = file.split(".")[0];

    fs.mkdirSync(folderName, { recursive: true });
    fs.writeFileSync(`${folderName}/addresses.json`, JSON.stringify(addresses, null, 2));
    fs.writeFileSync(`${folderName}/merkle-tree.json`, JSON.stringify(tree.dump()));
    fs.writeFileSync(`${folderName}/merkle-proofs.json`, JSON.stringify(proofs));
    console.log(`Merkle tree and proofs have been written to files for ${folderName.toUpperCase()}.`);
  }
})();
