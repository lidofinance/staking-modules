####
# CL mock beacon API server (backed by `csm-cl-mock` npm package).
# `CL_MOCK_URL` from .env routes all config/query/status/stop commands
# to the chosen server (local or remote).
####

cl_mock_port := env_var_or_default("CL_MOCK_PORT", "5052")

# Start a local csm-cl-mock server (no-op when CL_MOCK_URL is remote).
cl-start:
    #!/usr/bin/env bash
    set -euo pipefail

    url="${CL_MOCK_URL:-}"
    if [ -n "$url" ]; then
      host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^:/]+).*#\1#')
      if [ "$host" != "127.0.0.1" ] && [ "$host" != "localhost" ]; then
        just _warn "CL mock is remote ($url); nothing to start locally"
        exit 0
      fi
    fi

    if nc -z -w 1 127.0.0.1 {{cl_mock_port}} > /dev/null 2>&1; then
      just _warn "CL mock already running on port {{cl_mock_port}}"
      exit 0
    fi

    # Preload package to avoid npx install prompts on first run.
    npx --yes csm-cl-mock help > /dev/null || true

    CL_MOCK_URL="http://127.0.0.1:{{cl_mock_port}}" \
      nohup npx csm-cl-mock serve --port {{cl_mock_port}} > /dev/null 2>&1 &

    # Wait up to ~10s for server to become ready.
    for i in {1..50}; do
      if CL_MOCK_URL="http://127.0.0.1:{{cl_mock_port}}" \
         npx csm-cl-mock status > /dev/null 2>&1; then
        just _info "CL mock started on http://127.0.0.1:{{cl_mock_port}}"
        exit 0
      fi
      sleep 0.2
    done
    just _warn "CL mock did not become ready within 10s"
    exit 1

cl-stop:
    @npx csm-cl-mock stop > /dev/null 2>&1 && just _info "CL mock stopped" \
      || just _warn "CL mock not running"

cl-status:
    @npx csm-cl-mock status

# Set a validator's CL status. Usage: just cl-set 0xpubkey active_ongoing [amountEth]
cl-set pubkey status amountEth="":
    @npx csm-cl-mock config set "{{pubkey}}" "{{status}}" {{amountEth}}

# Mark operator's key as active_ongoing on CL mock with given effective balance.
# Usage: just cl-activate <noId> <keyIndex> <amountEth>
cl-activate noId keyIndex amountEth="":
    #!/usr/bin/env bash
    set -euo pipefail
    pk=$(just get-pubkey {{noId}} {{keyIndex}})
    just cl-set "$pk" active_ongoing {{amountEth}}

# List valid validator statuses
cl-statuses:
    @npx csm-cl-mock config statuses

cl-list:
    @npx csm-cl-mock config list

cl-reset:
    @npx csm-cl-mock config reset && just _info "CL mock state cleared"

# Query CL mock API for every configured validator.
cl-query:
    @npx csm-cl-mock query
