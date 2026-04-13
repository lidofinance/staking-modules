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

key-topup noId keyIndex amountEth:
    just _impersonate-script NodeOperators --sig="increaseAllocatedBalance\(uint256,uint256,uint256\)" -- {{noId}} {{keyIndex}} $(cast to-wei {{amountEth}})

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

create-curated-operator gateIndex="0" keysCount="0":
    just _impersonate-script NodeOperators --sig="createCuratedOperator\(uint256,uint256\)" -- {{gateIndex}} {{keysCount}}

reset-operator-group noId:
    just _impersonate-script MetaRegistryHelpers --sig="resetOperatorGroup\(uint256\)" -- {{noId}}

set-bond-curve-weight curveId weight:
    just _impersonate-script MetaRegistryHelpers --sig="setBondCurveWeight\(uint256,uint256\)" -- {{curveId}} {{weight}}

seed-cm:
    just create-curated-operator 0
    just create-curated-operator 1
    just create-curated-operator 2
    just create-operator-group 0 34 1 33 2 33
    just add-keys 0 5
    just deposit-keys 5
    just add-keys 1 1
    just activate-keys 0 1
    just key-topup 0 0 2016
    just key-topup 0 1 2016
    just key-topup 0 2 2016
    just key-topup 0 3 1968

report-rewards:
    just make-rewards
    just submit-rewards

make-rewards:
    ANVIL_RPC_URL={{anvil_rpc_url}} node script/mock-rewards.mjs

submit-rewards:
    just _impersonate-script OracleReport --sig="submitRewards" --skip-simulation

_impersonate-script *args:
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[true],"id":1}' > /dev/null
    forge script --rpc-url={{anvil_rpc_url}} --timeout 300 -vvv --broadcast --unlocked {{args}}
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[false],"id":1}' > /dev/null

_read-script *args:
    forge script --rpc-url={{anvil_rpc_url}} --timeout 300 -vvv {{args}}
