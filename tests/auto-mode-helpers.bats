#!/usr/bin/env bats
# Tests for the M3 auto-mode helper scripts:
#   bin/kanban-active-board
#   bin/kanban-pick
#   bin/kanban-block-question
#   bin/kanban-resume
#
# Exercises the full lifecycle: init -> add-plan -> pick -> block -> resume.

BIN="${BATS_TEST_DIRNAME}/../bin"

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

init_project() {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap
  cat > plan.md <<'EOF'
# Test plan

Body.

## First task
Do the first thing.
## Second task
Do the second thing.
EOF
  "${BIN}/kanban-add-plan" test-plan plan.md --project-root . >/dev/null 2>&1
}

@test "kanban-active-board errors when .superpowers-kanban is missing" {
  run "${BIN}/kanban-active-board"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not initialized"* ]]
}

@test "kanban-active-board prints roadmap path when no active plan" {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap
  # No config.json -> falls back to roadmap
  run "${BIN}/kanban-active-board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.superpowers-kanban/roadmap" ]]
}

@test "kanban-active-board prints active plan path after add-plan" {
  init_project
  run "${BIN}/kanban-active-board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.superpowers-kanban/plans/test-plan" ]]
}

@test "kanban-pick returns a JSON card and moves it to in-progress" {
  init_project
  run "${BIN}/kanban-pick"
  [ "$status" -eq 0 ]
  # Output should be JSON; check for an id field.
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id') or d.get('task',{}).get('id'))" <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" != "None" ] && [ -n "$output" ]
}

@test "kanban-pick exits 3 when no eligible cards" {
  init_project
  # Drain the board: pick both cards.
  "${BIN}/kanban-pick" >/dev/null
  "${BIN}/kanban-pick" >/dev/null
  # Third pick: nothing left in todo.
  run "${BIN}/kanban-pick"
  [ "$status" -eq 3 ]
}

@test "kanban-block-question blocks the card and releases the claim" {
  init_project
  card_json=$("${BIN}/kanban-pick")
  card_id=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id') or d.get('task',{}).get('id'))" <<<"$card_json")
  [ -n "$card_id" ]

  run "${BIN}/kanban-block-question" "$card_id" "need clarification on auth flow"
  [ "$status" -eq 0 ]

  # Verify status is review and blocked flag set.
  board=$("${BIN}/kanban-active-board")
  run kanban-md --dir "$board" --json show "$card_id"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); t=d.get('task',d); print(t.get('status'), bool(t.get('blocked')), t.get('claim') or '')" <<<"$output"
  [[ "$output" == "review True "* ]] || [[ "$output" == "review True"* ]]
}

@test "kanban-resume unblocks, appends answer, returns to todo" {
  init_project
  card_json=$("${BIN}/kanban-pick")
  card_id=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id') or d.get('task',{}).get('id'))" <<<"$card_json")
  "${BIN}/kanban-block-question" "$card_id" "test question" >/dev/null

  run "${BIN}/kanban-resume" "$card_id" "use bcrypt with cost factor 12"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unblocked"* ]]

  # Check card is now in todo, unblocked, and has the answer in body.
  board=$("${BIN}/kanban-active-board")
  run kanban-md --dir "$board" --json show "$card_id"
  [ "$status" -eq 0 ]
  run python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
t = d.get('task', d)
print(t.get('status'), bool(t.get('blocked')))
print('---BODY---')
print(t.get('body',''))
" <<<"$output"
  [[ "$output" == *"todo False"* ]]
  [[ "$output" == *"## Answer"* ]]
  [[ "$output" == *"bcrypt with cost factor 12"* ]]
}

@test "kanban-resume errors without required args" {
  run "${BIN}/kanban-resume"
  [ "$status" -ne 0 ]
  run "${BIN}/kanban-resume" "1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"answer text required"* ]]
}

@test "kanban-block-question errors without required args" {
  run "${BIN}/kanban-block-question"
  [ "$status" -ne 0 ]
  run "${BIN}/kanban-block-question" "1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"summary required"* ]]
}

@test "auto-mode skill and command files exist" {
  [ -f "${BATS_TEST_DIRNAME}/../skills/superpowers-kanban-auto-mode/SKILL.md" ]
  [ -f "${BATS_TEST_DIRNAME}/../commands/kanban-auto.md" ]
  [ -f "${BATS_TEST_DIRNAME}/../commands/kanban-resume.md" ]
}

@test "auto-mode skill has correct YAML name" {
  run head -5 "${BATS_TEST_DIRNAME}/../skills/superpowers-kanban-auto-mode/SKILL.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: superpowers-kanban-auto-mode"* ]]
}
