deploy_script_name := "Deploy" + chain_script_suffix
deploy_script_path := "script" / "csm" / deploy_script_name + ".s.sol:" + deploy_script_name

csm_artifacts_latest_dir := "./artifacts/latest/csm/"
csm_artifacts_local_dir := "./artifacts/local/csm/"
csm_latest_deploy_config_path := csm_artifacts_latest_dir + "deploy-" + chain + ".json"
csm_local_deploy_config_path := csm_artifacts_local_dir + "deploy-" + chain + ".json"

# Deployment

deploy-csm *args:
    ARTIFACTS_DIR={{csm_artifacts_local_dir}} \
        just _deploy-generic {{deploy_script_path}} {{anvil_rpc_url}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} {{anvil_rpc_url}} "" "run-latest.json" {{csm_local_deploy_config_path}}

deploy-csm-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_latest_dir}} \
        just _deploy-live-generic {{deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} $RPC_URL "" "run-latest.json" {{csm_latest_deploy_config_path}}

deploy-csm-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_latest_dir}} \
        just _deploy-live-generic-no-confirm {{deploy_script_path}} --broadcast {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} $RPC_URL "" "run-latest.json" {{csm_latest_deploy_config_path}}

deploy-csm-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR={{csm_artifacts_local_dir}} \
        just _deploy-live-generic-dry {{deploy_script_path}} {{args}}
    just _finalize-broadcast-artifacts {{deploy_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{csm_local_deploy_config_path}}

verify-csm-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=hoodi for testnet deployment"
    just _verify-live-generic {{deploy_script_path}} {{args}}

# Local fork flows

# Start/reuse local fork and keep it running after deployment.
deploy-csm-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    just _fork-up > /dev/null

    just deploy-csm {{args}}
    just _warn "anvil is kept running in the background: {{anvil_rpc_url}}"

# Deploy CSM from scratch, add module to the SR, and run deployment and integration tests
test-csm-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    local_private_key="$(just _local-private-key)"
    just deploy-csm --silent --private-key="${local_private_key}" {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{csm_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-module
    just test-deployment-full-afterVote {{args}}
    just test-integration {{args}}

# Deploy CSM from scratch and run deployment tests
test-csm-full-deploy *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    local_private_key="$(just _local-private-key)"
    just deploy-csm --private-key="${local_private_key}" {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{csm_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}
