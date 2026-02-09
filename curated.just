
curated_deploy_script_name := "Deploy" + chain_script_suffix
curated_deploy_config_path := "artifacts" / chain / "curated" / "deploy-" + chain + ".json"

curated_deploy_script_path := "script" / "curated" / curated_deploy_script_name + ".s.sol:" + curated_deploy_script_name
curated_artifacts_latest_dir := "./artifacts/latest/curated/"
curated_artifacts_local_dir := "./artifacts/local/curated/"
curated_local_transactions_path := curated_artifacts_local_dir + "transactions.json"
curated_local_deploy_config_path := curated_artifacts_local_dir + "deploy-" + chain + ".json"

deploy-curated *args:
    mkdir -p {{curated_artifacts_local_dir}}
    just _deploy-generic {{curated_deploy_script_path}} {{anvil_rpc_url}} {{args}}

deploy-curated-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} just _deploy-curated-live {{args}}

    just _copy-run-latest {{curated_deploy_script_name}} $RPC_URL {{curated_deploy_config_path}}

deploy-curated-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_latest_dir}}
    ARTIFACTS_DIR={{curated_artifacts_latest_dir}} just _deploy-curated-live-no-confirm --broadcast {{args}}

    just _copy-run-latest {{curated_deploy_script_name}} $RPC_URL {{curated_deploy_config_path}}

_deploy-curated-live *args:
    just _deploy-live-generic {{curated_deploy_script_path}} {{args}}

deploy-curated-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{curated_artifacts_local_dir}}
    ARTIFACTS_DIR={{curated_artifacts_local_dir}} just _deploy-live-generic-dry {{curated_deploy_script_path}} {{args}}
    just _copy-run-latest-dry {{curated_deploy_script_name}} $RPC_URL {{curated_local_transactions_path}}

verify-curated-live *args:
    just _warn "Pass --chain=your_chain manually when running curated deployments"
    just _verify-live-generic {{curated_deploy_script_path}} {{args}}

_deploy-curated-live-no-confirm *args:
    just _deploy-live-generic-no-confirm {{curated_deploy_script_path}} {{args}}

vote-add-curated-module:
    just _impersonate-script SimulateVote --sig="addCuratedModule"

test-curated-local *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export ARTIFACTS_DIR={{curated_artifacts_local_dir}}
    just deploy-curated --silent --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{curated_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-curated-module

    just test-deployment-full-afterVote {{args}}

    just test-integration {{args}}

    just kill-fork

# Deploy Curated module from scratch and run deployment tests
test-curated-full-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    export ARTIFACTS_DIR={{curated_artifacts_local_dir}}
    just deploy-curated --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{curated_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}

    just kill-fork

# Run tests on fork with current state
test-curated-current *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}
    export DEPLOY_CONFIG={{curated_deploy_config_path}}

    just test-utils {{args}}

    just kill-fork
