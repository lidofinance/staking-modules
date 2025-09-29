set dotenv-load

import? ".local.just"
import "fork.just"

chain := env_var_or_default("CHAIN", "mainnet")
deploy_script_name := if chain == "mainnet" {
    "DeployMainnet"
} else if chain == "local-devnet" {
    "DeployLocalDevNet"
} else if chain == "hoodi" {
    "DeployHoodi"
} else if chain == "holesky" {
    "DeployHolesky"
} else {
    error("Unsupported chain " + chain)
}

deploy_implementations_script_name := if chain == "mainnet" {
    "DeployImplementationsMainnet"
} else if chain == "hoodi" {
    "DeployImplementationsHoodi"
} else if chain == "holesky" {
    "DeployImplementationsHolesky"
} else if chain == "local-devnet" {
    "SCRIPT_IS_NOT_DEFINED"
} else {
    error("Unsupported chain " + chain)
}

deploy_config_path := if chain == "mainnet" {
    "artifacts/mainnet/deploy-mainnet.json"
} else if chain == "local-devnet" {
    "artifacts/local-devnet/deploy-local-devnet.json"
} else if chain == "hoodi" {
    "artifacts/hoodi/deploy-hoodi.json"
} else if chain == "holesky" {
    "artifacts/holesky/deploy-holesky.json"
} else {
    error("Unsupported chain " + chain)
}

deploy_script_path := "script" / deploy_script_name + ".s.sol:" + deploy_script_name
deploy_impls_script_path := "script" / deploy_implementations_script_name + ".s.sol:" + deploy_implementations_script_name

anvil_host := env_var_or_default("ANVIL_IP_ADDR", "127.0.0.1")
anvil_port := env_var_or_default("ANVIL_PORT", "8545")
anvil_rpc_url := "http://" + anvil_host + ":" + anvil_port

default: clean deps build test-all

build *args:
    forge build --skip test --force {{args}}

clean:
    forge clean
    rm -rf cache broadcast out node_modules

deps:
    yarn workspaces focus --all --production

deps-dev:
    yarn workspaces focus --all && npx husky install

lint-solhint:
    yarn lint:solhint

lint-fix:
    yarn lint:fix

lint:
    yarn lint:check

test-all:
    just test-unit &
    just test-local

# Run all unit tests
test-unit *args:
    forge test --skip script --no-match-path 'test/fork/*' -vvv {{args}}

# Run all deployment tests that should be executed against full scratch deployment before the module activation vote
test-deployment-full-scratch *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '.*_afterVote.*' -vvv --show-progress {{args}}

# Run all deployment tests that should be executed against CSM v2 scratch deployment before the module upgrade vote
test-deployment-v2-only-scratch *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '(.*_afterVote.*)|(.*_onlyFull.*)' -vvv --show-progress {{args}}

# Run all deployment tests that should be executed against full scratch deployment after the module activation vote
test-deployment-full-afterVote *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '.*_scratch.*' -vvv --show-progress {{args}}

# Run all integration tests
test-integration *args:
    forge test --match-path 'test/fork/integration/*' -vvv --show-progress {{args}}

# Run tests applicable after the module upgrade vote. Does not include deployment tests
test-post-upgrade *args:
    forge test --match-path='test/fork/*' --no-match-path 'test/fork/deployment/*' -vvv --show-progress {{args}}

gas-report:
    #!/usr/bin/env python

    import subprocess
    import re

    command = "just test-unit --nmt 'testFuzz.+' --gas-report"
    output = subprocess.check_output(command, shell=True, text=True)

    lines = output.split('\n')

    filename = 'GAS.md'
    to_print = False
    skip_next = False

    with open(filename, 'w') as fh:
        for line in lines:
            if skip_next:
                skip_next = False
                continue

            if line.startswith('|'):
                to_print = True

            if line.startswith('| Deployment Cost'):
                to_print = False
                skip_next = True

            if re.match(r"Ran \d+ test suites", line):
                break

            if to_print:
                fh.write(line + '\n')

    print(f"Done. Gas report saved to {filename}")

coverage *args:
    FOUNDRY_PROFILE=coverage forge coverage --no-match-coverage '(test|script)' --no-match-path 'test/fork/*' {{args}}

# Run coverage and save the report in LCOV file.
coverage-lcov *args:
    FOUNDRY_PROFILE=coverage forge coverage --no-match-coverage '(test|script)' --no-match-path 'test/fork/*' --report lcov {{args}}

diffyscan-contracts *args:
    yarn generate:diffyscan {{args}}

oz-upgrades:
    #!/usr/bin/env bash
    set -euxo pipefail

    FOUNDRY_PROFILE=upgrades just build --skip=script,test

    CURR_DIR=$(pwd)
    TMP_DIR=$(mktemp -d)
    git clone --depth 1 --branch main https://github.com/lidofinance/community-staking-module "$TMP_DIR"

    cd "$TMP_DIR"
    just deps
    FOUNDRY_PROFILE=upgrades just build --skip=script,test
    cd "$CURR_DIR"

    cp -r "$TMP_DIR/out/build-info" out/v1

    # Muted some errors globally
    #   --unsafeAllowLinkedLibraries due to no support for linked libraries in upgrades-core
    #   --unsafeAllow=constructor,state-variable-immutable - all the contracts have immutables with safe usage
    # These changes fixing a mistake in the custom annotations in the v1 contract, but no changes in the actual storage pointer
    #   - Deleted namespace `erc7201:CSAccounting.CSBondLock`
    #   - Deleted namespace `erc7201:CSAccounting.CSBondCurve`
    #   - Deleted namespace `erc7201:CSAccounting.CSBondCore`
    # These findings related to the namespaced storage structs which can't be annotated properly https://github.com/OpenZeppelin/openzeppelin-upgrades/issues/802
    #   - Renamed `bondLockRetentionPeriod` to `bondLockPeriod`
    #   - Upgraded `bondLock` to an incompatible type
    # A safe change in the CSFeeOracle. We nullify the whole slot in the upgrade call
    #   - Layout changed for `strikes` (uint256 -> contract ICSStrikes). Number of bytes changed from 32 to 20

    npx @openzeppelin/upgrades-core validate --contract=CSModule --reference=v1:CSModule --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true
    npx @openzeppelin/upgrades-core validate --contract=CSAccounting --reference=v1:CSAccounting --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true
    npx @openzeppelin/upgrades-core validate --contract=CSFeeOracle --reference=v1:CSFeeOracle --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true
    npx @openzeppelin/upgrades-core validate --contract=CSFeeDistributor --reference=v1:CSFeeDistributor --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true

    rm -rf "$TMP_DIR"

make-fork *args:
    @if pgrep -x "anvil" > /dev/null; \
        then just _warn "anvil process is already running in the background. Make sure it's connected to the right network and in the right state."; \
        else anvil -f ${RPC_URL} --host {{anvil_host}} --port {{anvil_port}} --config-out localhost.json {{args}}; \
    fi

kill-fork:
    @-pkill anvil && just _warn "anvil process is killed"

deploy *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{deploy_script_path}} --sig="run(string)" --rpc-url {{anvil_rpc_url}} --broadcast --slow {{args}} -- `git rev-parse HEAD`

deploy-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _deploy-live {{args}}

    cp ./broadcast/{{deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

deploy-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _deploy-live-no-confirm --broadcast {{args}}

    cp ./broadcast/{{deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
_deploy-live *args:
    just _deploy-live-no-confirm --broadcast --verify {{args}}

deploy-live-dry *args:
    just _deploy-live-no-confirm {{args}}

verify-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=holesky for testnet deployment"
    forge script {{deploy_script_path}} --sig="run(string)" --rpc-url ${RPC_URL} --verify {{args}} --unlocked -- `git rev-parse HEAD`

_deploy-live-no-confirm *args:
    forge script {{deploy_script_path}} --sig="run(string)" --force --rpc-url ${RPC_URL} {{args}} -- `git rev-parse HEAD`

_deploy-impl *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{deploy_impls_script_path}} --sig="deploy(string,string)" \
            --rpc-url ${RPC_URL} {{args}} \
            -- {{deploy_config_path}} `git rev-parse HEAD`

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
deploy-impl-live *args:
    ARTIFACTS_DIR=./artifacts/latest/ just _deploy-impl --broadcast --verify {{args}}

    cp ./broadcast/{{deploy_implementations_script_name}}.s.sol/\
        $(cast chain-id --rpc-url=$RPC_URL)\
        /deploy-latest.json ./artifacts/latest/transactions.json

deploy-impl-dry *args:
    just _deploy-impl {{args}}

    cp ./broadcast/{{deploy_implementations_script_name}}.s.sol/\
        $(cast chain-id --rpc-url=$RPC_URL)\
        /dry-run/deploy-latest.json ./artifacts/local/transactions.json

deploy-local *args:
    just make-fork &
    @while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy {{args}}
    just _warn "anvil is kept running in the background: {{anvil_rpc_url}}"

# Deploy CSM v2 components, upgrade CSM, run deployment, integration, and post-upgrade tests
test-upgrade *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}

    just _deploy-impl --broadcast --private-key=`cat localhost.json | jq -r ".private_keys[0]"`

    export DEPLOY_CONFIG=./artifacts/local/upgrade-{{chain}}.json
    export VOTE_PREV_BLOCK=`cast block-number -r $RPC_URL`

    just vote-upgrade

    just test-deployment-full-afterVote {{args}}

    just test-post-upgrade {{args}}

    just kill-fork

# Deploy CSM from scratch, add module to the SR, and run deployment and integration tests
test-local *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy --silent --private-key=`cat localhost.json | jq -r ".private_keys[0]"`

    export DEPLOY_CONFIG=./artifacts/local/deploy-{{chain}}.json
    export RPC_URL={{anvil_rpc_url}}

    just vote-add-module

    just test-deployment-full-afterVote {{args}}
    
    just test-integration {{args}}

    just kill-fork

# Deploy CSM from scratch and run deployment tests
test-full-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done
    just deploy --private-key=`cat localhost.json | jq -r ".private_keys[0]"`

    export DEPLOY_CONFIG=./artifacts/local/deploy-{{chain}}.json
    export RPC_URL={{anvil_rpc_url}}

    just test-deployment-full-scratch {{args}}

    just kill-fork

# Deploy CSM v2 components and run deployment tests
test-v2-only-deploy *args:
    #!/usr/bin/env bash
    set -euxo pipefail

    just make-fork --silent &
    while ! echo exit | nc {{anvil_host}} {{anvil_port}} > /dev/null; do sleep 1; done

    export RPC_URL={{anvil_rpc_url}}

    just _deploy-impl --broadcast --private-key=`cat localhost.json | jq -r ".private_keys[0]"`

    export DEPLOY_CONFIG=./artifacts/local/upgrade-{{chain}}.json

    just test-deployment-v2-only-scratch {{args}}

    just kill-fork

_warn message:
    @tput setaf 3 && printf "[WARNING]" && tput sgr0 && echo " {{message}}"
