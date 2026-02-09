
deploy_script_name := "Deploy" + chain_script_suffix
deploy_csm_implementations_script_name := "DeployCSMImplementations" + chain_script_suffix
deploy_config_path := "artifacts" / chain / "deploy-" + chain + ".json"

deploy_script_path := "script" / "csm" / deploy_script_name + ".s.sol:" + deploy_script_name
deploy_csm_impls_script_path := "script" / "csm" / deploy_csm_implementations_script_name + ".s.sol:" + deploy_csm_implementations_script_name
csm_artifacts_latest_dir := "./artifacts/latest/"
csm_artifacts_local_dir := "./artifacts/local/"
csm_latest_transactions_path := csm_artifacts_latest_dir + "transactions.json"
csm_local_transactions_path := csm_artifacts_local_dir + "transactions.json"
csm_local_deploy_config_path := csm_artifacts_local_dir + "deploy-" + chain + ".json"
csm_local_upgrade_config_path := csm_artifacts_local_dir + "upgrade-" + chain + ".json"

deploy-csm *args:
    just _deploy-generic {{deploy_script_path}} {{anvil_rpc_url}} {{args}}

deploy-csm-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_latest_dir}} just _deploy-live {{args}}
    just _copy-run-latest {{deploy_script_name}} $RPC_URL {{csm_latest_transactions_path}}

deploy-csm-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_latest_dir}} just _deploy-live-no-confirm --broadcast {{args}}
    just _copy-run-latest {{deploy_script_name}} $RPC_URL {{csm_latest_transactions_path}}

deploy-csm-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_local_dir}} just _deploy-live-generic-dry {{deploy_script_path}} {{args}}
    just _copy-run-latest-dry {{deploy_script_name}} $RPC_URL {{csm_local_transactions_path}}

verify-csm-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=hoodi for testnet deployment"
    just _verify-live-generic {{deploy_script_path}} {{args}}

deploy-csm-impl *args:
    just _deploy-csm-impl {{args}}

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
deploy-csm-impl-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_latest_dir}} just _deploy-csm-impl --broadcast --verify {{args}}

    just _copy-file \
        ./broadcast/{{deploy_csm_implementations_script_name}}.s.sol/$(cast chain-id --rpc-url=$RPC_URL)/deploy-latest.json \
        {{csm_latest_transactions_path}}

deploy-csm-impl-dry *args:
    just _deploy-csm-impl {{args}}

    just _copy-file \
        ./broadcast/{{deploy_csm_implementations_script_name}}.s.sol/$(cast chain-id --rpc-url=$RPC_URL)/dry-run/deploy-latest.json \
        {{csm_local_transactions_path}}

upgrade-csm-v3:
    just vote-upgrade

deploy *args:
    just _warn "Deprecated. Use deploy-csm."
    just deploy-csm {{args}}

deploy-live *args:
    just _warn "Deprecated. Use deploy-csm-live."
    just deploy-csm-live {{args}}

deploy-live-no-confirm *args:
    just _warn "Deprecated. Use deploy-csm-live-no-confirm."
    just deploy-csm-live-no-confirm {{args}}

deploy-live-dry *args:
    just _warn "Deprecated. Use deploy-csm-live-dry."
    just deploy-csm-live-dry {{args}}

verify-live *args:
    just _warn "Deprecated. Use verify-csm-live."
    just verify-csm-live {{args}}

deploy-impl-live *args:
    just _warn "Deprecated. Use deploy-csm-impl-live."
    just deploy-csm-impl-live {{args}}

deploy-impl-dry *args:
    just _warn "Deprecated. Use deploy-csm-impl-dry."
    just deploy-csm-impl-dry {{args}}

upgrade-v3:
    just _warn "Deprecated. Use upgrade-csm-v3."
    just upgrade-csm-v3

deploy-local *args:
    just make-fork &
    @while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy-csm {{args}}
    just _warn "anvil is kept running in the background: {{anvil_rpc_url}}"

# Deploy CSM v3 components, upgrade CSM, run deployment, integration, and post-upgrade tests
test-csm-upgrade *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}

    SKIP_LEGACY_QUEUE_CHECK=1 just _deploy-csm-impl --broadcast --private-key=`cat localhost.json | jq -r ".private_keys[0]"`

    export DEPLOY_CONFIG={{csm_local_upgrade_config_path}}
    export VOTE_PREV_BLOCK=`cast block-number -r $RPC_URL`

    just vote-upgrade

    just test-deployment-full-afterVote {{args}}

    just test-post-upgrade {{args}}

    just kill-fork

# Deploy CSM from scratch, add module to the SR, and run deployment and integration tests
test-csm-local *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy-csm --silent --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{csm_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-module

    just test-deployment-full-afterVote {{args}}

    just test-integration {{args}}

    just kill-fork

# Deploy CSM from scratch and run deployment tests
test-csm-full-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy-csm --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{csm_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}

    just kill-fork

# Deploy CSM v3 components and run deployment tests
test-csm-v3-only-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}

    SKIP_LEGACY_QUEUE_CHECK=1 just _deploy-csm-impl --broadcast --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{csm_local_upgrade_config_path}}

    just test-deployment-csm-v3-only-scratch {{args}}

    just kill-fork

# Run tests on fork with current state
test-csm-current *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}

    export DEPLOY_CONFIG={{deploy_config_path}}

    just test-utils

    just kill-fork

# Run all deployment tests that should be executed against CSM v3 scratch deployment before the module upgrade vote
test-deployment-csm-v3-only-scratch *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '(.*_afterVote.*)|(.*_onlyFull.*)' -vvv --show-progress {{args}}

_deploy-live *args:
    just _deploy-live-generic {{deploy_script_path}} {{args}}

_deploy-live-no-confirm *args:
    just _deploy-live-generic-no-confirm {{deploy_script_path}} {{args}}

_deploy-csm-impl *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{deploy_csm_impls_script_path}} --sig="deploy(string,string)" \
            --rpc-url ${RPC_URL} {{disable_code_size_limit}} {{args}} \
            -- {{deploy_config_path}} `git rev-parse HEAD`
