#!/usr/bin/env bash
# Fetch completions from configured sources, dispatching on source.type

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Fetch completion sources defined in config.json into dirs.src.

Options:
    --source NAME   Fetch only the named source
    --force         Re-fetch even if already present (re-clone, re-download)
    -h, --help      Show this help
EOF
}

# Convert a github blob URL to its raw equivalent.
# Leaves non-github URLs untouched.
normalize_url() {
    local url="$1"
    if [[ "$url" =~ ^https://github.com/([^/]+)/([^/]+)/blob/(.+)$ ]]; then
        printf 'https://raw.githubusercontent.com/%s/%s/%s' \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    else
        printf '%s' "$url"
    fi
}

# fetch_remote NAME URL PATHS_JSON [FORCE]
fetch_remote() {
    local name="$1" url="$2" paths_json="$3" force="${4:-false}"
    local dir
    dir="$(get_dir src)/remote/$name"
    ensure_dir "$(dirname "$dir")"

    if [[ -d "$dir/.git" ]]; then
        if [[ "$force" == "true" ]]; then
            log_debug "Force-removing $dir"
            rm -rf "$dir"
        else
            log_info "Updating remote source: $name"
            git -C "$dir" pull --quiet 2>/dev/null \
                || log_warn "Could not pull $name; using existing"
            return 0
        fi
    fi

    log_info "Cloning remote source: $name"
    if ! git clone --quiet --depth 1 "$url" "$dir" 2>/dev/null; then
        log_error "Failed to clone $name from $url"
        return 1
    fi

    if [[ "$paths_json" == "null" || -z "$paths_json" || "$paths_json" == "[]" ]]; then
        return 0
    fi

    # Move matched files to the source root so compile.sh can find them.
    local moved=0 staging
    staging="$(mktemp -d)"
    while IFS= read -r pat; do
        [[ -z "$pat" ]] && continue
        local f
        for f in "$dir"/$pat; do
            [[ -f "$f" ]] || continue
            cp "$f" "$staging/"
            moved=$((moved + 1))
        done
    done < <(echo "$paths_json" | jq -r '.[]')

    if [[ "$moved" -gt 0 ]]; then
        rm -rf "$dir"
        mkdir -p "$dir"
        cp "$staging"/* "$dir"/
    fi
    rm -rf "$staging"
    log_info "Staged $moved files from $name"
}

# fetch_snippet NAME URL [RENAME] [FORCE]
fetch_snippet() {
    local name="$1" url="$2" rename="${3:-}" force="${4:-false}"
    local dir
    dir="$(get_dir src)/snippet/$name"
    ensure_dir "$dir"

    local raw_url dest_name dest
    raw_url=$(normalize_url "$url")
    dest_name="${rename:-$(basename "$raw_url")}"
    dest="$dir/$dest_name"

    if [[ -f "$dest" && "$force" != "true" ]]; then
        log_debug "Snippet already present: $name ($dest_name)"
        return 0
    fi

    log_info "Downloading snippet: $name → $dest_name"
    if ! curl -fsSL --max-time 30 "$raw_url" -o "$dest"; then
        log_error "Failed to download $name from $raw_url"
        rm -f "$dest"
        return 1
    fi

    if [[ ! -s "$dest" ]]; then
        log_warn "Empty snippet for $name; removing"
        rm -f "$dest"
        return 1
    fi
}

# fetch_builtin NAME PATHS_JSON
fetch_builtin() {
    local name="$1" paths_json="$2"
    local dir
    dir="$(get_dir src)/builtin/$name"
    ensure_dir "$dir"

    local copied=0
    while IFS= read -r raw_path; do
        [[ -z "$raw_path" ]] && continue
        local path
        path=$(expand_path "$raw_path")
        if [[ -d "$path" ]]; then
            local f
            for f in "$path"/_*; do
                [[ -f "$f" ]] || continue
                cp "$f" "$dir/"
                copied=$((copied + 1))
            done
        elif [[ -f "$path" ]]; then
            cp "$path" "$dir/"
            copied=$((copied + 1))
        else
            log_warn "Builtin path not found for $name: $path"
        fi
    done < <(echo "$paths_json" | jq -r '.[]')

    log_info "Copied $copied files for builtin source: $name"
}

# fetch_generated NAME COMMANDS_JSON
fetch_generated() {
    local name="$1" commands_json="$2"
    local dir
    dir="$(get_dir src)/generated/$name"
    ensure_dir "$dir"

    local generated=0
    while IFS= read -r entry; do
        local cmd_name script
        cmd_name=$(echo "$entry" | jq -r '.key')
        script=$(echo "$entry" | jq -r '.value')
        local out="$dir/_$cmd_name"
        log_debug "Generating completion for $cmd_name: $script"
        if ( eval "$script" ) > "$out" 2>/dev/null && [[ -s "$out" ]]; then
            generated=$((generated + 1))
        else
            rm -f "$out"
            log_warn "Generator failed or empty: $name/$cmd_name"
        fi
    done < <(echo "$commands_json" | jq -c 'to_entries[]')

    log_info "Generated $generated files for source: $name"
}

# fetch_generic NAME COMMANDS_JSON
# Defers to scripts/generic.sh per command. Skips if generic.sh is missing.
fetch_generic() {
    local name="$1" commands_json="$2"
    if [[ ! -x "$SCRIPT_DIR/generic.sh" ]]; then
        log_warn "generic.sh not available; skipping source: $name"
        return 0
    fi
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        log_info "Generating generic completion: $cmd"
        "$SCRIPT_DIR/generic.sh" "$cmd" || log_warn "generic generation failed for $cmd"
    done < <(echo "$commands_json" | jq -r 'keys[]')
}

# process_source SOURCE_JSON [FORCE]
process_source() {
    local source_json="$1" force="${2:-false}"
    local name type when
    name=$(echo "$source_json" | jq -r '.name')
    type=$(echo "$source_json" | jq -r '.type')
    when=$(echo "$source_json" | jq -r '.when // empty')

    if [[ -n "$when" ]] && ! has_command "$when"; then
        log_debug "Skipping $name (when=$when not on PATH)"
        return 0
    fi

    case "$type" in
        remote)
            local url paths
            url=$(echo "$source_json" | jq -r '.url')
            paths=$(echo "$source_json" | jq -c '.paths // []')
            fetch_remote "$name" "$url" "$paths" "$force"
            ;;
        snippet)
            local url rename
            url=$(echo "$source_json" | jq -r '.url')
            rename=$(echo "$source_json" | jq -r '.rename // empty')
            fetch_snippet "$name" "$url" "$rename" "$force"
            ;;
        builtin)
            local paths
            paths=$(echo "$source_json" | jq -c '.paths // []')
            fetch_builtin "$name" "$paths"
            ;;
        generated)
            local commands
            commands=$(echo "$source_json" | jq -c '.commands // {}')
            fetch_generated "$name" "$commands"
            ;;
        generic)
            local commands
            commands=$(echo "$source_json" | jq -c '.commands // {}')
            fetch_generic "$name" "$commands"
            ;;
        *)
            log_error "Unknown source type for $name: $type"
            return 1
            ;;
    esac
}

main() {
    local only_source="" force="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source) only_source="$2"; shift 2 ;;
            --force)  force="true"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    load_config
    print_header "Fetching Completions"
    ensure_dir "$(get_dir src)"

    if [[ -n "$only_source" ]]; then
        local src
        if ! src=$(get_source_by_name "$only_source"); then
            log_error "Source not found: $only_source"
            exit 1
        fi
        process_source "$src" "$force"
    else
        local n
        n=$(get_source_count)
        log_info "Processing $n sources"
        local i
        for ((i=0; i<n; i++)); do
            process_source "$(get_source "$i")" "$force"
        done
    fi

    print_success "Fetch complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
