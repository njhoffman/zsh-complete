#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/compile.sh"
}

teardown() {
    teardown_test_env
}

@test "get_command_info returns info for an existing command" {
    local info
    info=$(get_command_info "ls")
    [[ -n "$info" ]]
}

@test "get_command_info returns empty for nonexistent command" {
    run get_command_info "no_such_cmd_xyz123"
    [[ "$status" -ne 0 || -z "$output" ]]
}

@test "compile_commands writes valid JSON" {
    load_config
    compile_commands 5
    assert_file_exists "$TEST_TEMP_ROOT/data/commands.json"
    jq '.' "$TEST_TEMP_ROOT/data/commands.json" > /dev/null
}

@test "compile_existing writes valid JSON (possibly empty)" {
    load_config
    compile_existing
    assert_file_exists "$TEST_TEMP_ROOT/data/comps-existing.json"
    jq '.' "$TEST_TEMP_ROOT/data/comps-existing.json" > /dev/null
}

@test "compile_available creates priority-suffixed symlinks" {
    load_config
    mkdir -p "$TEST_TEMP_ROOT/src/generated/test-generated"
    echo '#compdef gen' > "$TEST_TEMP_ROOT/src/generated/test-generated/_gen"
    mkdir -p "$TEST_TEMP_ROOT/src/builtin/test-builtin"
    echo '#compdef bin' > "$TEST_TEMP_ROOT/src/builtin/test-builtin/_bin"

    compile_available

    [[ -L "$TEST_TEMP_ROOT/available/_gen.0" ]]
    [[ -L "$TEST_TEMP_ROOT/available/_bin.1" ]]
}

@test "compile_available JSON contains command entries with source + priority" {
    load_config
    mkdir -p "$TEST_TEMP_ROOT/src/generated/test-generated"
    echo '#compdef foo' > "$TEST_TEMP_ROOT/src/generated/test-generated/_foo"

    compile_available

    local entry
    entry=$(jq -c '.foo[0]' "$TEST_TEMP_ROOT/data/comps-available.json")
    [[ "$entry" == *'"source":"test-generated"'* ]]
    [[ "$entry" == *'"priority":0'* ]]
}

@test "compile_available handles names with special characters" {
    load_config
    mkdir -p "$TEST_TEMP_ROOT/src/generated/test-generated"
    # Names with quotes don't survive ln on most filesystems; use weird-but-legal chars
    echo '#compdef weird-cmd.v2' > "$TEST_TEMP_ROOT/src/generated/test-generated/_weird-cmd.v2"

    compile_available

    jq '.' "$TEST_TEMP_ROOT/data/comps-available.json" > /dev/null
    [[ $(jq -r '.["weird-cmd.v2"][0].source' "$TEST_TEMP_ROOT/data/comps-available.json") == "test-generated" ]]
}

@test "compile_available emits empty {} when no sources have content" {
    load_config
    compile_available
    [[ $(cat "$TEST_TEMP_ROOT/data/comps-available.json") == "{}" ]]
}

@test "main runs all compile stages" {
    mkdir -p "$TEST_TEMP_ROOT/src/generated/test-generated"
    echo '#compdef m' > "$TEST_TEMP_ROOT/src/generated/test-generated/_m"
    main --limit 5
    assert_file_exists "$TEST_TEMP_ROOT/data/commands.json"
    assert_file_exists "$TEST_TEMP_ROOT/data/comps-existing.json"
    assert_file_exists "$TEST_TEMP_ROOT/data/comps-available.json"
}
