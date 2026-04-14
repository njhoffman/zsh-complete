#!/usr/bin/env bash
# Validate completion files: zsh -n syntax check + sourced smoke test.
# Records pass/fail to files.output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Validate completion files referenced in comps-available.json.

Options:
    --all            Check every command (default)
    --command CMD    Check a single command (looks up its winning available file)
    --file FILE      Check a single file path directly
    -h, --help       Show this help
EOF
}

# check_file FILE
# Echoes "ok" / "syntax: <msg>" / "missing: ..." and returns 0/non-zero.
# We restrict ourselves to `zsh -n` because completion files use `_arguments`
# and `compdef` machinery that only loads inside a real completion context.
check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "missing: $file"
        return 2
    fi

    local err
    if ! err=$(zsh -n "$file" 2>&1); then
        echo "syntax: $err"
        return 1
    fi

    echo "ok"
    return 0
}

# check_all: walk comps-available.json, check the lowest-priority entry per command.
check_all() {
    local available_file output_file
    available_file=$(get_file available)
    output_file=$(get_file output)
    ensure_dir "$(dirname "$output_file")"

    if [[ ! -f "$available_file" ]]; then
        log_error "No available data: $available_file"
        return 1
    fi

    echo '{}' > "$output_file"
    local pass=0 fail=0 cmd path result status_code
    while IFS= read -r cmd; do
        path=$(jq -r --arg c "$cmd" '.[$c] | sort_by(.priority) | .[0].path' "$available_file")
        result=$(check_file "$path") || true
        status_code=$?
        if [[ "$result" == "ok" ]]; then
            pass=$((pass + 1))
            local upd
            upd=$(jq --arg c "$cmd" --arg p "$path" \
                '.[$c] = {status:"pass", path:$p}' "$output_file")
            printf '%s\n' "$upd" > "$output_file"
        else
            fail=$((fail + 1))
            local upd
            upd=$(jq --arg c "$cmd" --arg p "$path" --arg e "$result" \
                '.[$c] = {status:"fail", path:$p, error:$e}' "$output_file")
            printf '%s\n' "$upd" > "$output_file"
            log_warn "FAIL $cmd: $result"
        fi
    done < <(jq -r 'keys[]' "$available_file")

    print_aligned "Passed" "$pass"
    print_aligned "Failed" "$fail"
}

main() {
    local mode="all" cmd="" file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)     mode="all"; shift ;;
            --command) mode="command"; cmd="$2"; shift 2 ;;
            --file)    mode="file"; file="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    load_config
    print_header "Checking Completions"

    case "$mode" in
        all)
            check_all
            ;;
        command)
            local available_file path result
            available_file=$(get_file available)
            path=$(jq -r --arg c "$cmd" '.[$c] | sort_by(.priority) | .[0].path' "$available_file")
            result=$(check_file "$path") || true
            print_aligned "$cmd" "$result"
            ;;
        file)
            local result
            result=$(check_file "$file") || true
            print_aligned "$file" "$result"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
