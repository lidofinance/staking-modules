
deploy_csm0x02_script_name := "DeployCSM0x02" + chain_script_suffix

deploy_csm0x02_script_path := "script" / "csm0x02" / deploy_csm0x02_script_name + ".s.sol:" + deploy_csm0x02_script_name
csm0x02_artifacts_local_dir := "./artifacts/local/csm0x02/"
csm0x02_artifacts_latest_dir := "./artifacts/latest/csm0x02/"
csm0x02_local_transactions_path := csm0x02_artifacts_local_dir + "transactions.json"
csm0x02_latest_transactions_path := csm0x02_artifacts_latest_dir + "transactions.json"
csm0x02_local_deploy_config_path := csm0x02_artifacts_local_dir + "deploy-" + chain + ".json"
csm0x02_deploy_config_path := "artifacts" / chain / "csm0x02" / "deploy-" + chain + ".json"

deploy-csm0x02 *args:
    mkdir -p {{csm0x02_artifacts_local_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} just _deploy-generic {{deploy_csm0x02_script_path}} {{anvil_rpc_url}} {{args}}

deploy-csm0x02-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_latest_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_latest_dir}} just _deploy-csm0x02-live {{args}}
    just _copy-run-latest {{deploy_csm0x02_script_name}} $RPC_URL {{csm0x02_latest_transactions_path}}

deploy-csm0x02-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_latest_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_latest_dir}} just _deploy-csm0x02-live-no-confirm --broadcast {{args}}
    just _copy-run-latest {{deploy_csm0x02_script_name}} $RPC_URL {{csm0x02_latest_transactions_path}}

_deploy-csm0x02-live *args:
    just _deploy-live-generic {{deploy_csm0x02_script_path}} {{args}}

deploy-csm0x02-live-dry *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    mkdir -p {{csm0x02_artifacts_local_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} just _deploy-live-generic-dry {{deploy_csm0x02_script_path}} {{args}}
    just _copy-run-latest-dry {{deploy_csm0x02_script_name}} $RPC_URL {{csm0x02_local_transactions_path}}

verify-csm0x02-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=hoodi for testnet deployment"
    just _verify-live-generic {{deploy_csm0x02_script_path}} {{args}}

_deploy-csm0x02-live-no-confirm *args:
    just _deploy-live-generic-no-confirm {{deploy_csm0x02_script_path}} {{args}}

vote-add-csm0x02-module:
    just vote-add-module

test-csm0x02-local *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    mkdir -p {{csm0x02_artifacts_local_dir}}

    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} \
        just deploy-csm0x02 --silent --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}}

    export DEPLOY_CONFIG={{csm0x02_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-csm0x02-module

    just test-deployment-full-afterVote {{args}}

    just test-integration {{args}}

    just kill-fork

# Deploy CSM0x02 from scratch and run deployment tests
test-csm0x02-full-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    mkdir -p {{csm0x02_artifacts_local_dir}}
    ARTIFACTS_DIR={{csm0x02_artifacts_local_dir}} \
        just deploy-csm0x02 --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}} -vvv

    export DEPLOY_CONFIG={{csm0x02_local_deploy_config_path}}
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}

    just kill-fork

# Run tests on fork with current state
test-csm0x02-current *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}
    export DEPLOY_CONFIG={{csm0x02_deploy_config_path}}

    just test-utils {{args}}

    just kill-fork
