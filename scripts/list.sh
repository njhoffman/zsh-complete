#!/usr/bin/env bash
# List zsh completions with various filters.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

List zsh completions with various filters.

Options:
    --to-install     Commands with available but not installed completions
    --to-uninstall   Installed completions without an associated command
    --missing        Commands without any available completions
    --existing       Commands with installed completions
    --all            All commands with their completion status
    --summary        Counts of commands and completions
    --pick           Interactively pick a source for an available command
                     (writes selection into config.commands)
    --json           Output in JSON format
    -h, --help       Show this help
EOF
}

load_data() {
    local commands_file
    commands_file=$(get_file commands)
    if [[ ! -f "$commands_file" ]]; then
        log_error "Commands data not found. Run compile.sh first."
        return 1
    fi
}

# Files used by every filter; resolves to /dev/null when missing so jq still works.
_resolve_files() {
    COMMANDS_FILE=$(get_file commands)
    AVAILABLE_FILE=$(get_file available)
    EXISTING_FILE=$(get_file existing)
    [[ -f "$AVAILABLE_FILE" ]] || AVAILABLE_FILE=/dev/null
    [[ -f "$EXISTING_FILE"  ]] || EXISTING_FILE=/dev/null
}

list_to_install() {
    _resolve_files
    [[ "$AVAILABLE_FILE" == /dev/null ]] && return 0
    jq -r --slurpfile e "$EXISTING_FILE" '
        keys[] as $c | select($e[0][$c] == null) | $c
    ' "$AVAILABLE_FILE" | sort
}

list_to_uninstall() {
    _resolve_files
    [[ "$EXISTING_FILE" == /dev/null ]] && return 0
    jq -r --slurpfile c "$COMMANDS_FILE" '
        keys[] as $cmd | select($c[0][$cmd] == null) | $cmd
    ' "$EXISTING_FILE" | sort
}

list_missing() {
    _resolve_files
    jq -r --slurpfile a "$AVAILABLE_FILE" '
        keys[] as $cmd | select($a[0][$cmd] == null) | $cmd
    ' "$COMMANDS_FILE" | sort
}

list_existing() {
    _resolve_files
    [[ "$EXISTING_FILE" == /dev/null ]] && return 0
    jq -r --slurpfile c "$COMMANDS_FILE" --slurpfile a "$AVAILABLE_FILE" '
        to_entries[]
        | select($c[0][.key] != null)
        | (if ($a[0][.key] != null) then "\(.key) (+\($a[0][.key] | length) available)"
                                    else .key end)
    ' "$EXISTING_FILE" | sort
}

list_all() {
    _resolve_files
    jq -r --slurpfile e "$EXISTING_FILE" --slurpfile a "$AVAILABLE_FILE" '
        keys[] as $cmd
        | $cmd
          + (if ($e[0][$cmd] != null) then " [installed]" else "" end)
          + (if ($a[0][$cmd] != null)
             then " [available:\($a[0][$cmd] | length)]"
             else "" end)
    ' "$COMMANDS_FILE" | sort
}

print_summary() {
    _resolve_files
    local cc ac ec to_install missing
    cc=$(jq 'length' "$COMMANDS_FILE")
    ac=$(jq 'length' "$AVAILABLE_FILE" 2>/dev/null || echo 0)
    ec=$(jq 'length' "$EXISTING_FILE" 2>/dev/null || echo 0)
    to_install=$(list_to_install | wc -l)
    missing=$(list_missing | wc -l)

    print_header "Summary"
    print_aligned "Commands"   "$cc"
    print_aligned "Available"  "$ac"
    print_aligned "Existing"   "$ec"
    print_aligned "To install" "$to_install"
    print_aligned "Missing"    "$missing"
}

# Open a picker over all installable commands; for the chosen command, present
# its source candidates and write the selection into config.commands.
pick_interactive() {
    _resolve_files
    [[ "$AVAILABLE_FILE" == /dev/null ]] && {
        log_error "No available completions data; run compile.sh"
        return 1
    }

    local -a installable=()
    mapfile -t installable < <(list_to_install)
    [[ ${#installable[@]} -eq 0 ]] && {
        print_aligned "Pick" "Nothing to install"
        return 0
    }

    local cmd
    cmd=$(fzf_or_select "Pick command: " "${installable[@]}") || return 1
    [[ -z "$cmd" ]] && return 1

    local -a sources=()
    mapfile -t sources < <(jq -r --arg c "$cmd" '.[$c][].source' "$AVAILABLE_FILE")
    [[ ${#sources[@]} -eq 0 ]] && {
        log_warn "No source candidates for $cmd"
        return 1
    }

    local source
    source=$(fzf_or_select "Source for $cmd: " "${sources[@]}") || return 1
    [[ -z "$source" ]] && return 1

    # Patch config.json in-place: .commands[$cmd] = $source
    local new
    new=$(jq --arg c "$cmd" --arg s "$source" '
        .commands = ((.commands // {}) | .[$c] = $s)
    ' "$CONFIG_FILE")
    printf '%s\n' "$new" > "$CONFIG_FILE"
    print_success "Mapped $cmd -> $source in $CONFIG_FILE"
}

list_json() {
    local filter="$1"
    _resolve_files
    case "$filter" in
        to-install)   list_to_install   | jq -R -s 'split("\n") | map(select(length>0))' ;;
        to-uninstall) list_to_uninstall | jq -R -s 'split("\n") | map(select(length>0))' ;;
        missing)      list_missing      | jq -R -s 'split("\n") | map(select(length>0))' ;;
        existing)
            jq --slurpfile c "$COMMANDS_FILE" '
                to_entries | map(select(.key as $k | $c[0][$k] != null))
            ' "$EXISTING_FILE"
            ;;
        all)
            jq --slurpfile e "$EXISTING_FILE" --slurpfile a "$AVAILABLE_FILE" '
                to_entries | map({
                    command: .key,
                    types: .value,
                    installed: ($e[0][.key] != null),
                    available: (if $a[0][.key] then ($a[0][.key] | length) else 0 end)
                })
            ' "$COMMANDS_FILE"
            ;;
        summary)
            local cc ac ec
            _resolve_files
            cc=$(jq 'length' "$COMMANDS_FILE")
            ac=$(jq 'length' "$AVAILABLE_FILE" 2>/dev/null || echo 0)
            ec=$(jq 'length' "$EXISTING_FILE"  2>/dev/null || echo 0)
            jq -n --argjson c "$cc" --argjson a "$ac" --argjson e "$ec" \
                  --argjson ti "$(list_to_install | wc -l)" \
                  --argjson mi "$(list_missing    | wc -l)" \
                  '{commands:$c, available:$a, existing:$e, to_install:$ti, missing:$mi}'
            ;;
    esac
}

print_list() {
    local title="$1"; shift
    local items=("$@")
    if [[ ${#items[@]} -eq 0 ]]; then
        print_aligned "$title" "None"
        return
    fi
    print_header "$title"
    printf '%s\n' "${items[@]}"
    echo
    print_aligned "Total" "${#items[@]}"
}

main() {
    local filter="all" json=false pick=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to-install)   filter="to-install"; shift ;;
            --to-uninstall) filter="to-uninstall"; shift ;;
            --missing)      filter="missing"; shift ;;
            --existing)     filter="existing"; shift ;;
            --all)          filter="all"; shift ;;
            --summary)      filter="summary"; shift ;;
            --pick)         pick=true; shift ;;
            --json)         json=true; shift ;;
            -h|--help)      show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    load_config
    load_data || exit 1

    if $pick; then
        pick_interactive
        return
    fi

    if $json; then
        list_json "$filter"
        return
    fi

    case "$filter" in
        to-install)
            local -a r; mapfile -t r < <(list_to_install)
            print_list "Commands to Install" "${r[@]}" ;;
        to-uninstall)
            local -a r; mapfile -t r < <(list_to_uninstall)
            print_list "Completions to Uninstall" "${r[@]}" ;;
        missing)
            local -a r; mapfile -t r < <(list_missing)
            print_list "Commands Missing Completions" "${r[@]}" ;;
        existing)
            local -a r; mapfile -t r < <(list_existing)
            print_list "Installed Completions" "${r[@]}" ;;
        all)
            local -a r; mapfile -t r < <(list_all)
            print_list "All Commands" "${r[@]}" ;;
        summary)
            print_summary ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
