// The script can be used to find the gindicies required for Verifier deployment.

import { ssz } from "@lodestar/types";

const FIELDS = {
  gIWithdrawals: ["latestExecutionPayloadHeader", "withdrawalsRoot"],
  gIValidators: ["validators"],
  gIBalances: ["balances"],
  gIHistoricalSummaries: ["historicalSummaries"],
  gIBlockRoots: ["blockRoots"],
};

for (const fork of ["electra"]) {
  const Fork = ssz[fork];
  for (const [name, path] of Object.entries(FIELDS)) {
    const gI = Fork.BeaconState.getPathInfo(path).gindex;
    console.log(`${fork}::${name}:`, `0x${gI.toString(16)}`);
  }
  console.log();
}
