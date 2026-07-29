const fs = require("fs");

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJsonFile(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n");
}

function parseLibrary(library) {
  const parts = library.split(":");
  if (parts.length !== 3) {
    throw new Error(`Invalid library entry: ${library}`);
  }

  const [, name, address] = parts;
  if (!name || !address) {
    throw new Error(`Invalid library entry: ${library}`);
  }

  return { name, address };
}

function mergeExternalLibraries(deployConfigPath, transactionsPath) {
  const deployConfig = readJsonFile(deployConfigPath);
  const transactions = readJsonFile(transactionsPath);
  const libraries = transactions.libraries || [];

  deployConfig.ExternalLibraries = libraries.reduce((acc, library) => {
    const { name, address } = parseLibrary(library);
    if (acc[name] && acc[name].toLowerCase() !== address.toLowerCase()) {
      throw new Error(`Conflicting addresses for ${name}: ${acc[name]} and ${address}`);
    }
    acc[name] = address;
    return acc;
  }, {});

  writeJsonFile(deployConfigPath, deployConfig);
}

function main() {
  const [, , deployConfigPath, transactionsPath] = process.argv;
  if (!deployConfigPath || !transactionsPath) {
    throw new Error("Usage: node script/mergeExternalLibraries.js <deploy-config> <transactions>");
  }

  mergeExternalLibraries(deployConfigPath, transactionsPath);
}

try {
  main();
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
