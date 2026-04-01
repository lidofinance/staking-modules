import { createServer } from "node:http";
import { readFileSync } from "node:fs";

const PORT = Number(process.env.CL_MOCK_PORT ?? 5052);
const STATE_FILE = process.env.CL_STATE_FILE ?? "cl-state.json";
const FAR_FUTURE = "18446744073709551615";
const WC_PLACEHOLDER = "0x02000000000000000000000x4473dcddbf77679a643bdb654dbd86d67f8d32f2";

const EPOCH_DEFAULTS = {
  pending_initialized: {
    activation_epoch: FAR_FUTURE,
    exit_epoch: FAR_FUTURE,
    withdrawable_epoch: FAR_FUTURE,
  },
  pending_queued: {
    activation_epoch: FAR_FUTURE,
    exit_epoch: FAR_FUTURE,
    withdrawable_epoch: FAR_FUTURE,
  },
  active_ongoing: { activation_epoch: "0", exit_epoch: FAR_FUTURE, withdrawable_epoch: FAR_FUTURE },
  active_exiting: { activation_epoch: "0", exit_epoch: "999999", withdrawable_epoch: "1000255" },
  active_slashed: { activation_epoch: "0", exit_epoch: "999999", withdrawable_epoch: "1000255" },
  exited_unslashed: { activation_epoch: "0", exit_epoch: "100", withdrawable_epoch: "356" },
  exited_slashed: { activation_epoch: "0", exit_epoch: "100", withdrawable_epoch: "356" },
  withdrawal_possible: { activation_epoch: "0", exit_epoch: "100", withdrawable_epoch: "356" },
  withdrawal_done: { activation_epoch: "0", exit_epoch: "100", withdrawable_epoch: "356" },
  withdrawal_possible_slashed: {
    activation_epoch: "0",
    exit_epoch: "100",
    withdrawable_epoch: "356",
  },
  withdrawal_done_slashed: { activation_epoch: "0", exit_epoch: "100", withdrawable_epoch: "356" },
};

const API_STATUS = {
  withdrawal_possible_slashed: "withdrawal_possible",
  withdrawal_done_slashed: "withdrawal_done",
};

function loadState() {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return {};
  }
}

function buildValidator(pubkey, entry, autoIndex) {
  const status = entry.status;
  const epochs = EPOCH_DEFAULTS[status] ?? EPOCH_DEFAULTS.active_ongoing;

  return {
    index: String(entry.index ?? autoIndex),
    balance: entry.balance ?? "32000000000",
    status: API_STATUS[status] ?? status,
    validator: {
      pubkey,
      withdrawal_credentials: entry.withdrawal_credentials ?? WC_PLACEHOLDER,
      effective_balance: entry.effective_balance ?? "32000000000",
      slashed: entry.slashed ?? status?.endsWith("_slashed") ?? false,
      activation_eligibility_epoch: entry.activation_eligibility_epoch ?? "0",
      activation_epoch: entry.activation_epoch ?? epochs.activation_epoch,
      exit_epoch: entry.exit_epoch ?? epochs.exit_epoch,
      withdrawable_epoch: entry.withdrawable_epoch ?? epochs.withdrawable_epoch,
    },
  };
}

const VALIDATORS_RE = /^\/eth\/v1\/beacon\/states\/[^/]+\/validators\/?$/;

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method !== "GET" || !VALIDATORS_RE.test(url.pathname)) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ message: "not found" }));
    return;
  }

  const ids = url.searchParams.get("id")?.split(",").filter(Boolean) ?? [];
  const state = loadState();
  const data = [];

  let autoIndex = 900000;
  for (const pubkey of ids) {
    const key = pubkey.toLowerCase();
    const entry = state[key];
    if (!entry?.status) continue;
    data.push(buildValidator(key, entry, autoIndex++));
  }

  res.writeHead(200, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(
    JSON.stringify({
      execution_optimistic: false,
      finalized: true,
      data,
    }),
  );
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`CL mock server listening on http://127.0.0.1:${PORT}`);
  console.log(`State file: ${STATE_FILE}`);
});
