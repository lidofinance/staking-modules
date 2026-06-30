const fs = require("fs");
const path = require("path");

const ARTIFACTS_DIR = "artifacts";

function readJsonFile(path) {
  return JSON.parse(fs.readFileSync(path));
}

function main() {
  const result = {};
  // Accepts nested subdirs, e.g. "local/csm" or "hoodi/curated".
  const txPath = path.join(ARTIFACTS_DIR, process.argv[2] || "", "transactions.json");
  if (!fs.existsSync(txPath)) {
    throw new Error("transactions.json not found at: " + txPath);
  }
  const transactions = readJsonFile(txPath).transactions;

  transactions.forEach((tx) => {
    if (tx.transactionType.startsWith("CREATE") && tx.contractAddress && tx.contractName) {
      result[tx.contractAddress] = tx.contractName;
    }

    let factoryContractName = null;
    if (tx.contractName === "VettedGateFactory" && tx.function?.startsWith("create(")) {
      factoryContractName = "OssifiableProxy";
    }

    if (factoryContractName) {
      (tx.additionalContracts || []).forEach((nestedTx) => {
        if (nestedTx.transactionType === "CREATE" && nestedTx.address) {
          result[nestedTx.address] = factoryContractName;
        }
      });
    }
  });

  console.log(JSON.stringify(result, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
