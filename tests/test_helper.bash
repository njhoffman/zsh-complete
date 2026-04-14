#!/usr/bin/env bash
# Test helper for bats tests

# Project paths
export TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
export SCRIPTS_DIR="$PROJECT_ROOT/scripts"
export FIXTURES_DIR="$TEST_DIR/fixtures"

# Test environment paths
export TEST_TEMP_ROOT="/tmp/zsh-complete-test"
export CONFIG_FILE="$FIXTURES_DIR/config.json"

# Suppress colored output in tests for easier assertion
export NO_COLOR=1

# Set log level to debug for tests
export LOG_LEVEL=debug

# Source utilities
source "$SCRIPTS_DIR/lib/utils.sh"

# Setup test environment
setup_test_env() {
    rm -rf "$TEST_TEMP_ROOT"
    mkdir -p "$TEST_TEMP_ROOT"/{data,src/{remote,snippet,builtin,generated,generic},available,active,temp,mock-builtin}

    # Create mock completion files
    echo '#compdef testcmd1' > "$TEST_TEMP_ROOT/mock-builtin/_testcmd1"
    echo '#compdef testcmd2' > "$TEST_TEMP_ROOT/mock-builtin/_testcmd2"
}

# Cleanup test environment
teardown_test_env() {
    rm -rf "$TEST_TEMP_ROOT"
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Expected file to exist: $file" >&2
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Expected directory to exist: $dir" >&2
        return 1
    fi
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "Expected file '$file' to contain: $pattern" >&2
        return 1
    fi
}

# Assert output contains string
assert_output_contains() {
    local pattern="$1"
    if [[ ! "$output" =~ $pattern ]]; then
        echo "Expected output to contain: $pattern" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# Assert JSON file has key
assert_json_has_key() {
    local file="$1"
    local key="$2"
    if ! jq -e ".$key" "$file" > /dev/null 2>&1; then
        echo "Expected JSON file '$file' to have key: $key" >&2
        return 1
    fi
}

# Get JSON value
get_json_value() {
    local file="$1"
    local path="$2"
    jq -r "$path" "$file"
}
