#!/usr/bin/env bats

load test_helper

setup() {
    setup_test_env
    source "$SCRIPTS_DIR/sync.sh"
    load_config

    # Seed available data + symlinks
    mkdir -p "$TEST_TEMP_ROOT/data"
    mkdir -p "$TEST_TEMP_ROOT/src/builtin/test-builtin"
    mkdir -p "$TEST_TEMP_ROOT/src/generated/test-generated"
    echo '#compdef foo gen' > "$TEST_TEMP_ROOT/src/generated/test-generated/_foo"
    echo '#compdef foo bin' > "$TEST_TEMP_ROOT/src/builtin/test-builtin/_foo"
    echo '#compdef bar bin' > "$TEST_TEMP_ROOT/src/builtin/test-builtin/_bar"

    ln -sf "$TEST_TEMP_ROOT/src/generated/test-generated/_foo" "$TEST_TEMP_ROOT/available/_foo.0"
    ln -sf "$TEST_TEMP_ROOT/src/builtin/test-builtin/_foo"     "$TEST_TEMP_ROOT/available/_foo.1"
    ln -sf "$TEST_TEMP_ROOT/src/builtin/test-builtin/_bar"     "$TEST_TEMP_ROOT/available/_bar.1"

    cat > "$TEST_TEMP_ROOT/data/comps-available.json" << EOF
{
  "foo": [
    {"path":"$TEST_TEMP_ROOT/available/_foo.0","lines":1,"source":"test-generated","priority":0},
    {"path":"$TEST_TEMP_ROOT/available/_foo.1","lines":1,"source":"test-builtin","priority":1}
  ],
  "bar": [
    {"path":"$TEST_TEMP_ROOT/available/_bar.1","lines":1,"source":"test-builtin","priority":1}
  ]
}
EOF
}

teardown() {
    teardown_test_env
}

@test "pick_winner picks lowest priority by default" {
    local entries winner
    entries=$(jq -c '.foo' "$TEST_TEMP_ROOT/data/comps-available.json")
    winner=$(pick_winner "foo" "$entries" "{}")
    [[ $(echo "$winner" | jq -r '.source') == "test-generated" ]]
}

@test "pick_winner honors override map" {
    local entries winner
    entries=$(jq -c '.foo' "$TEST_TEMP_ROOT/data/comps-available.json")
    winner=$(pick_winner "foo" "$entries" '{"foo":"test-builtin"}')
    [[ $(echo "$winner" | jq -r '.source') == "test-builtin" ]]
}

@test "pick_winner falls back to priority if override source not present" {
    local entries winner
    entries=$(jq -c '.foo' "$TEST_TEMP_ROOT/data/comps-available.json")
    winner=$(pick_winner "foo" "$entries" '{"foo":"no-such-source"}')
    [[ $(echo "$winner" | jq -r '.source') == "test-generated" ]]
}

@test "build_plan emits install lines for missing actives" {
    local plan
    plan=$(build_plan)
    [[ "$plan" == *$'install\tfoo\t'* ]]
    [[ "$plan" == *$'install\tbar\t'* ]]
}

@test "build_plan emits no-op when active matches winner" {
    ln -sf "$TEST_TEMP_ROOT/src/generated/test-generated/_foo" "$TEST_TEMP_ROOT/active/_foo"
    ln -sf "$TEST_TEMP_ROOT/src/builtin/test-builtin/_bar"     "$TEST_TEMP_ROOT/active/_bar"
    local plan
    plan=$(build_plan)
    [[ -z "$plan" ]]
}

@test "build_plan emits update when active points to wrong source" {
    ln -sf "$TEST_TEMP_ROOT/src/builtin/test-builtin/_foo" "$TEST_TEMP_ROOT/active/_foo"
    local plan
    plan=$(build_plan)
    [[ "$plan" == *$'update\tfoo\t'* ]]
}

@test "build_plan emits remove for orphaned actives" {
    echo 'orphan' > "$TEST_TEMP_ROOT/active/_orphan"
    local plan
    plan=$(build_plan)
    [[ "$plan" == *$'remove\torphan\t-'* ]]
}

@test "apply installs links into active dir" {
    local plan
    plan=$(build_plan)
    apply_plan "$plan"
    [[ -L "$TEST_TEMP_ROOT/active/_foo" ]]
    [[ -L "$TEST_TEMP_ROOT/active/_bar" ]]
    # _foo should resolve to test-generated (priority 0)
    [[ "$(readlink -f "$TEST_TEMP_ROOT/active/_foo")" == "$TEST_TEMP_ROOT/src/generated/test-generated/_foo" ]]
}

@test "apply removes orphans flagged by build_plan" {
    echo 'orphan' > "$TEST_TEMP_ROOT/active/_orphan"
    local plan
    plan=$(build_plan)
    apply_plan "$plan"
    [[ ! -e "$TEST_TEMP_ROOT/active/_orphan" ]]
}

@test "prune_orphans removes commands not in available data" {
    ln -sf "$TEST_TEMP_ROOT/src/builtin/test-builtin/_bar" "$TEST_TEMP_ROOT/active/_stale"
    prune_orphans
    [[ ! -e "$TEST_TEMP_ROOT/active/_stale" ]]
}

@test "main --dry-run does not modify active dir" {
    main --dry-run > /dev/null 2>&1
    [[ ! -e "$TEST_TEMP_ROOT/active/_foo" ]]
}

@test "main --apply installs winners" {
    main --apply > /dev/null 2>&1
    [[ -L "$TEST_TEMP_ROOT/active/_foo" ]]
    [[ -L "$TEST_TEMP_ROOT/active/_bar" ]]
}
