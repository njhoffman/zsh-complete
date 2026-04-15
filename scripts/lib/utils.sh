#!/usr/bin/env bash
# Shared utilities for zsh-complete scripts

# Prevent double-sourcing
[[ -n "${_UTILS_SH_SOURCED:-}" ]] && return 0
_UTILS_SH_SOURCED=1

set -eo pipefail

# Colors for terminal output
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'

# Log levels (lower = more severe)
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3

# Default log level from environment or info
CURRENT_LOG_LEVEL="${LOG_LEVEL:-info}"

# Script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Config file path
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/config.json}"

# Parsed config cache (use -gA for global associative arrays)
declare -gA CONFIG_DIRS=()
declare -gA CONFIG_FILES=()
CONFIG_LOADED=false

# Convert log level name to number
log_level_to_num() {
    local level
    level=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$level" in
        error) echo $LOG_LEVEL_ERROR ;;
        warn)  echo $LOG_LEVEL_WARN ;;
        info)  echo $LOG_LEVEL_INFO ;;
        debug) echo $LOG_LEVEL_DEBUG ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# Get current log level as number
get_current_log_level() {
    log_level_to_num "$CURRENT_LOG_LEVEL"
}

# Format timestamp for logging
log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Tracks the previous log call's wall-clock for elapsed-time annotations.
LAST_LOG_EPOCH="${EPOCHREALTIME:-}"

# Compute elapsed seconds since the last log call. Empty if <1s or unavailable.
# Override with TEST_LOG_ELAPSED to bypass the wall clock for deterministic tests.
log_elapsed_suffix() {
    if [[ -n "${TEST_LOG_ELAPSED:-}" ]]; then
        printf ' (took %ss)' "$TEST_LOG_ELAPSED"
        return
    fi

    local now="${EPOCHREALTIME:-}"
    [[ -z "$now" || -z "$LAST_LOG_EPOCH" ]] && { LAST_LOG_EPOCH="$now"; return; }

    # EPOCHREALTIME = "<seconds>.<microseconds>"; convert to integer microseconds
    # to avoid awk/bc dependency.
    local now_us prev_us delta_us
    now_us="${now/./}"
    prev_us="${LAST_LOG_EPOCH/./}"
    delta_us=$(( now_us - prev_us ))
    LAST_LOG_EPOCH="$now"

    if (( delta_us >= 1000000 )); then
        local s ms
        s=$(( delta_us / 1000000 ))
        ms=$(( (delta_us % 1000000) / 100000 ))
        printf ' (took %d.%ds)' "$s" "$ms"
    fi
}

# Write to log file if configured
log_to_file() {
    local level="$1"
    local message="$2"

    # Only log to file if config is loaded and history file is configured
    if [[ "$CONFIG_LOADED" == "true" ]] && [[ -v CONFIG_FILES[history] ]]; then
        local log_file="${CONFIG_FILES[history]}"
        if [[ -n "$log_file" ]]; then
            local expanded_path
            expanded_path=$(expand_path "$log_file")
            mkdir -p "$(dirname "$expanded_path")"
            echo "[$(log_timestamp)] [$level] $message" >> "$expanded_path"
        fi
    fi
}

# Core logging function
_log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    local message="$4"

    local current_level_num suffix
    current_level_num=$(get_current_log_level)
    suffix=$(log_elapsed_suffix)

    # Always log to file regardless of level
    log_to_file "$level" "${message}${suffix}"

    # Only output to terminal if level is at or below current threshold
    if [[ $level_num -le $current_level_num ]]; then
        echo -e "${color}[${level}]${COLOR_RESET} ${message}${suffix}" >&2
    fi
}

# Logging functions
log_error() {
    _log "ERROR" $LOG_LEVEL_ERROR "$COLOR_RED" "$*"
}

log_warn() {
    _log "WARN" $LOG_LEVEL_WARN "$COLOR_YELLOW" "$*"
}

log_info() {
    _log "INFO" $LOG_LEVEL_INFO "$COLOR_GREEN" "$*"
}

log_debug() {
    _log "DEBUG" $LOG_LEVEL_DEBUG "$COLOR_BLUE" "$*"
}

# Expand $HOME and other variables in paths
expand_path() {
    local path="$1"
    # Replace $HOME with actual home directory
    path="${path//\$HOME/$HOME}"
    # Expand ~ at start of path
    path="${path/#\~/$HOME}"
    echo "$path"
}

# Check if jq is installed
require_jq() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install with: sudo apt install jq"
        exit 1
    fi
}

# Load configuration from config.json
load_config() {
    require_jq

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    log_debug "Loading config from $CONFIG_FILE"

    # Strip comments (lines starting with // or /* */) for JSON parsing
    local json_content
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")

    # Parse dirs
    local dirs_output
    dirs_output=$(echo "$json_content" | jq -r '.dirs | to_entries | .[] | "\(.key)=\(.value)"')
    while IFS='=' read -r key value; do
        [[ -n "$key" ]] && CONFIG_DIRS["$key"]="$value"
    done <<< "$dirs_output"

    # Parse files
    local files_output
    files_output=$(echo "$json_content" | jq -r '.files | to_entries | .[] | "\(.key)=\(.value)"')
    while IFS='=' read -r key value; do
        [[ -n "$key" ]] && CONFIG_FILES["$key"]="$value"
    done <<< "$files_output"

    CONFIG_LOADED=true
    log_debug "Loaded ${#CONFIG_DIRS[@]} dirs and ${#CONFIG_FILES[@]} files from config"
}

# Get a directory path from config (expanded)
get_dir() {
    local key="$1"
    if [[ ! -v CONFIG_DIRS[$key] ]]; then
        log_error "Directory key not found in config: $key"
        return 1
    fi
    expand_path "${CONFIG_DIRS[$key]}"
}

# Get a file path from config (expanded)
get_file() {
    local key="$1"
    if [[ ! -v CONFIG_FILES[$key] ]]; then
        log_error "File key not found in config: $key"
        return 1
    fi
    expand_path "${CONFIG_FILES[$key]}"
}

# Get sources array from config as JSON
get_sources() {
    require_jq
    local json_content
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")
    echo "$json_content" | jq -c '.sources'
}

# Get source count
get_source_count() {
    require_jq
    local json_content
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")
    echo "$json_content" | jq '.sources | length'
}

# Get a specific source by index
get_source() {
    local index="$1"
    require_jq
    local json_content
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")
    echo "$json_content" | jq -c ".sources[$index]"
}

# Get a specific source by name; prints empty string + returns 1 if not found
get_source_by_name() {
    local name="$1"
    require_jq
    local json_content result
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")
    result=$(echo "$json_content" | jq -c --arg n "$name" '.sources[] | select(.name == $n)')
    if [[ -z "$result" ]]; then
        return 1
    fi
    echo "$result"
}

# Get the on-disk source directory for a source JSON object: $src/<type>/<name>
get_source_dir() {
    local source_json="$1"
    local name type
    name=$(echo "$source_json" | jq -r '.name')
    type=$(echo "$source_json" | jq -r '.type')
    if [[ -z "$name" || "$name" == "null" || -z "$type" || "$type" == "null" ]]; then
        log_error "Source missing name or type: $source_json"
        return 1
    fi
    printf '%s/%s/%s' "$(get_dir src)" "$type" "$name"
}

# Get the per-command override map (config.commands) as JSON object
get_command_overrides() {
    require_jq
    local json_content
    json_content=$(sed -E -e 's|^[[:space:]]*//.*$||' -e '/\/\*/,/\*\//d' "$CONFIG_FILE")
    echo "$json_content" | jq -c '.commands // {}'
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Render a progress bar to stderr. Only draws when stderr is a TTY.
# Usage: progress_bar CURRENT TOTAL [LABEL]
# Force off by setting NO_PROGRESS=1; force on with FORCE_PROGRESS=1.
progress_bar() {
    local current="$1" total="$2" label="${3:-}"
    [[ "${NO_PROGRESS:-0}" == "1" ]] && return 0
    if [[ "${FORCE_PROGRESS:-0}" != "1" && ! -t 2 ]]; then
        return 0
    fi
    (( total <= 0 )) && return 0

    local width=30 pct filled empty bar
    pct=$(( current * 100 / total ))
    (( pct > 100 )) && pct=100
    filled=$(( current * width / total ))
    (( filled > width )) && filled=$width
    empty=$(( width - filled ))

    bar=$(printf '%*s' "$filled" '' | tr ' ' '=')
    bar+=$(printf '%*s' "$empty"  '' | tr ' ' ' ')

    # \r returns to start of line; \033[K clears to end.
    printf '\r\033[K[%s] %d/%d (%d%%) %s' \
        "$bar" "$current" "$total" "$pct" "$label" >&2
}

# Finish a progress bar: clear the line so subsequent output isn't mangled.
progress_done() {
    [[ "${NO_PROGRESS:-0}" == "1" ]] && return 0
    if [[ "${FORCE_PROGRESS:-0}" != "1" && ! -t 2 ]]; then
        return 0
    fi
    printf '\r\033[K' >&2
}

# Print aligned output (key-value pairs)
print_aligned() {
    local key="$1"
    local value="$2"
    local width="${3:-20}"
    printf "${COLOR_CYAN}%-${width}s${COLOR_RESET} %s\n" "$key:" "$value"
}

# Print section header
print_header() {
    local title="$1"
    echo -e "\n${COLOR_BOLD}=== $title ===${COLOR_RESET}\n"
}

# Print success message
print_success() {
    echo -e "${COLOR_GREEN}$*${COLOR_RESET}"
}

# Print error message (to stdout, not log)
print_error() {
    echo -e "${COLOR_RED}$*${COLOR_RESET}"
}

# Count lines in a file
count_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file"
    else
        echo 0
    fi
}

# Get file mime type
get_mime_type() {
    local file="$1"
    file --mime-type -b "$file" 2>/dev/null || echo "unknown"
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Alias used by `when` source guards
has_command() {
    command_exists "$1"
}

# Interactive picker: prefer fzf, fall back to bash select.
# Usage: fzf_or_select "Prompt: " "item1" "item2" ...
# Selection prints to stdout. Returns 1 if nothing chosen.
fzf_or_select() {
    local prompt="$1"
    shift
    local items=("$@")

    [[ ${#items[@]} -eq 0 ]] && return 1

    if command_exists fzf && [[ -t 0 ]]; then
        printf '%s\n' "${items[@]}" | fzf --prompt="$prompt" --height=40% --reverse
        return $?
    fi

    local choice
    PS3="$prompt"
    select choice in "${items[@]}"; do
        if [[ -n "$choice" ]]; then
            echo "$choice"
            return 0
        fi
    done
    return 1
}
