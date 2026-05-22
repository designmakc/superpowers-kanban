#!/usr/bin/env bats
# Tests for bin/kanban-viewer (M5).
#
# Exercises the script's --once mode for unit-style assertions on the
# rendered HTML, plus a smoke test that boots the HTTP server and hits
# a few endpoints with curl.

BIN="${BATS_TEST_DIRNAME}/../bin"
SCRIPT="${BIN}/kanban-viewer"

setup() {
  SCRATCH="$(mktemp -d)"
  PROJECT="${SCRATCH}/proj"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init -q >/dev/null 2>&1
}

teardown() {
  rm -rf "$SCRATCH"
  pkill -f "kanban-viewer.*--project-root.*${SCRATCH}" 2>/dev/null || true
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
# Plan: Sample

Body.

## Task one
do one
## Task two
do two
EOF
  "${BIN}/kanban-add-plan" sample plan.md --project-root . >/dev/null 2>&1
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "errors when project not initialized" {
  run "$SCRIPT" --once --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "--once on initialized but empty project renders index" {
  require_kanban_md
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap

  run "$SCRIPT" --once --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<!doctype html>"* ]]
  [[ "$output" == *"roadmap"* ]]
}

@test "--once with plans lists every board on the index" {
  init_with_plan
  run "$SCRIPT" --once --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"roadmap"* ]]
  [[ "$output" == *"plans/sample"* ]]
  [[ "$output" == *"2 cards"* ]]
}

@test "HTTP server serves the index and board endpoints" {
  init_with_plan

  PORT=$((RANDOM % 1000 + 9100))
  "$SCRIPT" --project-root "$PROJECT" --port "$PORT" >/dev/null 2>&1 &
  VIEWER_PID=$!
  # Wait up to 2s for the port to open.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sf "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then break; fi
    sleep 0.2
  done

  run curl -sf "http://127.0.0.1:${PORT}/"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plans/sample"* ]]

  run curl -sf "http://127.0.0.1:${PORT}/board?id=plans/sample"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Task one"* ]]
  [[ "$output" == *"Task two"* ]]
  # status columns
  [[ "$output" == *">todo<"* ]]
  [[ "$output" == *">in-progress<"* ]]

  run curl -sf "http://127.0.0.1:${PORT}/static/style.css"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--bg"* ]]

  run curl -sf "http://127.0.0.1:${PORT}/api/boards"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(len(d))" <<<"$output"
  [ "$output" -ge "2" ]

  kill "$VIEWER_PID" 2>/dev/null || true
  wait "$VIEWER_PID" 2>/dev/null || true
}

@test "kanban-view command file exists" {
  [ -f "${BATS_TEST_DIRNAME}/../commands/kanban-view.md" ]
}
