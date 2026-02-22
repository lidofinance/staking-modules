#!/bin/bash
#
# Setup Curated Gates on Local Hoodi Fork
# Prerequisite: Run prepare-modules.sh first to deploy CSM v3, CM v2, and CSM 0x02
#
# This script creates curves 2-7 and gates 2-7 (curve 1 and gate 1 already exist from prepare-modules.sh)
# Bond parameters: first key 11 ETH, subsequent 0.6 ETH (curve 7: 0.35 ETH)
#
# Steps:
# 1. Grants required roles to SENDER
# 2. Creates 6 bond curves (curveIds 2-7)
# 3. Deploys 6 curated gates via MerkleGateFactory
# 4. Grants roles to each new gate
# 5. Updates deploy config JSON with new gate addresses
# 6. Revokes temporary roles from SENDER

set -e

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CM_DEPLOY_CONFIG="${DEPLOY_CONFIG:-./artifacts/local/curated/deploy-hoodi.json}"

LOCAL_PK=$(just _local-private-key)
SENDER=$(cast wallet address "$LOCAL_PK")

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
META_REGISTRY=$(jq -r '.MetaRegistry' "$CM_DEPLOY_CONFIG")

# Get admins and impersonate
ACCOUNTING_ADMIN=$(get_admin "$ACCOUNTING")
MODULE_ADMIN=$(get_admin "$CURATED_MODULE")
META_REGISTRY_ADMIN=$(get_admin "$META_REGISTRY")
cast rpc anvil_impersonateAccount "$ACCOUNTING_ADMIN" --rpc-url="$RPC_URL" > /dev/null
cast rpc anvil_impersonateAccount "$MODULE_ADMIN" --rpc-url="$RPC_URL" > /dev/null
cast rpc anvil_impersonateAccount "$META_REGISTRY_ADMIN" --rpc-url="$RPC_URL" > /dev/null

# Role hashes
MANAGE_CURVES_ROLE=$(cast keccak "MANAGE_BOND_CURVES_ROLE")
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

# Grant required roles to SENDER
echo ">>> Granting roles..."
cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
  "$MANAGE_CURVES_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --unlocked --from="$ACCOUNTING_ADMIN" > /dev/null
cast send "$CURATED_MODULE" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --unlocked --from="$MODULE_ADMIN" > /dev/null
cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --unlocked --from="$ACCOUNTING_ADMIN" > /dev/null
cast send "$META_REGISTRY" "grantRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --unlocked --from="$META_REGISTRY_ADMIN" > /dev/null

# Bond curves for curveIds 2-7 (curveId 1 already exists from prepare-modules.sh)
# Format: [(minKeys, trendWei), ...]
# Bond parameters: [first_key_ETH, (subsequent_key_ETH)]
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
SET_OPERATOR_INFO_ROLE=$(cast keccak "SET_OPERATOR_INFO_ROLE")

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
    --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null

  # Verify curve ID
  CURVE_COUNT=$(cast call "$ACCOUNTING" "getCurvesCount()(uint256)" --rpc-url="$RPC_URL")
  CURVE_ID=$((CURVE_COUNT - 1))
  if [ "$CURVE_ID" -ne "$EXPECTED_CURVE_ID" ]; then
    echo "ERROR: Expected curveId=$EXPECTED_CURVE_ID but got $CURVE_ID"
    exit 1
  fi

  # Deploy gate via MerkleGateFactory
  # MerkleGateFactory.create(bytes initCalldata, address admin)
  # initCalldata = CuratedGate.initialize(curveId, treeRoot, treeCid, admin)
  INIT_DATA=$(cast calldata "initialize(uint256,bytes32,string,address)" \
    "$CURVE_ID" "$TREE_ROOT" "$TREE_CID" "$SENDER")
  cast send "$GATE_FACTORY" \
    "create(bytes,address)" \
    "$INIT_DATA" "$SENDER" \
    --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null

  # Get new gate address from logs
  # MerkleGateCreated(address indexed gate, address indexed implementation, address indexed admin)
  NEW_GATE=$(cast logs --from-block latest --address "$GATE_FACTORY" \
    "MerkleGateCreated(address,address,address)" --rpc-url="$RPC_URL" --json | \
    jq -r '.[0].topics[1]' | sed 's/0x000000000000000000000000/0x/')
  NEW_GATES+=("$NEW_GATE")

  echo ">>> Adding gate $CURVE_ID: $NEW_GATE"

  # Grant roles to new gate
  cast send "$CURATED_MODULE" "grantRole(bytes32,address)" \
    "$CREATE_NO_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null
  cast send "$ACCOUNTING" "grantRole(bytes32,address)" \
    "$SET_CURVE_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null
  cast send "$META_REGISTRY" "grantRole(bytes32,address)" \
    "$SET_OPERATOR_INFO_ROLE" "$NEW_GATE" \
    --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null

  # Update deploy config JSON
  TMP_FILE=$(mktemp)
  jq --arg gate "$NEW_GATE" '.CuratedGates += [$gate]' "$CM_DEPLOY_CONFIG" > "$TMP_FILE" && mv "$TMP_FILE" "$CM_DEPLOY_CONFIG"
done

# Revoke temporary roles from SENDER
echo ">>> Revoking roles..."
cast send "$ACCOUNTING" "revokeRole(bytes32,address)" \
  "$MANAGE_CURVES_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null
cast send "$CURATED_MODULE" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null
cast send "$ACCOUNTING" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null
cast send "$META_REGISTRY" "revokeRole(bytes32,address)" \
  "$DEFAULT_ADMIN_ROLE" "$SENDER" \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK" > /dev/null

echo ""
echo "Next: Run ./update-curated-trees.sh to update merkle trees"
echo ""
echo "=== Complete ==="
