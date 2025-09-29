####
# Fork helper scripts
####

# Gets bond curve info from CSAccounting
get-curve-info id:
    cast call --rpc-url=$RPC_URL $(jq -r '.CSAccounting' ./artifacts/{{chain}}/deploy-{{chain}}.json) \
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

propose-reward noId address:
    just _impersonate-script NodeOperators --sig="proposeRewardAddress\(uint256,address\)" -- {{noId}} {{address}}

propose-manager noId address:
    just _impersonate-script NodeOperators --sig="proposeManagerAddress\(uint256,address\)" -- {{noId}} {{address}}

confirm-reward noId:
    just _impersonate-script NodeOperators --sig="confirmRewardAddress\(uint256\)" -- {{noId}}

confirm-manager noId:
    just _impersonate-script NodeOperators --sig="confirmManagerAddress\(uint256\)" -- {{noId}}

add-keys noId keysCount:
    just _impersonate-script NodeOperators --sig="addKeys\(uint256,uint256\)" -- {{noId}} {{keysCount}}

unvet-keys noId vettedKeysCount:
    just _impersonate-script NodeOperators --sig="unvet\(uint256,uint256\)" -- {{noId}} {{vettedKeysCount}}

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

exit-request noId validatorIndex validatorPubKey:
    just _impersonate-script NodeOperators --sig="exitRequest\(uint256,uint256,bytes\)" -vvv -- {{noId}} {{validatorIndex}} {{validatorPubKey}}

_impersonate-script *args:
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[true],"id":1}' > /dev/null
    forge script --rpc-url={{anvil_rpc_url}} -vvv --broadcast --unlocked {{args}}
    curl -sS {{anvil_rpc_url}} --header 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"anvil_autoImpersonateAccount","params":[false],"id":1}' > /dev/null
