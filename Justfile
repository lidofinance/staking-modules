set dotenv-load

chain := env_var_or_default("CHAIN", "mainnet")
chain_script_suffix := if chain == "mainnet" {
    "Mainnet"
} else if chain == "hoodi" {
    "Hoodi"
} else if chain == "local-devnet" {
    "LocalDevNet"
} else {
    error("Unsupported chain " + chain + ". Supported: mainnet, hoodi, local-devnet")
}
anvil_host := env_var_or_default("ANVIL_IP_ADDR", "127.0.0.1")
anvil_port := env_var_or_default("ANVIL_PORT", "8545")
anvil_rpc_url := "http://" + anvil_host + ":" + anvil_port
disable_code_size_limit := if env("DISABLE_CODE_SIZE_LIMIT", "") != "" { "--disable-code-size-limit" } else { "" }

# Shared deployment helpers
_deploy-generic deploy_script_path rpc_url *args:
    FOUNDRY_PROFILE=deploy \
        forge script {{deploy_script_path}} --sig="run(string)" --rpc-url {{rpc_url}} --broadcast --slow {{args}} -- `git rev-parse HEAD`

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
_deploy-live-generic deploy_script_path *args:
    just _deploy-live-generic-no-confirm {{deploy_script_path}} --broadcast --verify {{args}}

_deploy-live-generic-no-confirm deploy_script_path *args:
    forge script {{deploy_script_path}} --sig="run(string)" --force --rpc-url ${RPC_URL} {{args}} -- `git rev-parse HEAD`

_deploy-live-generic-dry deploy_script_path *args:
    FOUNDRY_PROFILE=deploy just _deploy-live-generic-no-confirm {{deploy_script_path}} {{args}}

_verify-live-generic deploy_script_path *args:
    forge script {{deploy_script_path}} --sig="run(string)" --rpc-url ${RPC_URL} --verify {{args}} --unlocked -- `git rev-parse HEAD`

# Shared artifact helpers
_copy-broadcast-json script_name rpc_url dry_prefix json_name dest_path:
    just _copy-file \
        ./broadcast/{{script_name}}.s.sol/$(cast chain-id --rpc-url "{{rpc_url}}"){{dry_prefix}}/{{json_name}} \
        {{dest_path}}

_copy-file src_path dest_path:
    mkdir -p "$(dirname "{{dest_path}}")"
    cp "{{src_path}}" "{{dest_path}}"

# Shared local fork helpers
_local-private-key:
    @jq -re '.private_keys[0]' localhost.json

# Start local anvil fork when needed.
# Prints owned PID; prints nothing when reusing an already running fork.
_fork-up:
    #!/usr/bin/env bash
    set -euo pipefail

    if nc -z -w 1 {{anvil_host}} {{anvil_port}} > /dev/null 2>&1; then
        just _warn "anvil process is already running at {{anvil_rpc_url}}; reusing existing process." >&2
        exit 0
    fi

    rpc_url="${RPC_URL:-}"
    if [ -z "${rpc_url}" ]; then
        just _warn "RPC_URL is required to start anvil fork." >&2
        exit 1
    fi

    anvil -f "${rpc_url}" --host {{anvil_host}} --port {{anvil_port}} \
        --config-out localhost.json {{disable_code_size_limit}} --timeout 90000 \
        > /dev/null 2>&1 < /dev/null &
    anvil_pid=$!
    # Guard against hanging forever when anvil fails to accept connections.
    start_deadline_epoch=$(( $(date +%s) + 60 ))

    while ! nc -z -w 1 {{anvil_host}} {{anvil_port}} > /dev/null 2>&1; do
        if ! kill -0 "${anvil_pid}" 2>/dev/null; then
            wait "${anvil_pid}" || true
            just _warn "failed to start anvil at {{anvil_rpc_url}}." >&2
            exit 1
        fi

        if [ "$(date +%s)" -ge "${start_deadline_epoch}" ]; then
            kill "${anvil_pid}" 2>/dev/null || true
            wait "${anvil_pid}" || true
            just _warn "timed out waiting for anvil at {{anvil_rpc_url}}." >&2
            exit 1
        fi

        sleep 1
    done

    printf "%s\n" "${anvil_pid}"

_fork-up-and-down:
    #!/usr/bin/env bash
    set -euo pipefail

    # Emit snippet for `eval`: bind pid and install cleanup trap in the caller shell.
    # If fork is reused (already running), owned_anvil_pid is empty and cleanup is a no-op.
    owned_anvil_pid="$(just _fork-up)"
    cat <<EOF
    owned_anvil_pid="${owned_anvil_pid}"
    if [ -n "\${owned_anvil_pid}" ]; then
        just _info "local anvil fork started at {{anvil_rpc_url}} (pid: \${owned_anvil_pid}); it will be stopped on recipe exit."
    fi

    __fork_cleanup() {
        if [ -z "\${owned_anvil_pid}" ]; then
            return 0
        fi

        if ! kill -0 "\${owned_anvil_pid}" 2>/dev/null; then
            return 0
        fi

        if ! ps -p "\${owned_anvil_pid}" -o comm= 2>/dev/null | grep -qx "anvil"; then
            return 0
        fi

        if kill "\${owned_anvil_pid}" 2>/dev/null; then
            just _info "local anvil fork stopped (pid: \${owned_anvil_pid})."
        fi
    }
    trap __fork_cleanup EXIT
    EOF

# Recipe modules
import? ".local.just"
import "fork.just"
import "csm.just"
import "csm0x02.just"
import "curated.just"

# Default and top-level workflows
default: clean deps build test-all

build *args:
    forge build --skip test --skip script {{args}}

clean:
    forge clean
    rm -rf cache broadcast out node_modules

deps:
    yarn workspaces focus --all --production

deps-dev:
    yarn workspaces focus --all && npx husky install

lint-solhint:
    yarn lint:solhint

lint-foundry *args:
    forge lint {{args}}

lint-fix:
    yarn lint:fix

lint:
    just lint-foundry
    yarn lint:check

test-all:
    #!/usr/bin/env bash
    set -euo pipefail

    # Run unit tests in parallel with local fork flows, but always wait to preserve failures.
    just test-unit &
    unit_pid=$!

    if ! just test-local; then
        wait "${unit_pid}" || true
        exit 1
    fi

    wait "${unit_pid}"

# Run all local fork deployment/integration flows across modules.
# Must be sequential because local flows share one anvil endpoint.
test-local *args:
    just test-csm-local {{args}}
    just test-curated-local {{args}}
    just test-csm0x02-local {{args}}

# Run all unit tests
test-unit *args:
    forge test --skip script --no-match-path 'test/fork/**' -vvv {{args}}

# Run all deployment tests that should be executed against full scratch deployment before the module activation vote
test-deployment-full-scratch *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '.*_afterVote.*' -vvv --show-progress -j 4 {{args}}

# Run all deployment tests that should be executed against full scratch deployment after the module activation vote
test-deployment-full-afterVote *args:
    forge test --match-path 'test/fork/deployment/*' --no-match-test '.*_scratch.*' -vvv --show-progress -j 4 {{args}}

# Run all integration tests
# Restrict to 4 parallel jobs to avoid overloading the RPC
test-integration *args:
    forge test --match-path 'test/fork/integration/**' -vvv --show-progress -j 4 {{args}}

# Run tests for utility contracts
test-utils *args:
    forge test --match-path 'test/fork/utils/*' -vvv --show-progress {{args}}

# Run tests applicable after the module upgrade vote. Does not include deployment tests
test-post-upgrade *args:
    forge test --match-path='test/fork/**' --no-match-path 'test/fork/deployment/**' -vvv --show-progress -j 4 {{args}}

gas-report:
    #!/usr/bin/env python

    import subprocess
    import re

    command = "just test-unit --nmt 'testFuzz.+' --gas-report"

    try:
        output = subprocess.check_output(command, shell=True, text=True)
    except subprocess.CalledProcessError as e:
        print(e.output)
        raise

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
    set -euo pipefail

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
    npx @openzeppelin/upgrades-core validate --contract=Accounting --reference=v1:Accounting --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true
    npx @openzeppelin/upgrades-core validate --contract=FeeOracle --reference=v1:FeeOracle --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true
    npx @openzeppelin/upgrades-core validate --contract=FeeDistributor --reference=v1:FeeDistributor --referenceBuildInfoDirs=out/v1 \
        --unsafeAllowLinkedLibraries --unsafeAllow=constructor,state-variable-immutable || true

    rm -rf "$TMP_DIR"

make-fork *args:
    @if nc -z -w 1 {{anvil_host}} {{anvil_port}} > /dev/null 2>&1; \
        then just _warn "anvil process is already running at {{anvil_rpc_url}}. Make sure it's connected to the right network and in the right state."; \
        else exec anvil -f ${RPC_URL} --host {{anvil_host}} --port {{anvil_port}} --config-out localhost.json {{disable_code_size_limit}} --timeout 90000 {{args}}; \
    fi

kill-fork:
    @-pkill anvil && just _warn "anvil process is killed"

deploy-utils module_name contract_name *args:
    just _deploy-utils {{module_name}} {{contract_name}} {{anvil_rpc_url}} ./artifacts/latest/{{module_name}}/utils/{{contract_name}}/ "" --broadcast {{args}}

deploy-utils-dry module_name contract_name *args:
    just _deploy-utils {{module_name}} {{contract_name}} $RPC_URL ./artifacts/local/{{module_name}}/utils/{{contract_name}}/ "/dry-run" {{args}}

deploy-utils-live module_name contract_name *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    just _deploy-utils-live-confirmed {{module_name}} {{contract_name}} {{args}}

[confirm("You are about to broadcast utility contract deployment transactions to the network. Are you sure?")]
_deploy-utils-live-confirmed module_name contract_name *args:
    just _deploy-utils {{module_name}} {{contract_name}} $RPC_URL ./artifacts/latest/{{module_name}}/utils/{{contract_name}}/ "" --broadcast --verify {{args}}

_deploy-utils module_name contract_name rpc_url artifacts_dir dry-prefix *args:
    #!/usr/bin/env bash
    CHAIN_LOWER="{{chain}}"
    CHAIN_CAPITALIZED="${CHAIN_LOWER^}"

    mkdir -p {{artifacts_dir}}
    ARTIFACTS_DIR={{artifacts_dir}} \
    forge script script/Deploy{{contract_name}}${CHAIN_CAPITALIZED}.s.sol:Deploy{{contract_name}}${CHAIN_CAPITALIZED} --sig="run(string)" \
        --rpc-url {{rpc_url}} --slow {{args}} -- `git rev-parse HEAD`

    just _copy-file \
        ./broadcast/Deploy{{contract_name}}${CHAIN_CAPITALIZED}.s.sol/`cast chain-id --rpc-url={{rpc_url}}`{{dry-prefix}}/run-latest.json \
        {{artifacts_dir}}/transactions.json

_warn message:
    @tput setaf 3 && printf "[WARNING]" && tput sgr0 && echo " {{message}}"

_info message:
    @tput setaf 6 && printf "[INFO]" && tput sgr0 && echo " {{message}}"
