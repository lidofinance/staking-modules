// The script can be used to find the gindicies required for Verifier deployment.

import { ssz } from "@lodestar/types";

const FIELDS = [
  ["gIWithdrawals", ["latestExecutionPayloadHeader", "withdrawalsRoot"]],
  ["gIWithdrawals", ["payloadExpectedWithdrawals"]],
  ["gIValidators", ["validators"]],
  ["gIBalances", ["balances"]],
  ["gIBlockRoots", ["blockRoots"]],
  ["gIHistoricalSummaries", ["historicalSummaries"]],
];

for (const fork of ["electra", "gloas"]) {
  const Fork = ssz[fork];
  for (const [name, path] of FIELDS) {
    try {
      const gI = Fork.BeaconState.getPathInfo(path).gindex;
      console.log(`${fork}::${name}:`, `0x${gI.toString(16)}`);
    } catch {}
  }
  console.log();
}
