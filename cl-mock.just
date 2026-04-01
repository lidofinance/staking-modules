####
# CL mock beacon API server
####

cl_mock_port := env_var_or_default("CL_MOCK_PORT", "5052")
cl_state_file := "cl-state.json"
cl_valid_statuses := "pending_initialized pending_queued active_ongoing active_exiting active_slashed exited_unslashed exited_slashed withdrawal_possible withdrawal_done withdrawal_possible_slashed withdrawal_done_slashed"

cl-start:
    @if nc -z -w 1 127.0.0.1 {{cl_mock_port}} > /dev/null 2>&1; \
        then just _warn "CL mock already running on port {{cl_mock_port}}"; \
        else CL_MOCK_PORT={{cl_mock_port}} CL_STATE_FILE={{cl_state_file}} node script/cl-mock/server.mjs & \
             sleep 0.3 && just _info "CL mock started on http://127.0.0.1:{{cl_mock_port}}"; \
    fi

cl-stop:
    @-pkill -f "cl-mock/server.mjs" && just _info "CL mock stopped"

cl-status:
    @nc -z -w 1 127.0.0.1 {{cl_mock_port}} > /dev/null 2>&1 && just _info "CL mock running on port {{cl_mock_port}}" || just _warn "CL mock not running"

# Set a validator's CL status. Usage: just cl-set 0xpubkey active_ongoing
cl-set pubkey status:
    #!/usr/bin/env bash
    set -euo pipefail
    pk="{{pubkey}}"
    if [[ ! "$pk" =~ ^0x[0-9a-fA-F]{96}$ ]]; then
      echo "error: invalid pubkey '${pk}'. Expected 0x-prefixed 96-hex-char string (48 bytes)" >&2
      exit 1
    fi
    valid=({{cl_valid_statuses}})
    for v in "${valid[@]}"; do [[ "$v" == "{{status}}" ]] && found=1 && break; done
    if [[ -z "${found:-}" ]]; then
      echo "error: invalid status '{{status}}'. Valid statuses:" >&2
      printf '  %s\n' "${valid[@]}" >&2
      exit 1
    fi
    [ -f "{{cl_state_file}}" ] || echo '{}' > "{{cl_state_file}}"
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync('{{cl_state_file}}', 'utf8'));
      const k = '{{pubkey}}'.toLowerCase();
      s[k] = { ...(s[k] || {}), status: '{{status}}' };
      fs.writeFileSync('{{cl_state_file}}', JSON.stringify(s, null, 2) + '\n');
    "

# List valid validator statuses
cl-statuses:
    @printf '%s\n' {{cl_valid_statuses}}

cl-list:
    @[ -f "{{cl_state_file}}" ] && node -e " \
      const s = JSON.parse(require('fs').readFileSync('{{cl_state_file}}', 'utf8')); \
      for (const [k, v] of Object.entries(s)) \
        console.log(k.slice(0,18) + '...' + k.slice(-6), v.status || '?'); \
    " || echo "(empty)"

cl-reset:
    @echo '{}' > "{{cl_state_file}}" && just _info "CL mock state cleared"

# Query CL mock API for all keys in cl-state.json
cl-query:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f "{{cl_state_file}}" ] || { echo "(no state file)"; exit 0; }
    ids=$(node -e "const s=JSON.parse(require('fs').readFileSync('{{cl_state_file}}','utf8')); console.log(Object.keys(s).join(','))")
    [ -z "$ids" ] && { echo "(no keys)"; exit 0; }
    curl -s "http://127.0.0.1:{{cl_mock_port}}/eth/v1/beacon/states/head/validators?id=${ids}" | node -e "
      let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>console.log(JSON.stringify(JSON.parse(d),null,2)));
    "
