####
# Fork helper scripts
####

# Gets bond curve info from Accounting
get-curve-info id:
    cast call --rpc-url=$RPC_URL $(jq -r '.Accounting' ./artifacts/{{chain}}/deploy-{{chain}}.json) \
         'getCurveInfo' {{id}}

vote-add-module:
    just _impersonate-script SimulateVote --sig="addModule"

vote-upgrade:
    just _impersonate-script SimulateVote --sig="upgrade"
    just _impersonate-script SimulateVote --sig="postUpgrade"

public-release:
    just _impersonate-script PauseResume --sig="publicRelease"

pause-csm:
    just _impersonate-script PauseResume --sig="pauseCSM"

resume-csm:
    just _impersonate-script PauseResume --sig="resumeCSM"

pause-accounting:
    just _impersonate-script PauseResume --sig="pauseAccounting"

resume-accounting:
    just _impersonate-script PauseResume --sig="resumeAccounting"

grant-role role where who:
    just _impersonate-script Roles --sig="grantRole\(bytes32,address,address\)" -- {{role}} {{where}} {{who}}

propose-reward noId address:
    just _impersonate-script NodeOperators --sig="proposeRewardAddress\(uint256,address\)" -- {{noId}} {{address}}

propose-manager noId address:
    just _impersonate-script NodeOperators --sig="proposeManagerAddress\(uint256,address\)" -- {{noId}} {{address}}

confirm-reward noId:
    just _impersonate-script NodeOperators --sig="confirmRewardAddress\(uint256\)" -- {{noId}}

confirm-manager noId:
    just _impersonate-script NodeOperators --sig="confirmManagerAddress\(uint256\)" -- {{noId}}

operator-keys noId:
    just _read-script NodeOperators --sig="operatorKeys\(uint256\)" -- {{noId}}

get-pubkey noId keyIndex:
    #!/usr/bin/env bash
    set -euo pipefail
    pk=$(just _read-script NodeOperators --sig="operatorKey\(uint256,uint256\)" -- {{noId}} {{keyIndex}} 2>/dev/null | grep -o '0x.\{96\}') || true
    if [[ -z "$pk" ]]; then
      echo "error: no key found for operator {{noId}} at index {{keyIndex}}" >&2
      exit 1
    fi
    echo "$pk"

operators-count:
    just _read-script NodeOperators --sig="operatorsCount"

get-last-operator:
    #!/usr/bin/env bash
    set -euo pipefail
    count=$(just operators-count 2>&1 | grep -A1 '== Logs ==' | tail -1 | tr -d '[:space:]')
    if [[ -z "$count" || "$count" == "0" ]]; then
      echo "error: no operators" >&2
      exit 1
    fi
    echo $(( count - 1 ))

operator-info noId:
    just _read-script NodeOperators --sig="operatorInfo\(uint256\)" -- {{noId}}

bond-info noId:
    just _read-script NodeOperators --sig="bondInfo\(uint256\)" -- {{noId}}

add-keys noId keysCount:
    just _impersonate-script NodeOperators --sig="addKeys\(uint256,uint256\)" -- {{noId}} {{keysCount}}

unvet-key noId keyIndex:
    just _impersonate-script NodeOperators --sig="unvet\(uint256,uint256\)" -- {{noId}} {{keyIndex}}

exit-keys noId exitedKeysCount:
    just _impersonate-script NodeOperators --sig="exit\(uint256,uint256\)" -- {{noId}} {{exitedKeysCount}}

stuck-keys noId stuckKeysCount:
    just _impersonate-script NodeOperators --sig="stuck\(uint256,uint256\)" -- {{noId}} {{stuckKeysCount}}

defaultAmount := "32000000000000000000"
withdraw-key noId keyIndex exitBalance=defaultAmount slashingPenalty="0":
    just _impersonate-script NodeOperators --sig="withdraw\(uint256,uint256,uint256,uint256\)" -- {{noId}} {{keyIndex}} {{exitBalance}} {{slashingPenalty}}

slash-key noId keyIndex:
    just _impersonate-script NodeOperators --sig="slash\(uint256,uint256\)" -- {{noId}} {{keyIndex}}

remove-key noId keyIndex:
    just _impersonate-script NodeOperators --sig="removeKey\(uint256,uint256\)" -- {{noId}} {{keyIndex}}

deposit-keys depositsCount:
    just _impersonate-script NodeOperators --sig="deposit\(uint256\)" -- {{depositsCount}}

target-limit noId limit:
    just _impersonate-script NodeOperators --sig="targetLimit\(uint256,uint256,uint256\)" -- {{noId}} 1 {{limit}}

target-limit-forced noId limit:
    just _impersonate-script NodeOperators --sig="targetLimit\(uint256,uint256,uint256\)" -- {{noId}} 2 {{limit}}

target-limit-off noId:
    just _impersonate-script NodeOperators --sig="targetLimit\(uint256,uint256,uint256\)" -- {{noId}} 0 0

report-stealing noId amount:
    just _impersonate-script NodeOperators --sig="reportStealing\(uint256,uint256\)" -- {{noId}} {{amount}}

cancel-stealing noId amount:
    just _impersonate-script NodeOperators --sig="cancelStealing\(uint256,uint256\)" -- {{noId}} {{amount}}

settle-stealing noId:
    just _impersonate-script NodeOperators --sig="settleStealing\(uint256\)" -- {{noId}}

compensate-stealing noId amount:
    just _impersonate-script NodeOperators --sig="compensateStealing\(uint256,uint256\)" -- {{noId}} {{amount}}

report-penalty noId amountEth:
    just _impersonate-script NodeOperators --sig="reportGeneralDelayedPenalty\(uint256,uint256\)" -- {{noId}} $(cast to-wei {{amountEth}})

cancel-penalty noId amountEth:
    just _impersonate-script NodeOperators --sig="cancelGeneralDelayedPenalty\(uint256,uint256\)" -- {{noId}} $(cast to-wei {{amountEth}})

settle-penalty noId:
    just _impersonate-script NodeOperators --sig="settleGeneralDelayedPenalty\(uint256\)" -- {{noId}}

compensate-penalty noId:
    just _impersonate-script NodeOperators --sig="compensateGeneralDelayedPenalty\(uint256\)" -- {{noId}}

add-bond noId amountEth:
    just _impersonate-script NodeOperators --sig="addBond\(uint256,uint256\)" -- {{noId}} $(cast to-wei {{amountEth}})

create-bond-debt noId amountEth:
    just _impersonate-script NodeOperators --sig="createBondDebt\(uint256,uint256\)" -- {{noId}} $(cast to-wei {{amountEth}})

topup address amountEth="100":
    cast rpc --rpc-url={{anvil_rpc_url}} anvil_setBalance {{address}} $(cast to-wei {{amountEth}} | cast to-hex --base-in 10)

warp days:
    cast rpc --rpc-url={{anvil_rpc_url}} evm_increaseTime $(( {{days}} * 86400 )) > /dev/null && cast rpc --rpc-url={{anvil_rpc_url}} evm_mine > /dev/null

# Take an anvil snapshot; prints its id
snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    id=$(cast rpc --rpc-url={{anvil_rpc_url}} evm_snapshot | tr -d '"')
    echo "snapshot: $id"

# Revert to the latest snapshot (or an explicit id) and take a fresh one
revert id="":
    #!/usr/bin/env bash
    set -euo pipefail
    rpc="{{anvil_rpc_url}}"
    id="{{id}}"
    if [[ -z "$id" ]]; then
      probe=$(cast rpc --rpc-url="$rpc" evm_snapshot | tr -d '"')
      id=$(printf '0x%x' $(( probe - 1 )))
    fi
    ok=$(cast rpc --rpc-url="$rpc" evm_revert "$id" | tr -d '"')
    if [[ "$ok" != "true" ]]; then
      echo "error: evm_revert failed for id $id (no prior snapshot?)" >&2
      exit 1
    fi
    new_id=$(cast rpc --rpc-url="$rpc" evm_snapshot | tr -d '"')
    echo "reverted to $id; new snapshot: $new_id"

activate-keys noId count:
    just _impersonate-script NodeOperators --sig="activateKeys\(uint256,uint256\)" -- {{noId}} {{count}}

report-balance noId keyIndex balanceEth:
    just _impersonate-script NodeOperators --sig="reportBalance\(uint256,uint256,uint256\)" -- {{noId}} {{keyIndex}} $(cast to-wei {{balanceEth}})

get-key-balance noId keyIndex:
    #!/usr/bin/env bash
    set -euo pipefail
    bal=$(just _read-script NodeOperators --sig="keyAllocatedBalance\(uint256,uint256\)" -- {{noId}} {{keyIndex}} 2>&1 | grep -A1 '== Logs ==' | tail -1 | tr -d '[:space:]')
    if [[ -z "$bal" ]]; then
      echo "error: no balance for operator {{noId}} key {{keyIndex}}" >&2
      exit 1
    fi
    echo "$bal"

key-balances noId:
    just _read-script NodeOperators --sig="keyAllocatedBalances\(uint256\)" -- {{noId}}

key-topup noId keyIndex amountEth:
    just _impersonate-script NodeOperators --sig="increaseAllocatedBalance\(uint256,uint256,uint256\)" -- {{noId}} {{keyIndex}} $(cast to-wei {{amountEth}})

topup-active-keys noId:
    just _impersonate-script NodeOperators --sig="topUpActiveKeys\(uint256\)" -- {{noId}}

exit-request noId keyIndex validatorIndex="900000":
    just _impersonate-script NodeOperators --sig="exitRequest\(uint256,uint256,uint256\)" -vvv -- {{noId}} {{keyIndex}} {{validatorIndex}}

# Usage: just create-operator-group 1 90 2 10
# Converts percent to basis points, builds forge array arg
create-operator-group *args:
    #!/usr/bin/env bash
    pairs=""
    set -- {{args}}
    while [ $# -ge 2 ]; do
      bp=$(( $2 * 100 ))
      [ -n "$pairs" ] && pairs="$pairs,"
      pairs="$pairs$1,$bp"
      shift 2
    done
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[true],"id":1}' > /dev/null
    forge script --rpc-url={{anvil_rpc_url}} --timeout 300 -vvv --broadcast --unlocked MetaRegistryHelpers --sig='createOperatorGroup(uint256[])' -- "[$pairs]"
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[false],"id":1}' > /dev/null

create-curated-operator selector operator="0x0000000000000000000000000000000000000000":
    #!/usr/bin/env bash
    set -euo pipefail
    gate=$(just _resolve-gate-addr "{{selector}}")
    just _impersonate-script NodeOperators --sig="createCuratedOperator\(address,address\)" -- "$gate" "{{operator}}"


reset-operator-group noId:
    just _impersonate-script MetaRegistryHelpers --sig="resetOperatorGroup\(uint256\)" -- {{noId}}

set-bond-curve-weight curveId weight:
    just _impersonate-script MetaRegistryHelpers --sig="setBondCurveWeight\(uint256,uint256\)" -- {{curveId}} {{weight}}

seed-cm:
    just create-curated-operator 0
    just create-curated-operator 1
    just create-curated-operator 2
    just create-operator-group 0 34 1 33 2 33

    just add-keys 0 4
    just deposit-keys 100
    just topup-active-keys 0

    just add-keys 1 5
    just deposit-keys 100
    just topup-active-keys 1

    just add-keys 0 6
    just deposit-keys 100
    just topup-active-keys 0

    just add-keys 0 1
    just add-keys 1 1

report-rewards format="v3":
    just make-rewards {{format}}
    just submit-rewards

# format: v2 (legacy array) | v3 (default; {_ver, frames} wrapper, reward_share)
make-rewards format="v3":
    REPORT_FORMAT={{format}} ANVIL_RPC_URL={{anvil_rpc_url}} node script/mock-rewards.mjs

submit-rewards:
    just _impersonate-script OracleReport --sig="submitRewards" --skip-simulation

# Merkle gate helpers
#
# Selector resolution (against $DEPLOY_CONFIG):
#   - 0x… address           -> used as-is
#   - ics                   -> .VettedGate                (CSM)
#   - idvtc                 -> .IdentifiedDVTClusterGate  (CSM)
#   - po|pto|pgo|do|ee|idvc|idvc+|idvc-plus
#                           -> .CuratedGates[i]           (CM)
#   - integer N             -> .CuratedGates[N]           (CM)

_resolve-gate-addr selector:
    #!/usr/bin/env bash
    set -euo pipefail
    sel="{{selector}}"
    if [[ "$sel" =~ ^0x[0-9a-fA-F]{40}$ ]]; then echo "$sel"; exit 0; fi
    cfg="${DEPLOY_CONFIG:?DEPLOY_CONFIG not set}"
    name=$(echo "$sel" | tr '[:upper:]' '[:lower:]')
    case "$name" in
      ics)              q='.VettedGate' ;;
      idvtc)            q='.IdentifiedDVTClusterGate' ;;
      po)               q='.CuratedGates[0]' ;;
      pto)              q='.CuratedGates[1]' ;;
      pgo)              q='.CuratedGates[2]' ;;
      do)               q='.CuratedGates[3]' ;;
      eeo)              q='.CuratedGates[4]' ;;
      iodc)             q='.CuratedGates[5]' ;;
      iodcp)            q='.CuratedGates[6]' ;;
      *)
        if [[ "$name" =~ ^[0-9]+$ ]]; then q=".CuratedGates[$name]"
        else echo "error: unknown gate selector '$sel'" >&2; exit 1
        fi ;;
    esac
    addr=$(jq -re "$q" "$cfg" 2>/dev/null || true)
    if [[ -z "$addr" || "$addr" == "null" ]]; then
      echo "error: $q not found in $cfg" >&2; exit 1
    fi
    echo "$addr"

# Generic: update a Merkle gate tree on the local fork
# Example: just update-gate-tree ics 0xroot... bafk...cid
update-gate-tree selector root cid:
    #!/usr/bin/env bash
    set -euo pipefail
    rpc="{{anvil_rpc_url}}"
    gate=$(just _resolve-gate-addr "{{selector}}")
    code=$(cast code "$gate" --rpc-url="$rpc")
    if [[ -z "$code" || "$code" == "0x" ]]; then
      echo "error: no code at $gate" >&2; exit 1
    fi
    sender=$(cast rpc --rpc-url="$rpc" eth_accounts | jq -r '.[0]')
    admin=$(cast call "$gate" "getRoleMember(bytes32,uint256)(address)" \
        0x0000000000000000000000000000000000000000000000000000000000000000 0 \
        --rpc-url="$rpc")
    role=$(cast keccak SET_TREE_ROLE)
    echo "Gate:   $gate ({{selector}})"
    echo "Admin:  $admin"
    echo "Sender: $sender"
    echo "Root:   {{root}}"
    echo "CID:    {{cid}}"
    cur_root=$(cast call "$gate" "treeRoot()(bytes32)" --rpc-url="$rpc" | tr '[:upper:]' '[:lower:]')
    cur_cid=$(cast call "$gate" "treeCid()(string)" --rpc-url="$rpc" | tr -d '"')
    if [[ "$cur_root" == "$(echo '{{root}}' | tr '[:upper:]' '[:lower:]')" && "$cur_cid" == "{{cid}}" ]]; then
      echo "Already up-to-date, skipping."; exit 0
    fi
    cast rpc --rpc-url="$rpc" anvil_impersonateAccount "$admin" > /dev/null
    cast send "$gate" "grantRole(bytes32,address)" "$role" "$sender" \
        --rpc-url="$rpc" --unlocked --from="$admin" > /dev/null
    cast send "$gate" "setTreeParams(bytes32,string)" "{{root}}" "{{cid}}" \
        --rpc-url="$rpc" --unlocked --from="$sender" > /dev/null
    cast send "$gate" "revokeRole(bytes32,address)" "$role" "$sender" \
        --rpc-url="$rpc" --unlocked --from="$admin" > /dev/null
    echo "Updated."

# Replace gate tree from inline addresses (no temp file), then push to the gate
# Example: just set-gate-addrs ics 0xabc... 0xdef...
set-gate-addrs selector +addresses:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(printf '%s\n' {{addresses}} | npx --yes csm-test-tree /dev/stdin)
    root=$(echo "$out" | awk '/^Root:/ {print $2; exit}')
    cid=$(echo "$out"  | awk '/^CID:/  {print $2; exit}')
    if [[ -z "$root" || -z "$cid" ]]; then
      echo "error: failed to parse csm-test-tree output (CID missing? check PINATA_API_KEY/SECRET):" >&2
      echo "$out" >&2; exit 1
    fi
    echo "Generated tree:"
    echo "  Root: $root"
    echo "  CID:  $cid"
    just update-gate-tree "{{selector}}" "$root" "$cid"

# Read current tree params for any gate
get-gate-tree selector:
    #!/usr/bin/env bash
    set -euo pipefail
    rpc="{{anvil_rpc_url}}"
    gate=$(just _resolve-gate-addr "{{selector}}")
    echo "Gate: $gate ({{selector}})"
    echo "Root: $(cast call "$gate" 'treeRoot()(bytes32)' --rpc-url="$rpc")"
    echo "CID:  $(cast call "$gate" 'treeCid()(string)' --rpc-url="$rpc")"

_impersonate-script *args:
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[true],"id":1}' > /dev/null
    forge script --rpc-url={{anvil_rpc_url}} --timeout 300 -vvv --broadcast --unlocked {{args}}
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[false],"id":1}' > /dev/null

_read-script *args:
    forge script --rpc-url={{anvil_rpc_url}} --timeout 300 -vvv {{args}}
