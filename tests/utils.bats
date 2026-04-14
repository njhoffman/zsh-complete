#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "expand_path replaces \$HOME" {
    local result
    result=$(expand_path '$HOME/test/path')
    [[ "$result" == "$HOME/test/path" ]]
}

@test "expand_path replaces tilde" {
    local result
    result=$(expand_path '~/test/path')
    [[ "$result" == "$HOME/test/path" ]]
}

@test "expand_path handles paths without variables" {
    local result
    result=$(expand_path '/usr/local/bin')
    [[ "$result" == "/usr/local/bin" ]]
}

@test "load_config loads dirs from config" {
    load_config
    [[ -n "${CONFIG_DIRS[temp]}" ]]
    [[ -n "${CONFIG_DIRS[src]}" ]]
    [[ -n "${CONFIG_DIRS[available]}" ]]
    [[ -n "${CONFIG_DIRS[active]}" ]]
}

@test "load_config loads files from config" {
    load_config
    [[ -n "${CONFIG_FILES[history]}" ]]
    [[ -n "${CONFIG_FILES[commands]}" ]]
}

@test "get_dir returns expanded path" {
    load_config
    local result
    result=$(get_dir "temp")
    [[ "$result" == "/tmp/zsh-complete-test/temp" ]]
}

@test "get_file returns expanded path" {
    load_config
    local result
    result=$(get_file "history")
    [[ "$result" == "/tmp/zsh-complete-test/history.log" ]]
}

@test "get_dir fails for unknown key" {
    load_config
    run get_dir "nonexistent"
    [[ "$status" -ne 0 ]]
}

@test "get_source_count returns correct count" {
    local count
    count=$(get_source_count)
    [[ "$count" -eq 2 ]]
}

@test "get_source returns source by index" {
    local source
    source=$(get_source 0)
    [[ $(echo "$source" | jq -r '.name') == "test-generated" ]]
}

@test "ensure_dir creates directory" {
    local test_dir="$TEST_TEMP_ROOT/new_dir"
    [[ ! -d "$test_dir" ]]
    ensure_dir "$test_dir"
    [[ -d "$test_dir" ]]
}

@test "log_level_to_num converts levels correctly" {
    [[ $(log_level_to_num "error") -eq 0 ]]
    [[ $(log_level_to_num "warn") -eq 1 ]]
    [[ $(log_level_to_num "info") -eq 2 ]]
    [[ $(log_level_to_num "debug") -eq 3 ]]
}

@test "log_info writes to log file" {
    load_config
    log_info "Test message"
    assert_file_contains "$TEST_TEMP_ROOT/history.log" "Test message"
}

@test "count_lines returns correct count" {
    echo -e "line1\nline2\nline3" > "$TEST_TEMP_ROOT/testfile"
    local count
    count=$(count_lines "$TEST_TEMP_ROOT/testfile")
    [[ "$count" -eq 3 ]]
}

@test "count_lines returns 0 for nonexistent file" {
    local count
    count=$(count_lines "$TEST_TEMP_ROOT/nonexistent")
    [[ "$count" -eq 0 ]]
}

@test "command_exists returns true for existing command" {
    command_exists "ls"
}

@test "command_exists returns false for nonexistent command" {
    ! command_exists "nonexistent_command_12345"
}

@test "get_mime_type returns mime type" {
    echo "test" > "$TEST_TEMP_ROOT/testfile.txt"
    local mime
    mime=$(get_mime_type "$TEST_TEMP_ROOT/testfile.txt")
    [[ "$mime" == "text/plain" ]]
}

@test "get_source_by_name returns source by name" {
    local src
    src=$(get_source_by_name "test-builtin")
    [[ $(echo "$src" | jq -r '.type') == "builtin" ]]
}

@test "get_source_by_name returns 1 for unknown name" {
    run get_source_by_name "no-such-source"
    [[ "$status" -ne 0 ]]
}

@test "get_source_dir builds <src>/<type>/<name>" {
    load_config
    local src dir
    src=$(get_source_by_name "test-builtin")
    dir=$(get_source_dir "$src")
    [[ "$dir" == "/tmp/zsh-complete-test/src/builtin/test-builtin" ]]
}

@test "get_command_overrides returns the commands map" {
    local map
    map=$(get_command_overrides)
    [[ $(echo "$map" | jq -r '.testcmd') == "test-builtin" ]]
}

@test "has_command matches command_exists" {
    has_command "ls"
    ! has_command "no_such_command_xyz"
}
