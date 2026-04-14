#!/usr/bin/env bash
# Compile commands + completion sources into JSON data files and link them
# into dirs.available with priority suffixes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Compile commands and completions into data files; link available completions.

Options:
    --limit N    Process at most N commands (0 = unlimited)
    -h, --help   Show this help
EOF
}

# Inspect a command via \`type -a\` and emit one JSON object per definition.
get_command_info() {
    local cmd="$1"
    local type_output
    type_output=$(type -a "$cmd" 2>/dev/null) || return 1

    local line
    while IFS= read -r line; do
        if [[ "$line" =~ "is aliased to" ]]; then
            local def="${line#*\`}"
            def="${def%\'*}"
            jq -nc --arg def "$def" '{type:"alias", definition:$def}'
        elif [[ "$line" =~ "is a shell builtin" ]]; then
            jq -nc '{type:"builtin"}'
        elif [[ "$line" =~ "is a shell function" ]]; then
            jq -nc '{type:"function"}'
        elif [[ "$line" =~ "is " ]]; then
            local path="${line##* is }"
            if [[ -f "$path" ]]; then
                local mime
                mime=$(get_mime_type "$path")
                if [[ "$mime" =~ ^text/ ]]; then
                    local lines
                    lines=$(count_lines "$path")
                    jq -nc --arg p "$path" --arg m "$mime" --argjson l "$lines" \
                        '{type:"file", path:$p, mime:$m, lines:$l}'
                else
                    jq -nc --arg p "$path" --arg m "$mime" \
                        '{type:"file", path:$p, mime:$m}'
                fi
            fi
        fi
    done <<< "$type_output"
}

# Stream JSON objects {key, value} pairs into a single object.
# Reads NUL-separated "key<TAB>json" lines on stdin.
_stream_to_object() {
    jq -sR 'split("\u0000") | map(select(length>0))
            | map(split("\t") | {key:.[0], value:(.[1]|fromjson)})
            | from_entries'
}

# Build commands.json
compile_commands() {
    local limit="${1:-${COMPILE_COMMANDS_LIMIT:-0}}"
    log_info "Compiling commands data (limit=${limit:-0})"

    local commands_file
    commands_file=$(get_file commands)
    ensure_dir "$(dirname "$commands_file")"

    local count=0
    declare -A seen=()
    local tmp
    tmp=$(mktemp)

    local path_dirs dir cmd_path cmd_name raw info
    IFS=':' read -ra path_dirs <<< "$PATH"
    for dir in "${path_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        for cmd_path in "$dir"/*; do
            [[ -x "$cmd_path" && -f "$cmd_path" ]] || continue
            if [[ "$limit" -gt 0 && "$count" -ge "$limit" ]]; then
                break 2
            fi
            cmd_name=$(basename "$cmd_path")
            [[ -n "${seen[$cmd_name]:-}" ]] && continue
            seen["$cmd_name"]=1

            raw=$(get_command_info "$cmd_name" 2>/dev/null) || true
            [[ -z "$raw" ]] && continue
            info=$(echo "$raw" | jq -cs '.')
            printf '%s\t%s\0' "$cmd_name" "$info" >> "$tmp"
            count=$((count + 1))
        done
    done

    _stream_to_object < "$tmp" > "$commands_file"
    rm -f "$tmp"
    log_info "Recorded $count commands"
}

# Build comps-existing.json by scanning standard zsh dirs.
compile_existing() {
    log_info "Compiling existing completions data"

    local existing_file
    existing_file=$(get_file existing)
    ensure_dir "$(dirname "$existing_file")"

    local -a comp_dirs=(
        "/usr/share/zsh/functions/Completion"
        "/usr/share/zsh/vendor-completions"
        "/usr/local/share/zsh/site-functions"
        "/usr/share/zsh/site-functions"
        "$HOME/.zsh/completions"
    )

    local tmp
    tmp=$(mktemp)
    declare -A seen=()
    local count=0

    local d f basename cmd_name lines entry
    for d in "${comp_dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r -d '' f; do
            basename=$(basename "$f")
            cmd_name="${basename#_}"
            lines=$(count_lines "$f")
            entry=$(jq -nc --arg p "$f" --argjson l "$lines" '[{path:$p, lines:$l}]')
            if [[ -n "${seen[$cmd_name]:-}" ]]; then
                continue
            fi
            seen["$cmd_name"]=1
            printf '%s\t%s\0' "$cmd_name" "$entry" >> "$tmp"
            count=$((count + 1))
        done < <(find "$d" -maxdepth 2 -name '_*' -type f -print0 2>/dev/null)
    done

    if [[ -s "$tmp" ]]; then
        _stream_to_object < "$tmp" > "$existing_file"
    else
        echo '{}' > "$existing_file"
    fi
    rm -f "$tmp"
    log_info "Found $count existing completions"
}

# Build comps-available.json + symlinks under dirs.available.
compile_available() {
    log_info "Compiling available completions"

    local available_file available_dir src_dir
    available_file=$(get_file available)
    available_dir=$(get_dir available)
    src_dir=$(get_dir src)

    ensure_dir "$(dirname "$available_file")"
    ensure_dir "$available_dir"

    rm -f "$available_dir"/_*

    local n
    n=$(get_source_count)
    local total=0
    local tmp
    tmp=$(mktemp)
    declare -A by_cmd=()

    local i source_json name source_path comp_file basename cmd_name link lines entry
    for ((i=0; i<n; i++)); do
        source_json=$(get_source "$i")
        name=$(echo "$source_json" | jq -r '.name')
        source_path=$(get_source_dir "$source_json")
        [[ -d "$source_path" ]] || { log_debug "No content for source $name at $source_path"; continue; }

        log_debug "Processing source $name (priority $i)"
        for comp_file in "$source_path"/_*; do
            [[ -f "$comp_file" ]] || continue
            basename=$(basename "$comp_file")
            cmd_name="${basename#_}"
            link="$available_dir/${basename}.${i}"
            ln -sf "$comp_file" "$link"
            lines=$(count_lines "$comp_file")
            entry=$(jq -nc --arg p "$link" --argjson l "$lines" --arg s "$name" --argjson pri "$i" \
                '{path:$p, lines:$l, source:$s, priority:$pri}')
            by_cmd["$cmd_name"]="${by_cmd[$cmd_name]:+${by_cmd[$cmd_name]}$'\n'}$entry"
            total=$((total + 1))
        done
    done

    local cmd
    for cmd in "${!by_cmd[@]}"; do
        local arr
        arr=$(printf '%s\n' "${by_cmd[$cmd]}" | jq -s '.')
        printf '%s\t%s\0' "$cmd" "$arr" >> "$tmp"
    done

    if [[ -s "$tmp" ]]; then
        _stream_to_object < "$tmp" > "$available_file"
    else
        echo '{}' > "$available_file"
    fi
    rm -f "$tmp"
    log_info "Linked $total completions for ${#by_cmd[@]} commands"
}

main() {
    local limit=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit) limit="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
    [[ -n "${COMPILE_COMMANDS_LIMIT:-}" && "$limit" -eq 0 ]] && limit="$COMPILE_COMMANDS_LIMIT"

    load_config
    print_header "Compiling Completions"
    compile_commands "$limit"
    compile_existing
    compile_available
    print_success "Compilation complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
