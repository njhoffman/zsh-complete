#!/usr/bin/env bats

load test_helper

CLI="$SCRIPTS_DIR/zsh-complete"

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "no args prints usage" {
    run "$CLI"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "help subcommand prints usage" {
    run "$CLI" help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Subcommands"* ]]
}

@test "unknown subcommand exits non-zero" {
    run "$CLI" bogus
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown subcommand"* ]]
}

@test "fetch --help is forwarded" {
    run "$CLI" fetch --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--source"* ]]
}

@test "compile --help is forwarded" {
    run "$CLI" compile --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--limit"* ]]
}

@test "list --help is forwarded" {
    run "$CLI" list --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--to-install"* ]]
}

@test "sync --help is forwarded" {
    run "$CLI" sync --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--apply"* ]]
}

@test "generic --help is forwarded" {
    run "$CLI" generic --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--stdout"* ]]
}

@test "check --help is forwarded" {
    run "$CLI" check --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--file"* ]]
}

@test "search subcommand emits deferred notice" {
    run "$CLI" search
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"deferred"* ]]
}

@test "doctor reports tool presence" {
    run "$CLI" doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"jq"* ]]
    [[ "$output" == *"valid"* ]]
}
