#!/usr/bin/env bats
# Tests for bin/roadmap-status (M4).

BIN="${BATS_TEST_DIRNAME}/../bin"
SCRIPT="${BIN}/roadmap-status"

setup() {
  SCRATCH="$(mktemp -d)"
  PROJECT="${SCRATCH}/proj"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init -q >/dev/null 2>&1
}

teardown() {
  rm -rf "$SCRATCH"
}

require_kanban_md() {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi
}

init_with_plans() {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap

  cat >plan-a.md <<'EOF'
# Plan: Feature A

Body A.

## Task A1
A1
## Task A2
A2
EOF

  cat >plan-b.md <<'EOF'
# Plan: Feature B

Body B.

## Task B1
B1
EOF

  "${BIN}/kanban-add-plan" feature-a plan-a.md --project-root . >/dev/null 2>&1
  "${BIN}/kanban-add-plan" feature-b plan-b.md --project-root . >/dev/null 2>&1
}

@test "errors when not initialized" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Roadmap board not found"* ]]
}

@test "reports zero plans when only roadmap exists" {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No plans yet"* ]]
}

@test "reports all plans with card counts" {
  init_with_plans
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-a"* ]]
  [[ "$output" == *"feature-b"* ]]
  [[ "$output" == *"2 plans, 3 cards total"* ]]
  [[ "$output" == *"3 todo"* ]]
}

@test "JSON output has plans and overall keys" {
  init_with_plans
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['overall']['plans'], d['overall']['cards_total'])" <<<"$output"
  [ "$output" = "2 3" ]
}

@test "without --apply, drifted epic is flagged but not moved" {
  init_with_plans

  # Move one card on plan-a to in-progress directly (claiming it).
  board="${PROJECT}/.superpowers-kanban/plans/feature-a"
  kanban-md --dir "$board" pick --claim claude --status todo --move in-progress >/dev/null 2>&1

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"out of sync"* ]]
  # Epic should still be at "todo" (not moved without --apply).
  status=$(kanban-md --dir "${PROJECT}/.superpowers-kanban/roadmap" --json list | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
items = data if isinstance(data, list) else data.get('tasks', [])
for t in items:
    if 'plan:feature-a' in (t.get('tags') or []):
        print(t['status']); break
")
  [ "$status" = "todo" ]
}

@test "--apply moves drifted epic to in-progress" {
  init_with_plans
  board="${PROJECT}/.superpowers-kanban/plans/feature-a"
  kanban-md --dir "$board" pick --claim claude --status todo --move in-progress >/dev/null 2>&1

  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applied epic moves"* ]] || [[ "$output" == *"-> in-progress"* ]]

  new_status=$(kanban-md --dir "${PROJECT}/.superpowers-kanban/roadmap" --json list | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
items = data if isinstance(data, list) else data.get('tasks', [])
for t in items:
    if 'plan:feature-a' in (t.get('tags') or []):
        print(t['status']); break
")
  [ "$new_status" = "in-progress" ]
}

@test "--apply is idempotent (second run reports no moves)" {
  init_with_plans
  board="${PROJECT}/.superpowers-kanban/plans/feature-a"
  kanban-md --dir "$board" pick --claim claude --status todo --move in-progress >/dev/null 2>&1
  "$SCRIPT" --apply >/dev/null 2>&1

  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"Applied epic moves"* ]]
}

@test "all cards done -> epic moves to done with --apply" {
  init_with_plans
  board="${PROJECT}/.superpowers-kanban/plans/feature-b"
  # Drive single card all the way through. Need agent name from config.
  kanban-md --dir "$board" pick --claim claude --status todo --move in-progress >/dev/null 2>&1
  kanban-md --dir "$board" move 1 review --claim claude >/dev/null 2>&1
  kanban-md --dir "$board" move 1 done --claim claude >/dev/null 2>&1

  run "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  new_status=$(kanban-md --dir "${PROJECT}/.superpowers-kanban/roadmap" --json list | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
items = data if isinstance(data, list) else data.get('tasks', [])
for t in items:
    if 'plan:feature-b' in (t.get('tags') or []):
        print(t['status']); break
")
  [ "$new_status" = "done" ]
}

@test "roadmap-status command file exists" {
  [ -f "${BATS_TEST_DIRNAME}/../commands/roadmap-status.md" ]
}
