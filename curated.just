
curated_deploy_script_name := if chain == "mainnet" {
    "DeployMainnet"
} else if chain == "local-devnet" {
    "DeployLocalDevNet"
} else if chain == "hoodi" {
    "DeployHoodi"
} else {
    error("Unsupported curated deployment chain " + chain)
}

curated_deploy_config_path := if chain == "mainnet" {
    "artifacts/mainnet/curated/deploy-mainnet.json"
} else if chain == "local-devnet" {
    "artifacts/local-devnet/curated/deploy-local-devnet.json"
} else if chain == "hoodi" {
    "artifacts/hoodi/curated/deploy-hoodi.json"
} else {
    error("Unsupported curated deployment chain " + chain)
}

curated_deploy_script_path := "script" / "curated" / curated_deploy_script_name + ".s.sol:" + curated_deploy_script_name

deploy-curated *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{curated_deploy_script_path}} --sig="run(string)" --rpc-url {{anvil_rpc_url}} --broadcast --slow {{args}} -- `git rev-parse HEAD`

deploy-curated-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/curated/ just _deploy-curated-live {{args}}

    mkdir -p `dirname {{curated_deploy_config_path}}`
    cp ./broadcast/{{curated_deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        {{curated_deploy_config_path}}

deploy-curated-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/curated/ just _deploy-curated-live-no-confirm --broadcast {{args}}

    mkdir -p `dirname {{curated_deploy_config_path}}`
    cp ./broadcast/{{curated_deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        {{curated_deploy_config_path}}

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
_deploy-curated-live *args:
    just _deploy-curated-live-no-confirm --broadcast --verify {{args}}

deploy-curated-live-dry *args:
    just _deploy-curated-live-no-confirm {{args}}

verify-curated-live *args:
    just _warn "Pass --chain=your_chain manually when running curated deployments"
    forge script {{curated_deploy_script_path}} --sig="run(string)" --rpc-url ${RPC_URL} --verify {{args}} --unlocked -- `git rev-parse HEAD`

_deploy-curated-live-no-confirm *args:
    forge script {{curated_deploy_script_path}} --sig="run(string)" --force --rpc-url ${RPC_URL} {{args}} -- `git rev-parse HEAD`

vote-add-curated-module:
    just _impersonate-script SimulateVote --sig="addCuratedModule"

test-curated-local *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    mkdir -p ./artifacts/local/curated

    ARTIFACTS_DIR=./artifacts/local/curated/ just deploy-curated --silent --private-key=`cat localhost.json | jq -r ".private_keys[0]"` {{disable_code_size_limit}}

    export DEPLOY_CONFIG=./artifacts/local/curated/deploy-{{chain}}.json
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-curated-module

    just test-deployment-full-afterVote {{args}}

    just test-integration {{args}}

    just kill-fork
