#!/usr/bin/env bash
# Sync available completions into the active fpath dir.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Plan and apply changes to the active completions dir.

Options:
    --dry-run       Print the plan only (default)
    --apply         Execute the plan
    --prune         Remove orphaned symlinks (no available completion)
    -h, --help      Show this help
EOF
}

# Pick the winning entry for a command from its available entries (JSON array).
# Honors $OVERRIDES (jq object of cmd -> source-name) before falling back to
# lowest priority (smallest "priority" field).
pick_winner() {
    local cmd="$1"
    local entries_json="$2"
    local overrides_json="$3"

    echo "$entries_json" | jq -c \
        --arg cmd "$cmd" \
        --argjson ov "$overrides_json" \
        '
        ($ov[$cmd] // "") as $force
        | if $force != "" and (map(.source == $force) | any)
          then (map(select(.source == $force)) | sort_by(.priority) | .[0])
          else (sort_by(.priority) | .[0])
          end
        '
}

# Build a plan as TSV: action<TAB>cmd<TAB>target<TAB>current
build_plan() {
    local available_file active_dir overrides
    available_file=$(get_file available)
    active_dir=$(get_dir active)
    overrides=$(get_command_overrides)

    if [[ ! -f "$available_file" ]]; then
        log_error "Available data missing: $available_file (run compile.sh)"
        return 1
    fi

    ensure_dir "$active_dir"

    declare -A want=()
    local cmd entries winner target
    while IFS= read -r cmd; do
        entries=$(jq -c --arg c "$cmd" '.[$c]' "$available_file")
        winner=$(pick_winner "$cmd" "$entries" "$overrides")
        target=$(echo "$winner" | jq -r '.path')
        want["$cmd"]="$target"
    done < <(jq -r 'keys[]' "$available_file")

    # Compare against current state of $active_dir
    declare -A current=()
    local link basename
    if [[ -d "$active_dir" ]]; then
        for link in "$active_dir"/_*; do
            [[ -L "$link" || -f "$link" ]] || continue
            basename=$(basename "$link")
            local k="${basename#_}"
            local actual
            actual=$(readlink -f "$link" 2>/dev/null || echo "$link")
            current["$k"]="$actual"
        done
    fi

    # Emit install/update/remove lines
    local k
    for k in "${!want[@]}"; do
        local target_path="${want[$k]}"
        local resolved
        resolved=$(readlink -f "$target_path" 2>/dev/null || echo "$target_path")
        if [[ -z "${current[$k]:-}" ]]; then
            printf 'install\t%s\t%s\t-\n' "$k" "$target_path"
        elif [[ "${current[$k]}" != "$resolved" ]]; then
            printf 'update\t%s\t%s\t%s\n' "$k" "$target_path" "${current[$k]}"
        fi
    done

    for k in "${!current[@]}"; do
        if [[ -z "${want[$k]:-}" ]]; then
            printf 'remove\t%s\t-\t%s\n' "$k" "${current[$k]}"
        fi
    done
}

print_plan() {
    local plan="$1"
    local active_dir
    active_dir=$(get_dir active)

    print_header "Sync Plan ($active_dir)"

    local ic uc rc
    ic=$(echo "$plan" | grep -c '^install' || true)
    uc=$(echo "$plan" | grep -c '^update'  || true)
    rc=$(echo "$plan" | grep -c '^remove'  || true)

    if [[ -z "$plan" ]]; then
        print_aligned "Nothing to do" ""
        return
    fi

    local action cmd target current line
    while IFS=$'\t' read -r action cmd target current; do
        case "$action" in
            install) printf "${COLOR_GREEN}+ %-30s${COLOR_RESET} %s\n" "$cmd" "$target" ;;
            update)  printf "${COLOR_YELLOW}~ %-30s${COLOR_RESET} %s\n" "$cmd" "$target" ;;
            remove)  printf "${COLOR_RED}- %-30s${COLOR_RESET} %s\n" "$cmd" "$current" ;;
        esac
    done <<< "$plan"

    echo
    print_aligned "Install" "$ic"
    print_aligned "Update"  "$uc"
    print_aligned "Remove"  "$rc"
}

apply_plan() {
    local plan="$1"
    local active_dir
    active_dir=$(get_dir active)
    ensure_dir "$active_dir"

    local action cmd target current
    while IFS=$'\t' read -r action cmd target current; do
        [[ -z "$action" ]] && continue
        case "$action" in
            install|update)
                ln -sfn "$target" "$active_dir/_$cmd"
                log_info "$action _$cmd -> $target"
                ;;
            remove)
                rm -f "$active_dir/_$cmd"
                log_info "remove _$cmd (was $current)"
                ;;
        esac
    done <<< "$plan"
}

prune_orphans() {
    local active_dir available_file
    active_dir=$(get_dir active)
    available_file=$(get_file available)

    [[ -d "$active_dir" ]] || return 0
    [[ -f "$available_file" ]] || return 0

    local link basename cmd_name removed=0
    for link in "$active_dir"/_*; do
        [[ -L "$link" ]] || continue
        basename=$(basename "$link")
        cmd_name="${basename#_}"
        if ! jq -e --arg c "$cmd_name" 'has($c)' "$available_file" > /dev/null; then
            rm -f "$link"
            log_info "pruned orphan: $basename"
            removed=$((removed + 1))
        fi
        # Also remove dangling symlinks
        if [[ -L "$link" && ! -e "$link" ]]; then
            rm -f "$link"
            log_info "pruned dangling: $basename"
            removed=$((removed + 1))
        fi
    done
    log_info "Pruned $removed entries"
}

main() {
    local mode="dry-run" prune=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) mode="dry-run"; shift ;;
            --apply)   mode="apply"; shift ;;
            --prune)   prune=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    load_config

    local plan
    plan=$(build_plan)
    print_plan "$plan"

    if [[ "$mode" == "apply" ]]; then
        print_header "Applying"
        apply_plan "$plan"
        $prune && prune_orphans
        print_success "Sync complete"
    elif $prune; then
        log_warn "--prune ignored without --apply (use --apply --prune)"
    else
        echo
        print_aligned "Mode" "dry-run (use --apply to execute)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
