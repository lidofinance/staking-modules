#!/usr/bin/env bash
#
# prepare-modules.sh — bring the staking modules to their target state on a local
# anvil mainnet fork by simulating the governance votes, then populate SMDiscovery's
# module cache for the newly-added Curated Module (CM, id 4).
#
# Overridable via env (or pass the SMDiscovery address as $1):
#   RPC_URL      RPC endpoint         (default: http://127.0.0.1:8545)
#   DISCOVERY    SMDiscovery address  (default: locally-deployed address) [also $1]
#   MODULE_ID    module to cache      (default: 4 — Curated Module)
#   SENDER       cache tx sender      (default: anvil dev account #0, pre-funded)
#
set -euo pipefail

# run from the repo root so the relative artifact paths below always resolve
cd "$(dirname "$0")"

RPC_URL="http://127.0.0.1:8545"
DISCOVERY="${1:-${DISCOVERY:-0x6a9c16626D64dFe7A185eb6378F8eB901f96281C}}"
MODULE_ID="${MODULE_ID:-4}"
SENDER="${SENDER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}" # anvil dev account #0

ZERO=0x0000000000000000000000000000000000000000

# ── 1. switch the core StakingRouter proxy to v3 ──────────────────────────────
#
# The core protocol V3 (Triggerable Withdrawals) upgrade is DEPLOYED on this fork
# (new SR impl + v3 LidoLocator are live) but the governance vote that flips the SR
# proxy was never enacted, so the proxy still delegatecalls the old impl. That old impl
# lacks the struct-based addStakingModule(string,address,StakingModuleConfig) selector
# the module votes below call — without this step vote-add-curated-module reverts with a
# bare EvmError (unknown selector, ~234 gas). We replicate the exact SR step from core's
# UpgradeVoteScript: proxy__upgradeToAndCall(newImpl, finalizeUpgrade_v4(maxTopUpGwei)),
# sent by the proxy admin (the DAO Agent). Values from lido/core deployed-mainnet.json.
SR_PROXY=0xFdDf38947aFB03C621C71b06C9C70bce73f12999
SR_IMPL=0xDD76927045435C7605cf6f5F978cfb8CABDb5F80  # .stakingRouter.implementation.address
MAX_TOPUP_GWEI=3200000000000                        # .coreUpgrade.maxTopUpPerBlockGwei
SR_IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc # EIP-1967 impl
SR_ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 # EIP-1967 admin

cur_impl=$(cast storage "$SR_PROXY" "$SR_IMPL_SLOT" --rpc-url "$RPC_URL" | cast parse-bytes32-address)
if [ "$(printf '%s' "$cur_impl" | tr 'A-F' 'a-f')" = "$(printf '%s' "$SR_IMPL" | tr 'A-F' 'a-f')" ]; then
  echo "✓ StakingRouter already on v3 impl → $cur_impl"
else
  sr_admin=$(cast storage "$SR_PROXY" "$SR_ADMIN_SLOT" --rpc-url "$RPC_URL" | cast parse-bytes32-address)
  CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
  finalize=$(cast calldata "finalizeUpgrade_v4(uint256)" "$MAX_TOPUP_GWEI")
  echo "→ upgrading StakingRouter $SR_PROXY: $cur_impl → $SR_IMPL (admin=$sr_admin)"
  cast rpc anvil_setBalance "$sr_admin" 0x56bc75e2d63100000 --rpc-url "$RPC_URL" >/dev/null # 100 ETH gas
  cast rpc anvil_impersonateAccount "$sr_admin" --rpc-url "$RPC_URL" >/dev/null
  cast send "$SR_PROXY" "proxy__upgradeToAndCall(address,bytes,bool)" "$SR_IMPL" "$finalize" false \
    --rpc-url "$RPC_URL" --from "$sr_admin" --unlocked --chain "$CHAIN_ID" >/dev/null
  cast rpc anvil_stopImpersonatingAccount "$sr_admin" --rpc-url "$RPC_URL" >/dev/null
  new_impl=$(cast storage "$SR_PROXY" "$SR_IMPL_SLOT" --rpc-url "$RPC_URL" | cast parse-bytes32-address)
  new_ver=$(cast call "$SR_PROXY" "getContractVersion()(uint256)" --rpc-url "$RPC_URL")
  echo "✓ StakingRouter upgraded → $new_impl (version $new_ver)"
fi

# ── 2. simulate the votes ─────────────────────────────────────────────────────
RPC_URL="$RPC_URL" DEPLOY_CONFIG=./artifacts/mainnet/csm/upgrade-v3-mainnet.json just vote-upgrade
RPC_URL="$RPC_URL" DEPLOY_CONFIG=./artifacts/mainnet/curated/deploy-mainnet.json just vote-add-curated-module

# ── 3. update SMDiscovery module cache for the Curated Module ─────────────────
#
# updateModuleCache() is permissionless (it just mirrors the module address from the
# StakingRouter), so no role or DAO account is required. We impersonate anvil's pre-funded
# dev account #0 and send the tx unlocked (node-side signing), avoiding any local key.
#
# NOTE: the repo's .env sets CHAIN=hoodi, which foundry reads and would stamp onto the tx
# (→ chain-id mismatch against the chain-1 fork). We defeat that by querying the fork's
# real chain id and passing it explicitly via --chain.
echo "→ discovery=$DISCOVERY  moduleId=$MODULE_ID  rpc=$RPC_URL"

# discovery must be deployed on this fork
if [ "$(cast code "$DISCOVERY" --rpc-url "$RPC_URL")" = "0x" ]; then
  echo "✗ no contract code at $DISCOVERY — deploy SMDiscovery on the fork first" >&2
  exit 1
fi

# no-op if already cached (updateModuleCache reverts on an unchanged re-cache)
cached=$(cast call "$DISCOVERY" "moduleCache(uint256)(address,address)" "$MODULE_ID" --rpc-url "$RPC_URL" | head -1)
if [ "$cached" != "$ZERO" ]; then
  echo "✓ module $MODULE_ID already cached → $cached"
  exit 0
fi

# populate the cache (permissionless; impersonated sender, --chain from the fork)
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
cast rpc anvil_impersonateAccount "$SENDER" --rpc-url "$RPC_URL" >/dev/null
cast send "$DISCOVERY" "updateModuleCache(uint256)" "$MODULE_ID" \
  --rpc-url "$RPC_URL" --from "$SENDER" --unlocked --chain "$CHAIN_ID" >/dev/null
cast rpc anvil_stopImpersonatingAccount "$SENDER" --rpc-url "$RPC_URL" >/dev/null

# verify
out=$(cast call "$DISCOVERY" "moduleCache(uint256)(address,address)" "$MODULE_ID" --rpc-url "$RPC_URL")
module=$(printf '%s\n' "$out" | sed -n '1p')
accounting=$(printf '%s\n' "$out" | sed -n '2p')
echo "✓ cached module $MODULE_ID → module=$module accounting=$accounting"
