curated_deploy_script_name := "Deploy" + chain_script_suffix
curated_deploy_config_path := "artifacts" / chain / "curated" / "deploy-" + chain + ".json"
curated_deploy_script_path := "script" / "curated" / curated_deploy_script_name + ".s.sol:" + curated_deploy_script_name

curated_artifacts_latest_dir := "./artifacts/latest/curated/"
curated_artifacts_local_dir := "./artifacts/local/curated/"
curated_local_transactions_path := curated_artifacts_local_dir + "transactions.json"
curated_local_deploy_config_path := curated_artifacts_local_dir + "deploy-" + chain + ".json"

# Deployment

deploy-curated *args:
    mkdir -p {{curated_artifacts_local_dir}}
    just _deploy-generic {{curated_deploy_script_path}} {{anvil_rpc_url}} {{args}}

deploy-curated-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} \
        just _deploy-live-generic {{curated_deploy_script_path}} {{args}}
    just _copy-broadcast-json {{curated_deploy_script_name}} $RPC_URL "" "run-latest.json" {{curated_deploy_config_path}}

deploy-curated-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} \
        just _deploy-live-generic-no-confirm {{curated_deploy_script_path}} --broadcast {{args}}
    just _copy-broadcast-json {{curated_deploy_script_name}} $RPC_URL "" "run-latest.json" {{curated_deploy_config_path}}

deploy-curated-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_local_dir}}
    ARTIFACTS_DIR={{curated_artifacts_local_dir}} \
        just _deploy-live-generic-dry {{curated_deploy_script_path}} {{args}}
    just _copy-broadcast-json {{curated_deploy_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{curated_local_transactions_path}}

verify-curated-live *args:
    just _warn "Pass --chain=your_chain manually when running curated deployments"
    just _verify-live-generic {{curated_deploy_script_path}} {{args}}

# Governance helpers

vote-add-curated-module:
    just _impersonate-script SimulateVote --sig="addCuratedModule"

# Local fork flows

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

# Run utility tests on fork with current state
test-curated-current *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export RPC_URL={{anvil_rpc_url}}
    export DEPLOY_CONFIG={{curated_deploy_config_path}}

    just test-utils {{args}}
