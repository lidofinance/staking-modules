#!/bin/bash
#
# Prepare Local Hoodi Fork - All Modules
# Prerequisite: Local Hoodi fork already running on http://127.0.0.1:8545
#
# This script:
# 0. Upgrades StakingRouter v3 → v4
# 1. Upgrades CSM to v3 + executes vote
# 2. Deploys CM (Curated Module) v2 + executes vote
# 3. Updates SMDiscovery caches

set -e

# Load .env (replicates direnv's dotenv_if_exists)
set -a; [ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"; set +a

# Configuration
RPC_URL="${ANVIL_RPC_URL:-http://127.0.0.1:8545}"
export RPC_URL
ARTIFACTS_DIR="${ARTIFACTS_DIR:-./artifacts/hoodi/}"
export ARTIFACTS_DIR

LOCAL_PK=$(just _local-private-key)
SENDER=$(cast wallet address "$LOCAL_PK")

echo "=== Prepare Local Hoodi Fork - All Modules ==="
echo "RPC_URL: $RPC_URL"
echo "SENDER: $SENDER"
echo ""

# Step 0: StakingRouter v3 → v4 Upgrade
SR_PROXY=0xCc820558B39ee15C7C45B59390B503b83fb499A8
SR_NEW_IMPL=0x44d0b2B95d2C2bDF73FE4f5cD7E3A930494E5B1f
AGENT=0x0534aA41907c9631fae990960bCC72d75fA7cfeD

LIDO=0x3508A952176b3c15387C97BE809eaffB1982176a
ACCOUNTING_ORACLE=0xcb883B1bD0a41512b42D2dB267F2A2cd919FB216
ACCOUNTING=0x9b5b78D1C9A3238bF24662067e34c57c83E8c354
DEPOSIT_SECURITY_MODULE=0x2F0303F20E0795E6CCd17BD5efE791A586f28E03
TRIGGERABLE_WITHDRAWALS_GATEWAY=0x6679090D92b08a2a686eF8614feECD8cDFE209db
VALIDATOR_EXIT_DELAY_VERIFIER=0xa5F5A9360275390fF9728262a29384399f38d2f0

CSM_PROXY=0x79CEf36D84743222f37765204Bec41E92a93E59d

SR_VERSION=$(cast call "$SR_PROXY" "getContractVersion()(uint256)" --rpc-url "$RPC_URL")
if [ "$SR_VERSION" -lt 4 ]; then
  echo ">>> Upgrading StakingRouter v3 → v4..."

  cast rpc anvil_impersonateAccount "$AGENT" --rpc-url "$RPC_URL"
  cast rpc anvil_setBalance "$AGENT" "0x8AC7230489E80000" --rpc-url "$RPC_URL"

  CALLDATA=$(cast calldata "finalizeUpgrade_v4()")
  cast send --unlocked --from "$AGENT" "$SR_PROXY" \
    "proxy__upgradeToAndCall(address,bytes,bool)" \
    "$SR_NEW_IMPL" "$CALLDATA" false \
    --rpc-url "$RPC_URL"

  grant_sr_role() {
    local role_hash
    role_hash=$(cast keccak "$1")
    echo "  $1 → $2"
    cast send --unlocked --from "$AGENT" "$SR_PROXY" \
      "grantRole(bytes32,address)" "$role_hash" "$2" \
      --rpc-url "$RPC_URL" > /dev/null
  }

  grant_sr_role "STAKING_MODULE_MANAGE_ROLE"            "$AGENT"
  grant_sr_role "STAKING_MODULE_UNVETTING_ROLE"          "$DEPOSIT_SECURITY_MODULE"
  grant_sr_role "REPORT_EXITED_VALIDATORS_ROLE"          "$ACCOUNTING_ORACLE"
  grant_sr_role "REPORT_REWARDS_MINTED_ROLE"             "$LIDO"
  grant_sr_role "REPORT_REWARDS_MINTED_ROLE"             "$ACCOUNTING"
  grant_sr_role "REPORT_VALIDATOR_EXIT_TRIGGERED_ROLE"   "$TRIGGERABLE_WITHDRAWALS_GATEWAY"
  grant_sr_role "REPORT_VALIDATOR_EXITING_STATUS_ROLE"   "$VALIDATOR_EXIT_DELAY_VERIFIER"

  cast rpc anvil_stopImpersonatingAccount "$AGENT" --rpc-url "$RPC_URL"

  echo -n "SR contract version: "
  cast call "$SR_PROXY" "getContractVersion()(uint256)" --rpc-url "$RPC_URL"
  echo "Done"
else
  echo ">>> SR already v4, skipping"
fi
echo ""

# Step 1: CSM v3 Upgrade
CSM_VERSION=$(cast call "$CSM_PROXY" "getInitializedVersion()(uint64)" --rpc-url "$RPC_URL")
if [ "$CSM_VERSION" -lt 3 ]; then
  echo ">>> Executing CSM v3 proxy upgrades..."
  UPGRADE_CONFIG="$ARTIFACTS_DIR/upgrade-v3-hoodi.json"

  # Precompute finalize calldata
  FINALIZE_V3=$(cast calldata "finalizeUpgradeV3()")
  # consensusVersion=4 per DeployHoodi.s.sol / DeployMainnet.s.sol
  FINALIZE_V3_ORACLE=$(cast calldata "finalizeUpgradeV3(uint256)" 4)

  # Enable global auto-impersonation (same as _impersonate-script in fork.just)
  cast rpc anvil_autoImpersonateAccount true --rpc-url "$RPC_URL" > /dev/null

  upgrade_proxy() {
    local proxy=$1 impl=$2 calldata=${3:-""}
    local admin retries=3
    admin=$(cast call "$proxy" "proxy__getAdmin()(address)" --rpc-url "$RPC_URL")
    cast rpc anvil_setBalance "$admin" "0x8AC7230489E80000" --rpc-url "$RPC_URL" > /dev/null
    for ((i=1; i<=retries; i++)); do
      if [ -n "$calldata" ]; then
        cast send --unlocked --from "$admin" "$proxy" \
          "proxy__upgradeToAndCall(address,bytes)" "$impl" "$calldata" \
          --rpc-url "$RPC_URL" > /dev/null && return 0
      else
        cast send --unlocked --from "$admin" "$proxy" \
          "proxy__upgradeTo(address)" "$impl" \
          --rpc-url "$RPC_URL" > /dev/null && return 0
      fi
      echo "    attempt $i/$retries failed, retrying..."
      sleep 1
    done
    echo "    ERROR: upgrade failed after $retries attempts"
    return 1
  }

  echo "  CSModule"
  upgrade_proxy \
    "$(jq -r .CSModule "$UPGRADE_CONFIG")" \
    "$(jq -r .CSModuleImpl "$UPGRADE_CONFIG")" \
    "$FINALIZE_V3"

  echo "  ParametersRegistry"
  upgrade_proxy \
    "$(jq -r .ParametersRegistry "$UPGRADE_CONFIG")" \
    "$(jq -r .ParametersRegistryImpl "$UPGRADE_CONFIG")" \
    "$FINALIZE_V3"

  echo "  FeeOracle"
  upgrade_proxy \
    "$(jq -r .FeeOracle "$UPGRADE_CONFIG")" \
    "$(jq -r .FeeOracleImpl "$UPGRADE_CONFIG")" \
    "$FINALIZE_V3_ORACLE"

  echo "  VettedGate"
  upgrade_proxy \
    "$(jq -r .VettedGate "$UPGRADE_CONFIG")" \
    "$(jq -r .VettedGateImpl "$UPGRADE_CONFIG")"

  echo "  Accounting"
  upgrade_proxy \
    "$(jq -r .Accounting "$UPGRADE_CONFIG")" \
    "$(jq -r .AccountingImpl "$UPGRADE_CONFIG")" \
    "$FINALIZE_V3"

  echo "  FeeDistributor"
  upgrade_proxy \
    "$(jq -r .FeeDistributor "$UPGRADE_CONFIG")" \
    "$(jq -r .FeeDistributorImpl "$UPGRADE_CONFIG")" \
    "$FINALIZE_V3"

  echo "  ExitPenalties"
  upgrade_proxy \
    "$(jq -r .ExitPenalties "$UPGRADE_CONFIG")" \
    "$(jq -r .ExitPenaltiesImpl "$UPGRADE_CONFIG")"

  echo "  ValidatorStrikes"
  upgrade_proxy \
    "$(jq -r .ValidatorStrikes "$UPGRADE_CONFIG")" \
    "$(jq -r .ValidatorStrikesImpl "$UPGRADE_CONFIG")"

  cast rpc anvil_autoImpersonateAccount false --rpc-url "$RPC_URL" > /dev/null
  echo "Done"
else
  echo ">>> CSM already v3, skipping"
fi
echo ""

# Step 2: CM v2 Deployment

echo ">>> Executing CM add module vote..."
DEPLOY_CONFIG="$ARTIFACTS_DIR/curated/deploy-hoodi.json" just vote-add-curated-module
echo "Done"
echo ""

# Step 3: Update SMDiscovery caches
SM_DISCOVERY="0xC4288A3070D8DA4c7F5DBEC335a9BB31489fDFf1"
echo ">>> Updating SMDiscovery caches..."
cast send "$SM_DISCOVERY" "updateModuleCache(uint256)" 5 \
  --rpc-url="$RPC_URL" --private-key="$LOCAL_PK"
echo "Done"
echo ""

# Summary
echo "=== Summary ==="
echo "SR v4: Upgraded"
echo "CSM v3: Upgraded"
echo "CM v2: Deployed"
echo "SMDiscovery caches: Updated"
echo ""
echo "Next: Run ./update-curated-trees.sh to update allowed addresses"
echo ""
echo "=== Done ==="
