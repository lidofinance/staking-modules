#!/bin/bash
#
# Prepare Local Hoodi Fork - Module Deployment
# Prerequisite: Local Hoodi fork already running on http://127.0.0.1:8545
#
# This script:
# 1. Upgrades CSM to v3 + executes vote
# 2. Deploys CM (Curated Module) v2 + executes vote
# 3. Updates SMDiscovery cache for module 5

set -e

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="560048"  # Hoodi chain ID

# Read sender address from Anvil (first available account)
SENDER=$(cast rpc eth_accounts --rpc-url="$RPC_URL" | jq -r '.[0]')
if [ -z "$SENDER" ] || [ "$SENDER" = "null" ]; then
  echo "ERROR: Could not read sender address from Anvil at $RPC_URL"
  echo "Make sure Anvil is running: just make-fork"
  exit 1
fi
CM_DEPLOY_CONFIG="./artifacts/local/curated/deploy-hoodi.json"
SM_DISCOVERY="0x43f1c35392418aeeDA48dC136caa7DE43544AbFF"
mkdir -p "$(dirname "$CM_DEPLOY_CONFIG")"

echo "=== Prepare Local Hoodi Fork - Module Deployment ==="
echo "RPC_URL: $RPC_URL"
echo "SENDER: $SENDER"
echo ""

# Step 1: Enable auto-impersonation
echo ">>> Enabling auto-impersonation..."
curl -sS "$RPC_URL" \
  --header 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[true],"id":1}' > /dev/null
echo "Done"
echo ""

# Step 2: CSM v3 Upgrade
echo ">>> Deploying CSM v3 implementations..."
RPC_URL="$RPC_URL" ARTIFACTS_DIR=./artifacts/local/ SKIP_LEGACY_QUEUE_CHECK=1 \
  just _deploy-impl --broadcast --sender "$SENDER" --unlocked
echo "Done"
echo ""

echo ">>> Executing CSM v3 upgrade vote..."
RPC_URL="$RPC_URL" DEPLOY_CONFIG=./artifacts/local/upgrade-hoodi.json just vote-upgrade
echo "Done"
echo ""

# Step 3: CM v2 Deployment
echo ">>> Deploying CM v2 implementations..."
RPC_URL="$RPC_URL" ARTIFACTS_DIR=./artifacts/local/curated/ \
  just deploy-curated --sender "$SENDER" --unlocked
echo "Done"
echo ""

echo ">>> Executing CM add module vote..."
RPC_URL="$RPC_URL" DEPLOY_CONFIG="$CM_DEPLOY_CONFIG" just vote-add-curated-module
echo "Done"
echo ""

# Step 4: Update SMDiscovery cache for module 5
echo ">>> Updating SMDiscovery cache for module 5..."
cast send "$SM_DISCOVERY" "updateModuleCache(uint256)" 5 \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER"
echo "Done"
echo ""

# Summary
echo "=== Summary ==="
echo "CSM v3: Upgraded"
echo "CM v2: Deployed"
echo "SMDiscovery module 5 cache: Updated"
echo ""
echo "Next: Run ./prepare-curated-gates.sh to setup curated gates"
echo ""
echo "=== Done ==="
