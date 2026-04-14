#!/usr/bin/env bats

load test_helper

@test "search.sh prints deferred notice and exits 0" {
    run "$SCRIPTS_DIR/search.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"deferred"* ]]
}

@test "search.sh --help prints usage" {
    run "$SCRIPTS_DIR/search.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"deferred"* ]]
}
