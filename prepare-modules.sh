#!/bin/bash
#
# Prepare Local Hoodi Fork - All Modules
# Prerequisite: Local Hoodi fork already running on http://127.0.0.1:8545
#
# This script:
# 1. Upgrades CSM to v3 + executes vote
# 2. Deploys CM (Curated Module) v2 + executes vote
# 3. Deploys CSM 0x02 + executes vote
# 4. Updates SMDiscovery caches

set -e

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
export RPC_URL

LOCAL_PK=$(just _local-private-key)
SENDER=$(cast wallet address "$LOCAL_PK")

echo "=== Prepare Local Hoodi Fork - All Modules ==="
echo "RPC_URL: $RPC_URL"
echo "SENDER: $SENDER"
echo ""

# Step 1: CSM v3 Upgrade
echo ">>> Deploying CSM v3 implementations..."
SKIP_LEGACY_QUEUE_CHECK=1 \
  just _deploy-csm-impl --broadcast --private-key="$LOCAL_PK"
echo "Done"
echo ""

echo ">>> Executing CSM v3 upgrade vote..."
DEPLOY_CONFIG=./artifacts/local/upgrade-hoodi.json just vote-upgrade
echo "Done"
echo ""

# Step 2: CM v2 Deployment
echo ">>> Deploying CM v2..."
ARTIFACTS_DIR=./artifacts/local/curated/ just deploy-curated --silent --private-key="$LOCAL_PK"
echo "Done"
echo ""

echo ">>> Executing CM add module vote..."
DEPLOY_CONFIG=./artifacts/local/curated/deploy-hoodi.json just vote-add-curated-module
echo "Done"
echo ""

# Step 3: CSM 0x02 Deployment
echo ">>> Deploying CSM 0x02..."
just deploy-csm0x02 --silent --private-key="$LOCAL_PK"
echo "Done"
echo ""

echo ">>> Executing CSM 0x02 add module vote..."
DEPLOY_CONFIG=./artifacts/local/csm0x02/deploy-hoodi.json just vote-add-csm0x02-module
echo "Done"
echo ""

# Step 4: Update SMDiscovery caches
SM_DISCOVERY="0x2E04CC1F1dac245f66a5C7c5288Bdd4f7cF0c8b4"
echo ">>> Updating SMDiscovery caches..."
cast send "$SM_DISCOVERY" "updateModuleCache(uint256)" 5 \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK"
cast send "$SM_DISCOVERY" "updateModuleCache(uint256)" 6 \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK"
echo "Done"
echo ""

# Summary
echo "=== Summary ==="
echo "CSM v3: Upgraded"
echo "CM v2: Deployed"
echo "CSM 0x02: Deployed"
echo "SMDiscovery caches: Updated"
echo ""
echo "Next: Run ./prepare-curated-gates.sh to setup curated gates"
echo ""
echo "=== Done ==="
