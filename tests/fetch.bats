#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/fetch.sh"
}

teardown() {
    teardown_test_env
}

@test "normalize_url rewrites github blob URLs to raw" {
    local result
    result=$(normalize_url "https://github.com/foo/bar/blob/main/_baz")
    [[ "$result" == "https://raw.githubusercontent.com/foo/bar/main/_baz" ]]
}

@test "normalize_url leaves non-github URLs alone" {
    local result
    result=$(normalize_url "https://example.com/_thing")
    [[ "$result" == "https://example.com/_thing" ]]
}

@test "fetch_builtin copies completion files into src/builtin/<name>" {
    load_config
    fetch_builtin "test-builtin" "[\"$TEST_TEMP_ROOT/mock-builtin\"]"
    assert_file_exists "$TEST_TEMP_ROOT/src/builtin/test-builtin/_testcmd1"
    assert_file_exists "$TEST_TEMP_ROOT/src/builtin/test-builtin/_testcmd2"
}

@test "fetch_builtin warns and continues on missing path" {
    load_config
    run fetch_builtin "test-missing" '["/nonexistent/path"]'
    [[ "$status" -eq 0 ]]
}

@test "fetch_generated writes stdout to src/generated/<name>/_<key>" {
    load_config
    fetch_generated "gen-src" '{"foo": "echo \"#compdef foo\""}'
    assert_file_exists "$TEST_TEMP_ROOT/src/generated/gen-src/_foo"
    assert_file_contains "$TEST_TEMP_ROOT/src/generated/gen-src/_foo" "#compdef foo"
}

@test "fetch_generated removes empty output" {
    load_config
    fetch_generated "gen-empty" '{"bar": "true"}'
    [[ ! -f "$TEST_TEMP_ROOT/src/generated/gen-empty/_bar" ]]
}

@test "fetch_generated removes failing-command output" {
    load_config
    fetch_generated "gen-fail" '{"baz": "exit 1"}'
    [[ ! -f "$TEST_TEMP_ROOT/src/generated/gen-fail/_baz" ]]
}

@test "fetch_snippet uses local file:// URL and obeys rename" {
    load_config
    local fixture="$TEST_TEMP_ROOT/_snippet_src"
    echo '#compdef snippet' > "$fixture"
    fetch_snippet "snip" "file://$fixture" "_renamed"
    assert_file_exists "$TEST_TEMP_ROOT/src/snippet/snip/_renamed"
    assert_file_contains "$TEST_TEMP_ROOT/src/snippet/snip/_renamed" "#compdef snippet"
}

@test "fetch_snippet skips re-download when present and not --force" {
    load_config
    local fixture="$TEST_TEMP_ROOT/_snippet_src"
    echo 'first' > "$fixture"
    fetch_snippet "snip2" "file://$fixture" "_x"
    echo 'second' > "$fixture"
    fetch_snippet "snip2" "file://$fixture" "_x"
    grep -q 'first' "$TEST_TEMP_ROOT/src/snippet/snip2/_x"
}

@test "fetch_snippet re-downloads with --force" {
    load_config
    local fixture="$TEST_TEMP_ROOT/_snippet_src"
    echo 'first' > "$fixture"
    fetch_snippet "snip3" "file://$fixture" "_x"
    echo 'second' > "$fixture"
    fetch_snippet "snip3" "file://$fixture" "_x" "true"
    grep -q 'second' "$TEST_TEMP_ROOT/src/snippet/snip3/_x"
}

@test "process_source dispatches builtin type" {
    load_config
    local src
    src=$(get_source_by_name "test-builtin")
    process_source "$src"
    assert_dir_exists "$TEST_TEMP_ROOT/src/builtin/test-builtin"
}

@test "process_source dispatches generated type" {
    load_config
    local src
    src=$(get_source_by_name "test-generated")
    process_source "$src"
    assert_file_exists "$TEST_TEMP_ROOT/src/generated/test-generated/_testcmd"
}

@test "process_source skips when 'when' command is absent" {
    load_config
    local src='{"name":"skipme","type":"builtin","when":"no_such_command_xyz","paths":["/tmp"]}'
    run process_source "$src"
    [[ "$status" -eq 0 ]]
    [[ ! -d "$TEST_TEMP_ROOT/src/builtin/skipme" ]]
}

@test "main --source filters to a single source" {
    main --source test-generated
    assert_file_exists "$TEST_TEMP_ROOT/src/generated/test-generated/_testcmd"
    [[ ! -d "$TEST_TEMP_ROOT/src/builtin/test-builtin" ]]
}

@test "main creates src directory" {
    main
    assert_dir_exists "$TEST_TEMP_ROOT/src"
}

@test "main --source with unknown source exits non-zero" {
    run main --source nope
    [[ "$status" -ne 0 ]]
}
