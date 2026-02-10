deploy_csm0x02_script_name := "DeployCSM0x02" + chain_script_suffix
deploy_csm0x02_script_path := "script" / "csm0x02" / deploy_csm0x02_script_name + ".s.sol:" + deploy_csm0x02_script_name

csm0x02_artifacts_local_dir := "./artifacts/local/csm0x02/"
csm0x02_artifacts_latest_dir := "./artifacts/latest/csm0x02/"
csm0x02_local_transactions_path := csm0x02_artifacts_local_dir + "transactions.json"
csm0x02_latest_transactions_path := csm0x02_artifacts_latest_dir + "transactions.json"
csm0x02_local_deploy_config_path := csm0x02_artifacts_local_dir + "deploy-" + chain + ".json"
csm0x02_deploy_config_path := "artifacts" / chain / "csm0x02" / "deploy-" + chain + ".json"

# Deployment

deploy-csm0x02 *args:
    mkdir -p {{csm0x02_artifacts_local_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} \
        just _deploy-generic {{deploy_csm0x02_script_path}} {{anvil_rpc_url}} {{args}}

deploy-csm0x02-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_latest_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_latest_dir}} \
        just _deploy-live-generic {{deploy_csm0x02_script_path}} {{args}}
    just _copy-broadcast-json {{deploy_csm0x02_script_name}} $RPC_URL "" "run-latest.json" {{csm0x02_latest_transactions_path}}

deploy-csm0x02-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_latest_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_latest_dir}} \
        just _deploy-live-generic-no-confirm {{deploy_csm0x02_script_path}} --broadcast {{args}}
    just _copy-broadcast-json {{deploy_csm0x02_script_name}} $RPC_URL "" "run-latest.json" {{csm0x02_latest_transactions_path}}

deploy-csm0x02-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_local_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} \
        just _deploy-live-generic-dry {{deploy_csm0x02_script_path}} {{args}}
    just _copy-broadcast-json {{deploy_csm0x02_script_name}} $RPC_URL "/dry-run" "run-latest.json" {{csm0x02_local_transactions_path}}

verify-csm0x02-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=hoodi for testnet deployment"
    just _verify-live-generic {{deploy_csm0x02_script_path}} {{args}}

# Governance helpers

vote-add-csm0x02-module:
    just vote-add-module

# Local fork flows

# Start/reuse local fork and keep it running after deployment.
deploy-csm0x02-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    just _fork-up > /dev/null

    just deploy-csm0x02 {{args}}
    just _warn "anvil is kept running in the background: {{anvil_rpc_url}}"

# Deploy CSM0x02 from scratch, add module to the SR, and run deployment and integration tests.
test-csm0x02-local *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}}
    local_private_key="$(just _local-private-key)"
    just deploy-csm0x02 --silent --private-key="${local_private_key}" {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{csm0x02_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-csm0x02-module
    just test-deployment-full-afterVote {{args}}
    just test-integration {{args}}

# Deploy CSM0x02 from scratch and run deployment tests
test-csm0x02-full-deploy *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}}
    local_private_key="$(just _local-private-key)"
    just deploy-csm0x02 --private-key="${local_private_key}" {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{csm0x02_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}

# Run utility tests on fork with current state
test-csm0x02-current *args:
    #!/usr/bin/env bash
    set -euo pipefail

    eval "$(just _fork-up-and-down)"

    export RPC_URL={{anvil_rpc_url}}
    export DEPLOY_CONFIG={{csm0x02_deploy_config_path}}

    just test-utils {{args}}
