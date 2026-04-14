#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/output.sh"
    load_config

    # A valid completion file
    cat > "$TEST_TEMP_ROOT/_good" << 'EOF'
#compdef good
_good() {
    _arguments '-h[help]'
}
_good "$@"
EOF

    # A syntactically broken completion file
    cat > "$TEST_TEMP_ROOT/_broken" << 'EOF'
#compdef broken
_broken() {
    _arguments '-h[help'
EOF
}

teardown() {
    teardown_test_env
}

@test "check_file returns ok for valid file" {
    local result
    result=$(check_file "$TEST_TEMP_ROOT/_good")
    [[ "$result" == "ok" ]]
}

@test "check_file flags syntax error" {
    local result
    result=$(check_file "$TEST_TEMP_ROOT/_broken") || true
    [[ "$result" == syntax:* ]]
}

@test "check_file flags missing file" {
    local result
    result=$(check_file "$TEST_TEMP_ROOT/_does_not_exist") || true
    [[ "$result" == missing:* ]]
}

@test "check_all writes pass/fail to comps-output.json" {
    cat > "$TEST_TEMP_ROOT/data/comps-available.json" << EOF
{
  "good":   [{"path":"$TEST_TEMP_ROOT/_good","lines":1,"source":"x","priority":0}],
  "broken": [{"path":"$TEST_TEMP_ROOT/_broken","lines":1,"source":"x","priority":0}]
}
EOF
    check_all > /dev/null 2>&1 || true
    [[ $(jq -r '.good.status'   "$TEST_TEMP_ROOT/data/comps-output.json") == "pass" ]]
    [[ $(jq -r '.broken.status' "$TEST_TEMP_ROOT/data/comps-output.json") == "fail" ]]
}

@test "main --file returns ok for good file" {
    run main --file "$TEST_TEMP_ROOT/_good"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ok"* ]]
}

@test "main --file reports syntax for broken file" {
    run main --file "$TEST_TEMP_ROOT/_broken"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"syntax"* ]]
}
