#!/bin/bash
#
# Setup Curated Gates on Local Hoodi Fork
# Prerequisite: Run prepare-modules.sh first to deploy CSM v3 and CM v2
#
# This script creates curves 2-7 and gates 2-7 (curve 1 and gate 1 already exist from prepare-modules.sh)
# Bond parameters from curated-gate-parameters.md
#
# Steps:
# 1. Grants required roles to SENDER
# 2. Creates 6 bond curves (curveIds 2-7)
# 3. Deploys 6 curated gates via factory
# 4. Grants roles to each new gate
# 5. Updates deploy config JSON with new gate addresses
# 6. Revokes temporary roles from SENDER

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
mkdir -p "$(dirname "$CM_DEPLOY_CONFIG")"

echo "=== Setup Curated Gates (2-7) ==="

# Helper function to get DEFAULT_ADMIN_ROLE holder for a contract
get_admin() {
  local contract=$1
  cast call "$contract" "getRoleMember(bytes32,uint256)(address)" \
    "0x0000000000000000000000000000000000000000000000000000000000000000" 0 \
    --rpc-url="$RPC_URL"
}

# Read addresses from deploy config
ACCOUNTING=$(jq -r '.Accounting' "$CM_DEPLOY_CONFIG")
GATE_FACTORY=$(jq -r '.CuratedGateFactory' "$CM_DEPLOY_CONFIG")
CURATED_MODULE=$(jq -r '.CuratedModule' "$CM_DEPLOY_CONFIG")
OPERATORS_DATA=$(jq -r '.OperatorsData' "$CM_DEPLOY_CONFIG")

# Get admins and impersonate
ACCOUNTING_ADMIN=$(get_admin "$ACCOUNTING")
MODULE_ADMIN=$(get_admin "$CURATED_MODULE")
OPERATORS_DATA_ADMIN=$(get_admin "$OPERATORS_DATA")
cast rpc anvil_impersonateAccount "$ACCOUNTING_ADMIN" --rpc-url="$RPC_URL" > /dev/null
cast rpc anvil_impersonateAccount "$MODULE_ADMIN" --rpc-url="$RPC_URL" > /dev/null
cast rpc anvil_impersonateAccount "$OPERATORS_DATA_ADMIN" --rpc-url="$RPC_URL" > /dev/null

# Role hashes
MANAGE_CURVES_ROLE=$(cast keccak "MANAGE_BOND_CURVES_ROLE")
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

# Grant required roles to SENDER
echo ">>> Granting roles..."
cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
  "$MANAGE_CURVES_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$ACCOUNTING_ADMIN" > /dev/null
cast send "$CURATED_MODULE" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$MODULE_ADMIN" > /dev/null
cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$ACCOUNTING_ADMIN" > /dev/null
cast send "$OPERATORS_DATA" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$OPERATORS_DATA_ADMIN" > /dev/null

# Bond curves for curveIds 2-7 (curveId 1 already exists from prepare-modules.sh)
# Format: [(minKeys, trendWei), ...]
# Bond parameters from curated-gate-parameters.md: [first_key_ETH, (subsequent_key_ETH)]
CURVES=(
  "[(1,11000000000000000000),(2,600000000000000000)]"
  "[(1,11000000000000000000),(2,600000000000000000)]"
  "[(1,11000000000000000000),(2,600000000000000000)]"
  "[(1,11000000000000000000),(2,600000000000000000)]"
  "[(1,11000000000000000000),(2,350000000000000000)]"
  "[(1,11000000000000000000),(2,600000000000000000)]"
)
CURVE_DESCS=(
  "[11, (0.6)] ETH"
  "[11, (0.6)] ETH"
  "[11, (0.6)] ETH"
  "[11, (0.6)] ETH"
  "[11, (0.35)] ETH"
  "[11, (0.6)] ETH"
)

# Placeholder merkle tree data (same for all gates, to be updated later)
TREE_ROOT="0x00000000000000000000000000000000000000000000000000000000bbbbcccc"
TREE_CID="TODO: ipfs-cid"

# Role hashes for gates
CREATE_NO_ROLE=$(cast keccak "CREATE_NODE_OPERATOR_ROLE")
SET_CURVE_ROLE=$(cast keccak "SET_BOND_CURVE_ROLE")
SETTER_ROLE=$(cast keccak "SETTER_ROLE")

# Verify initial curves count (curveIds 0 and 1 should exist)
echo ">>> Getting curves count..."
INITIAL_CURVE_COUNT=$(cast call "$ACCOUNTING" "getCurvesCount()(uint256)" --rpc-url="$RPC_URL")
if [ "$INITIAL_CURVE_COUNT" -ne 2 ]; then
  echo "ERROR: Expected 2 curves (curveIds 0,1) but found $INITIAL_CURVE_COUNT"
  echo "Make sure prepare-modules.sh has been run first"
  exit 1
fi
echo ">>> Found $INITIAL_CURVE_COUNT curves, starting from curveId 2"

# Track created gates
NEW_GATES=()

# Create curves and gates
for i in "${!CURVES[@]}"; do
  EXPECTED_CURVE_ID=$((i + 2))  # curveIds 2-7

  # Add bond curve
  echo ">>> Adding curve $EXPECTED_CURVE_ID: ${CURVE_DESCS[$i]}"
  cast send "$ACCOUNTING" "addBondCurve((uint256,uint256)[])" "${CURVES[$i]}" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null

  # Verify curve ID
  CURVE_COUNT=$(cast call "$ACCOUNTING" "getCurvesCount()(uint256)" --rpc-url="$RPC_URL")
  CURVE_ID=$((CURVE_COUNT - 1))
  if [ "$CURVE_ID" -ne "$EXPECTED_CURVE_ID" ]; then
    echo "ERROR: Expected curveId=$EXPECTED_CURVE_ID but got $CURVE_ID"
    exit 1
  fi

  # Deploy gate via factory
  cast send "$GATE_FACTORY" \
    "create(uint256,bytes32,string,address)" \
    "$CURVE_ID" "$TREE_ROOT" "$TREE_CID" "$SENDER" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null

  # Get new gate address from logs
  NEW_GATE=$(cast logs --from-block latest --address "$GATE_FACTORY" \
    "CuratedGateCreated(address)" --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --json | \
    jq -r '.[0].topics[1]' | sed 's/0x000000000000000000000000/0x/')
  NEW_GATES+=("$NEW_GATE")

  echo ">>> Adding gate $CURVE_ID: $NEW_GATE"

  # Grant roles to new gate
  cast send "$CURATED_MODULE" "grantRole(bytes32,address)" \
    "$CREATE_NO_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null
  cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
    "$SET_CURVE_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null
  cast send "$OPERATORS_DATA" "grantRole(bytes32,address)" \
    "$SETTER_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null

  # Update deploy config JSON
  TMP_FILE=$(mktemp)
  jq --arg gate "$NEW_GATE" '.CuratedGates += [$gate]' "$CM_DEPLOY_CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$CM_DEPLOY_CONFIG"
done

# Revoke temporary roles from SENDER
echo ">>> Revoking roles..."
cast send "$ACCOUNTING" "revokeRole(bytes32,address)" \
  "$MANAGE_CURVES_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null
cast send "$CURATED_MODULE" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null
cast send "$ACCOUNTING" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null
cast send "$OPERATORS_DATA" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null

echo ""
echo "Next: Run ./update-curated-trees.sh to update merkle trees"
echo ""
echo "=== Complete ==="
