#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/generic.sh"
}

teardown() {
    teardown_test_env
}

@test "strip_ansi removes color escapes" {
    local input output
    input=$'\033[31mred\033[0m and \033[1mbold\033[0m'
    output=$(printf '%s' "$input" | strip_ansi)
    [[ "$output" == "red and bold" ]]
}

@test "parse_options extracts short+long with arg" {
    local result
    result=$(parse_options < "$FIXTURES_DIR/sample-help.txt")
    [[ "$result" == *$'-o\t--output\tFILE\tWrite output to FILE'* ]]
}

@test "parse_options extracts short+long without arg" {
    local result
    result=$(parse_options < "$FIXTURES_DIR/sample-help.txt")
    [[ "$result" == *$'-h\t--help\t\tShow this help message and exit'* ]]
}

@test "parse_options extracts long-only options" {
    local result
    result=$(parse_options < "$FIXTURES_DIR/sample-help.txt")
    [[ "$result" == *$'\t--version\t\tPrint version and exit'* ]]
}

@test "parse_options extracts short-only options" {
    local result
    result=$(parse_options < "$FIXTURES_DIR/sample-help.txt")
    [[ "$result" == *$'-n\t\t\tDry run (no changes)'* ]]
}

@test "render_completion produces zsh-syntactically valid output" {
    local out
    out=$(parse_options < "$FIXTURES_DIR/sample-help.txt" | render_completion "sample")
    [[ "$out" == "#compdef sample"* ]]
    echo "$out" | zsh -n
}

@test "generate_for_command --stdout writes to stdout" {
    load_config
    local out
    out=$(generate_for_command "sample" "$FIXTURES_DIR/sample-help.txt" "true")
    [[ "$out" == "#compdef sample"* ]]
    [[ "$out" == *"_arguments"* ]]
}

@test "generate_for_command writes file and updates comps-generic.json" {
    load_config
    generate_for_command "sample" "$FIXTURES_DIR/sample-help.txt" "false"
    assert_file_exists "$TEST_TEMP_ROOT/src/generic/generic/_sample"
    assert_file_exists "$TEST_TEMP_ROOT/data/comps-generic.json"
    [[ $(jq -r '.sample.source' "$TEST_TEMP_ROOT/data/comps-generic.json") == "generic" ]]
}

@test "main with no command exits non-zero" {
    run main
    [[ "$status" -ne 0 ]]
}

@test "main --stdout fixture path emits a completion" {
    run main --source "$FIXTURES_DIR/sample-help.txt" --stdout sample
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"#compdef sample"* ]]
}
