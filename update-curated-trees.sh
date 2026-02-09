#!/bin/bash
#
# Update Curated Gates Merkle Trees on Local Hoodi Fork
#
# Generates merkle trees from addresses1..7 files using csm-test-tree
# and updates each corresponding CuratedGate contract.
#
# Prerequisite: Run prepare-modules.sh and prepare-curated-gates.sh first
#

set -e

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="560048"  # Hoodi chain ID
CM_DEPLOY_CONFIG="./artifacts/local/curated/deploy-hoodi.json"

# Preload package to avoid prompts during loop
echo ">>> Preloading csm-test-tree package..."
npx --yes csm-test-tree --help > /dev/null || true

# Read sender address from Anvil (first available account)
SENDER=$(cast rpc eth_accounts --rpc-url="$RPC_URL" | jq -r '.[0]')
if [ -z "$SENDER" ] || [ "$SENDER" = "null" ]; then
  echo "ERROR: Could not read sender address from Anvil at $RPC_URL"
  echo "Make sure Anvil is running: just make-fork"
  exit 1
fi

echo "=== Update Curated Gates Merkle Trees ==="
echo "RPC_URL: $RPC_URL"
echo "SENDER: $SENDER"
echo ""

# Role hashes
SET_TREE_ROLE=$(cast keccak "SET_TREE_ROLE")
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

# Helper function to get DEFAULT_ADMIN_ROLE holder for a contract
get_admin() {
  local contract=$1
  cast call "$contract" "getRoleMember(bytes32,uint256)(address)" \
    "$DEFAULT_ADMIN_ROLE" 0 \
    --rpc-url="$RPC_URL"
}

# Track results for summary
declare -a RESULTS

for i in {1..7}; do
  GATE=$(jq -r ".CuratedGates[$((i-1))]" "$CM_DEPLOY_CONFIG")
  ADDR_FILE="addresses$i"

  # Skip if gate not in deploy config or not deployed
  if [ -z "$GATE" ] || [ "$GATE" = "null" ]; then
    echo ">>> Gate $i: not in deploy config, skipping"
    RESULTS+=("Gate $i: SKIPPED (not deployed)")
    echo ""
    continue
  fi

  CODE=$(cast code "$GATE" --rpc-url="$RPC_URL")
  if [ -z "$CODE" ] || [ "$CODE" = "0x" ]; then
    echo ">>> Gate $i: $GATE has no code, skipping"
    RESULTS+=("Gate $i: SKIPPED (no code at $GATE)")
    echo ""
    continue
  fi

  echo ">>> Gate $i: $GATE (from $ADDR_FILE)"

  # Check if address file exists
  if [ ! -f "$ADDR_FILE" ]; then
    echo "  WARNING: $ADDR_FILE not found, skipping"
    RESULTS+=("Gate $i: SKIPPED (no $ADDR_FILE)")
    echo ""
    continue
  fi

  # Generate merkle tree and upload to IPFS
  echo "  Generating merkle tree..."
  OUTPUT=$(npx csm-test-tree "$ADDR_FILE")
  ROOT=$(echo "$OUTPUT" | grep "Root:" | awk '{print $2}')
  CID=$(echo "$OUTPUT" | grep "CID:" | awk '{print $2}')

  if [ -z "$ROOT" ] || [ -z "$CID" ]; then
    echo "  ERROR: Failed to parse csm-test-tree output"
    echo "  Output was: $OUTPUT"
    RESULTS+=("Gate $i: FAILED (parse error)")
    echo ""
    continue
  fi

  echo "  Root: $ROOT"
  echo "  CID: $CID"

  # Check if tree params already match (normalize formats for comparison)
  CURRENT_ROOT=$(cast call "$GATE" "treeRoot()(bytes32)" --rpc-url="$RPC_URL" | tr '[:upper:]' '[:lower:]')
  CURRENT_CID=$(cast call "$GATE" "treeCid()(string)" --rpc-url="$RPC_URL" | tr -d '"')
  ROOT_LOWER=$(echo "$ROOT" | tr '[:upper:]' '[:lower:]')
  if [ "$CURRENT_ROOT" = "$ROOT_LOWER" ] && [ "$CURRENT_CID" = "$CID" ]; then
    echo "  Tree already up-to-date, skipping"
    RESULTS+=("Gate $i: SKIPPED (unchanged)")
    echo ""
    continue
  fi

  # Get admin and impersonate
  ADMIN=$(get_admin "$GATE")
  echo "  Gate admin: $ADMIN"
  cast rpc anvil_impersonateAccount "$ADMIN" --rpc-url="$RPC_URL" > /dev/null

  # Grant SET_TREE_ROLE to SENDER
  echo "  Granting SET_TREE_ROLE..."
  cast send "$GATE" "grantRole(bytes32,address)" \
    "$SET_TREE_ROLE" "$SENDER" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$ADMIN" > /dev/null

  # Update tree params
  echo "  Updating tree params..."
  cast send "$GATE" "setTreeParams(bytes32,string)" \
    "$ROOT" "$CID" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$SENDER" > /dev/null

  # Revoke SET_TREE_ROLE from SENDER
  echo "  Revoking SET_TREE_ROLE..."
  cast send "$GATE" "revokeRole(bytes32,address)" \
    "$SET_TREE_ROLE" "$SENDER" \
    --rpc-url="$RPC_URL" --chain-id="$CHAIN_ID" --unlocked --from="$ADMIN" > /dev/null

  RESULTS+=("Gate $i: $ROOT | $CID")
  echo "  Done"
  echo ""
done

# Summary
echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
  echo "  $result"
done
echo ""
echo "=== Complete ==="
