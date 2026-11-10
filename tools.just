# Check that the installed tooling matches the versions the repo is pinned to
check-tools:
    #!/bin/sh
    set -u

    version_ge() {
        awk -v found="$1" -v required="$2" 'BEGIN {
            split(found, f, "."); split(required, r, ".")
            for (i = 1; i <= 3; i++) {
                if (f[i] + 0 > r[i] + 0) exit 0
                if (f[i] + 0 < r[i] + 0) exit 1
            }
        }'
    }

    foundry=$(cat .foundryref)
    node=$(sed 's/^v//' .nvmrc)
    yarn=$(sed -n 's/.*"packageManager": *"yarn@\([^"]*\)".*/\1/p' package.json)
    just_min=$(sed -n 's/^ *JUST_TAG: *//p' .github/workflows/test.yml | head -n1)

    failed=0
    while IFS='|' read -r tool rule required; do
        found=$($tool --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[^ ,()]*' | head -n1)
        case "$rule" in
            # Foundry binaries report `<semver>-<release tag>`, and the tag is what is pinned.
            tag) requirement="== $required"; case "$found" in *-"$required") ok=0 ;; *) ok=1 ;; esac ;;
            min) requirement=">= $required"; version_ge "$found" "$required" && ok=0 || ok=1 ;;
            eq)  requirement="== $required"; [ "$found" = "$required" ] && ok=0 || ok=1 ;;
            *)   requirement="any"; ok=0 ;;
        esac
        [ -n "$found" ] || { found="not installed"; ok=1; }

        [ "$ok" -eq 0 ] || failed=1
        printf '  %-4s %-6s %-14s %s\n' "$([ "$ok" -eq 0 ] && echo ok || echo fail)" "$tool" "$found" "$requirement"
    done <<EOF
    forge|tag|$foundry
    anvil|tag|$foundry
    cast|tag|$foundry
    just|min|$just_min
    jq|min|1.7
    node|eq|$node
    yarn|eq|$yarn
    uv|any|
    EOF

    exit "$failed"
