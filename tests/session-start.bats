#!/usr/bin/env bats
# Tests for the SessionStart hook (M6).

HOOK="${BATS_TEST_DIRNAME}/../hooks/session-start"
BIN="${BATS_TEST_DIRNAME}/../bin"

setup() {
  SCRATCH="$(mktemp -d)"
  PROJECT="${SCRATCH}/proj"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init -q >/dev/null 2>&1
  # Pretend Claude Code is the harness so the right envelope is emitted.
  export CLAUDE_PROJECT_DIR="$PROJECT"
  export CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
  unset CURSOR_PLUGIN_ROOT COPILOT_CLI
}

teardown() {
  rm -rf "$SCRATCH"
  unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
}

require_kanban_md() {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi
}

init_with_plan() {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap
  cat >plan.md <<'EOF'
# Plan: Test

Body.

## Task one
do one
## Task two
do two
EOF
  "${BIN}/kanban-add-plan" sample plan.md --project-root . >/dev/null 2>&1
}

@test "hook exists and is executable" {
  [ -x "$HOOK" ]
}

@test "emits valid JSON envelope when .superpowers-kanban is absent" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  # Output should be parseable JSON.
  run python3 -c "import json,sys; json.loads(sys.stdin.read())" <<<"$output"
  [ "$status" -eq 0 ]
}

@test "emits empty additionalContext when no .superpowers-kanban" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['hookSpecificOutput']['additionalContext'])" <<<"$output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits status summary when project is initialized" {
  init_with_plan
  run "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['hookSpecificOutput']['additionalContext'])")
  [[ "$ctx" == *"superpowers-kanban: project status"* ]]
  [[ "$ctx" == *"sample"* ]]
  [[ "$ctx" == *"todo=2"* ]]
}

@test "warns about blocked cards" {
  init_with_plan
  board="${PROJECT}/.superpowers-kanban/plans/sample"
  kanban-md --dir "$board" pick --claim claude --status todo --move in-progress >/dev/null 2>&1
  "${BIN}/kanban-block-question" 1 "stuck on this" >/dev/null 2>&1

  run "$HOOK"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['hookSpecificOutput']['additionalContext'])")
  [[ "$ctx" == *"BLOCKED"* ]]
  [[ "$ctx" == *"/kanban-resume"* ]]
}

@test "Cursor envelope shape when CURSOR_PLUGIN_ROOT is set" {
  init_with_plan
  CURSOR_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" run "$HOOK"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(list(d.keys())[0])" <<<"$output"
  [ "$output" = "additional_context" ]
}
