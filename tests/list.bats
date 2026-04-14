#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/list.sh"

    # Create test data files
    mkdir -p "$TEST_TEMP_ROOT/data"

    # commands.json - list of commands
    cat > "$TEST_TEMP_ROOT/data/commands.json" << 'EOF'
{
  "ls": [{"type": "file", "path": "/bin/ls"}],
  "grep": [{"type": "file", "path": "/bin/grep"}],
  "cat": [{"type": "file", "path": "/bin/cat"}],
  "orphan_cmd": [{"type": "file", "path": "/bin/orphan"}]
}
EOF

    # comps-available.json - available completions
    cat > "$TEST_TEMP_ROOT/data/comps-available.json" << 'EOF'
{
  "ls": [{"path": "/tmp/test/_ls.0", "lines": 100}],
  "grep": [{"path": "/tmp/test/_grep.0", "lines": 50}],
  "newcmd": [{"path": "/tmp/test/_newcmd.0", "lines": 30}]
}
EOF

    # comps-existing.json - installed completions
    cat > "$TEST_TEMP_ROOT/data/comps-existing.json" << 'EOF'
{
  "ls": [{"path": "/usr/share/zsh/functions/_ls", "lines": 100}],
  "cat": [{"path": "/usr/share/zsh/functions/_cat", "lines": 40}],
  "oldcmd": [{"path": "/usr/share/zsh/functions/_oldcmd", "lines": 20}]
}
EOF
}

teardown() {
    teardown_test_env
}

@test "list_to_install returns commands with available but not installed completions" {
    load_config
    local result
    result=$(list_to_install)

    # grep has available but not installed
    [[ "$result" == *"grep"* ]]
    # ls is both available and installed, should not be listed
    [[ "$result" != *"ls"* ]]
}

@test "list_to_uninstall returns installed completions without associated command" {
    load_config
    local result
    result=$(list_to_uninstall)

    # oldcmd is installed but not in commands
    [[ "$result" == *"oldcmd"* ]]
    # ls is in commands, should not be listed
    [[ "$result" != *"ls"* ]]
}

@test "list_missing returns commands without available completions" {
    load_config
    local result
    result=$(list_missing)

    # cat is a command but has no available completion
    [[ "$result" == *"cat"* ]]
    # ls has available completion, should not be listed
    [[ "$result" != *"ls"* ]]
}

@test "list_existing returns commands with installed completions" {
    load_config
    local result
    result=$(list_existing)

    # ls and cat have installed completions and are valid commands
    [[ "$result" == *"ls"* ]]
    [[ "$result" == *"cat"* ]]
}

@test "list_all returns all commands with status" {
    load_config
    local result
    result=$(list_all)

    # Should include all commands
    [[ "$result" == *"ls"* ]]
    [[ "$result" == *"grep"* ]]
    [[ "$result" == *"cat"* ]]
}

@test "show_help displays usage information" {
    run show_help
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--to-install"* ]]
    [[ "$output" == *"--missing"* ]]
}

@test "main with --to-install shows correct output" {
    run main --to-install
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grep"* ]]
}

@test "main with --json outputs valid JSON" {
    # Suppress stderr and capture only stdout
    local json_output
    json_output=$(main --to-install --json 2>/dev/null)
    # Validate it's JSON
    echo "$json_output" | jq '.' > /dev/null
}

@test "main with unknown option shows error" {
    run main --unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown option"* ]]
}

@test "load_data returns error when commands.json missing" {
    rm "$TEST_TEMP_ROOT/data/commands.json"
    run load_data
    [[ "$status" -ne 0 ]]
}

@test "list_existing reports installed commands and includes available count" {
    load_config
    local result
    result=$(list_existing)
    [[ "$result" == *"ls"* ]]
    [[ "$result" == *"available"* ]]
}

@test "list_all annotates installed and available status" {
    load_config
    local result
    result=$(list_all)
    [[ "$result" == *"ls"*"installed"* ]] || [[ "$result" =~ "ls".*"available" ]]
}

@test "main --summary prints counts" {
    run main --summary
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Commands"* ]]
    [[ "$output" == *"Available"* ]]
    [[ "$output" == *"Existing"* ]]
}

@test "main --summary --json emits valid JSON with totals" {
    local out
    out=$(main --summary --json 2>/dev/null)
    echo "$out" | jq '.commands' > /dev/null
}
