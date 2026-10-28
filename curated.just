curated_deploy_script_name := "Deploy" + chain_script_suffix
curated_deploy_config_path := "artifacts" / chain / "curated" / "deploy-" + chain + ".json"
curated_deploy_script_path := "script" / "curated" / curated_deploy_script_name + ".s.sol:" + curated_deploy_script_name

curated_artifacts_latest_dir := "./artifacts/latest/curated/"
curated_artifacts_local_dir := "./artifacts/local/curated/"
curated_latest_transactions_path := curated_artifacts_latest_dir + "transactions.json"
curated_local_transactions_path := curated_artifacts_local_dir + "transactions.json"
curated_latest_deploy_config_path := curated_artifacts_latest_dir + "deploy-" + chain + ".json"
curated_local_deploy_config_path := curated_artifacts_local_dir + "deploy-" + chain + ".json"
curated_module_script_name := "DeployCuratedModule"
curated_module_script_path := "script/curated/" + curated_module_script_name + ".s.sol:" + curated_module_script_name
curated_latest_upgrade_config_path := curated_artifacts_latest_dir + "upgrade-" + chain + ".json"
curated_local_upgrade_config_path := curated_artifacts_local_dir + "upgrade-" + chain + ".json"

# Deployment

deploy-curated *args:
    mkdir -p {{curated_artifacts_local_dir}}
    ARTIFACTS_DIR={{curated_artifacts_local_dir}} \
        just _deploy-generic {{curated_deploy_script_path}} {{anvil_rpc_url}} {{args}}
    just _finalize-broadcast-artifacts {{curated_deploy_script_name}} {{anvil_rpc_url}} "" "run-latest.json" {{curated_local_deploy_config_path}}

deploy-curated-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} \
        just _deploy-live-generic {{curated_deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{curated_deploy_script_name}} $RPC_URL "" "run-latest.json" {{curated_latest_deploy_config_path}}

deploy-curated-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} \
        just _deploy-live-generic-no-confirm {{curated_deploy_script_path}} --broadcast {{args}}
    just _finalize-broadcast-artifacts {{curated_deploy_script_name}} $RPC_URL "" "run-latest.json" {{curated_latest_deploy_config_path}}

deploy-curated-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_local_dir}}
    ARTIFACTS_DIR={{curated_artifacts_local_dir}} \
        just _deploy-live-generic-dry {{curated_deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{curated_deploy_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{curated_local_deploy_config_path}}

verify-curated-live *args:
    just _warn "Pass --chain=your_chain manually when running curated deployments"
    just _verify-live-generic {{curated_deploy_script_path}} {{args}}

# Implementation deployment

deploy-curated-impl *args:
    just _copy-file {{curated_deploy_config_path}} {{curated_local_upgrade_config_path}}
    DEPLOY_CONFIG={{curated_local_upgrade_config_path}} \
        just _deploy-generic {{curated_module_script_path}} {{anvil_rpc_url}} {{args}}
    just _finalize-broadcast-artifacts {{curated_module_script_name}} {{anvil_rpc_url}} "" "run-latest.json" {{curated_local_upgrade_config_path}}

deploy-curated-impl-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    just _copy-file {{curated_deploy_config_path}} {{curated_latest_upgrade_config_path}}
    DEPLOY_CONFIG={{curated_latest_upgrade_config_path}} \
        just _deploy-live-generic {{curated_module_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{curated_module_script_name}} $RPC_URL "" "run-latest.json" {{curated_latest_upgrade_config_path}}

deploy-curated-impl-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    just _copy-file {{curated_deploy_config_path}} {{curated_latest_upgrade_config_path}}
    DEPLOY_CONFIG={{curated_latest_upgrade_config_path}} \
        just _deploy-live-generic-no-confirm {{curated_module_script_path}} --broadcast {{args}}
    just _finalize-broadcast-artifacts {{curated_module_script_name}} $RPC_URL "" "run-latest.json" {{curated_latest_upgrade_config_path}}

deploy-curated-impl-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    just _copy-file {{curated_deploy_config_path}} {{curated_local_upgrade_config_path}}
    DEPLOY_CONFIG={{curated_local_upgrade_config_path}} \
        just _deploy-live-generic-dry {{curated_module_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{curated_module_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{curated_local_upgrade_config_path}}

verify-curated-impl-live *args:
    just _warn "Pass --chain=your_chain manually when running curated deployments"
    DEPLOY_CONFIG={{curated_latest_upgrade_config_path}} \
        just _verify-live-generic {{curated_module_script_path}} {{args}}

# Governance helpers

vote-add-curated-module:
    just _impersonate-script SimulateVote --sig="addCuratedModule"

vote-upgrade-curated:
    just _impersonate-script SimulateVote --sig="upgradeCurated"

# Local fork flows

# Upgrade the deployed Curated module, then run upgrade and integration tests.
test-curated-upgrade-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    local_private_key="$(just _local-private-key)"
    just deploy-curated-impl --silent --private-key="${local_private_key}" {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{curated_local_upgrade_config_path}}
    export RPC_URL={{anvil_rpc_url}}
    export VOTE_PREV_BLOCK="$(cast block-number --rpc-url "$RPC_URL")"

    just vote-upgrade-curated
    forge test --match-path 'test/fork/vote-upgrade/CuratedV2Upgrade.t.sol' --threads 1 -vvv {{args}}
    just test-integration {{args}}

# Start/reuse local fork and keep it running after deployment.
deploy-curated-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    just _fork-up > /dev/null

    just deploy-curated {{args}}
    just _warn "anvil is kept running in the background: {{anvil_rpc_url}}"

# Deploy Curated module from scratch, add module to the SR, and run deployment and integration tests.
test-curated-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export ARTIFACTS_DIR={{curated_artifacts_local_dir}}
    local_private_key="$(just _local-private-key)"
    just deploy-curated --silent --private-key="${local_private_key}" {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{curated_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-curated-module
    just test-deployment-full-afterVote {{args}}
    just test-integration {{args}}

# Deploy Curated module from scratch and run deployment tests
test-curated-full-deploy *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export ARTIFACTS_DIR={{curated_artifacts_local_dir}}
    local_private_key="$(just _local-private-key)"
    just deploy-curated --private-key="${local_private_key}" {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{curated_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}
