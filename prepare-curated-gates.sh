#!/bin/bash
#
# Curated Gates Reference
#
# All 6 gates and their bond curves are created by the CM deploy script.
# This script reads the deploy config and queries on-chain data to display them.
#
# Prerequisite: Local fork running with CM deployed (prepare-modules.sh)
#

set -e

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CM_DEPLOY_CONFIG="${DEPLOY_CONFIG:-./artifacts/local/curated/deploy-hoodi.json}"

ACCOUNTING=$(jq -r '.Accounting' "$CM_DEPLOY_CONFIG")
GATE_COUNT=$(jq '.CuratedGates | length' "$CM_DEPLOY_CONFIG")

# Gate names (not stored on-chain)
GATE_NAMES=(
  "Professional Operator"
  "Professional Trusted Operator"
  "Public Good Operator"
  "Decentralization Operator"
  "Extra Effort Operator"
  "Intra-Operator DVT Cluster"
)

echo "=== Curated Gates (from $CM_DEPLOY_CONFIG) ==="
echo ""

for i in $(seq 0 $((GATE_COUNT - 1))); do
  GATE=$(jq -r ".CuratedGates[$i]" "$CM_DEPLOY_CONFIG")
  NAME="${GATE_NAMES[$i]:-Gate $((i + 1))}"

  CURVE_ID=$(cast call "$GATE" "curveId()(uint256)" --rpc-url="$RPC_URL")

  # Read curve intervals: struct { (minKeysCount, minBond, trend)[] }
  RAW=$(cast call "$ACCOUNTING" "getCurveInfo(uint256)(((uint256,uint256,uint256)[]))" "$CURVE_ID" --rpc-url="$RPC_URL")
  # Parse intervals and format trend values from wei to ETH
  BOND_DESC=$(echo "$RAW" | grep -oE '\([0-9]+, [0-9]+ \[[^]]*\], [0-9]+ \[[^]]*\]\)' | while read -r interval; do
    KEYS=$(echo "$interval" | sed 's/(\([0-9]*\),.*/\1/')
    TREND=$(echo "$interval" | sed 's/.*, \([0-9]*\) \[.*/\1/')
    ETH=$(echo "scale=4; $TREND / 1000000000000000000" | bc | sed 's/0*$//;s/\.$//;s/^\./0./')
    echo -n "[$KEYS, $ETH ETH] "
  done)

  echo "Gate $((i + 1)): $NAME"
  echo "  Address:  $GATE"
  echo "  Curve ID: $CURVE_ID"
  echo "  Bond:     $BOND_DESC"
  echo ""
done

echo "See: script/curated/DeployMainnet.s.sol for full configuration"
