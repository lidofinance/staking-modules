const fs = require("fs");
const path = require("path");

function readJsonFile(path) {
  return JSON.parse(fs.readFileSync(path));
}

function main() {
  const args = process.argv.slice(2);
  if (!args.length) {
    throw new Error("Pass forge broadcast runs, e.g. broadcast/DeployMainnet.s.sol/1");
  }

  const result = {};
  for (const arg of args) {
    // Accepts a forge broadcast run .json file, or a broadcast dir holding run-latest.json.
    const txPath = arg.endsWith(".json") ? arg : path.join(arg, "run-latest.json");
    if (!fs.existsSync(txPath)) {
      throw new Error("Broadcast run not found at: " + txPath);
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
  }

  console.log(JSON.stringify(result, null, 2));
}

try {
  main();
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
