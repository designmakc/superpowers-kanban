#!/usr/bin/env bats
# Tests for bin/kanban-add-plan.
#
# These exercise the parser, validation, and end-to-end board creation
# in a throwaway scratch project. Skips end-to-end tests if kanban-md is
# not on PATH.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../bin/kanban-add-plan"
  SCRATCH="$(mktemp -d)"
  PLAN_FILE="${SCRATCH}/plan.md"
  PROJECT="${SCRATCH}/proj"
  mkdir -p "${PROJECT}/.superpowers-kanban"
}

teardown() {
  rm -rf "$SCRATCH"
}

init_roadmap() {
  (cd "${PROJECT}/.superpowers-kanban" && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv "${PROJECT}/.superpowers-kanban/kanban" "${PROJECT}/.superpowers-kanban/roadmap"
}

write_sample_plan() {
  cat >"$PLAN_FILE" <<'EOF'
# Plan: Sample feature

Design summary goes here. This becomes the epic body.

It can be multiple paragraphs.

## First task

Body for task one.

```python
# code in a fenced block — H1/H2 lines inside should NOT be parsed as headings
# Task X
```

## Second task

Body for task two.

## Third task

Body for task three.
EOF
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "rejects invalid plan-id slug" {
  write_sample_plan
  init_roadmap
  run "$SCRIPT" "Bad Slug" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"kebab-case"* ]]
}

@test "rejects missing plan markdown" {
  init_roadmap
  run "$SCRIPT" "test-plan" "${SCRATCH}/does-not-exist.md" --project-root "$PROJECT" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "rejects when roadmap is missing" {
  write_sample_plan
  run "$SCRIPT" "test-plan" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Roadmap board not found"* ]]
}

@test "dry-run parses tasks without writing anything" {
  write_sample_plan
  init_roadmap
  run "$SCRIPT" "test-plan" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tasks parsed: 3"* ]]
  [[ "$output" == *"First task"* ]]
  [[ "$output" == *"Second task"* ]]
  [[ "$output" == *"Third task"* ]]
  [ ! -d "${PROJECT}/.superpowers-kanban/plans/test-plan" ]
}

@test "dry-run treats fenced code block contents as body, not headings" {
  write_sample_plan
  init_roadmap
  run "$SCRIPT" "test-plan" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -eq 0 ]
  # 3 H2 task headings, and "# Task X" inside the fenced code block must not count
  [[ "$output" == *"Tasks parsed: 3"* ]]
}

@test "rejects plan with no H1" {
  init_roadmap
  cat >"$PLAN_FILE" <<'EOF'
## Just a task with no H1

Body
EOF
  run "$SCRIPT" "test-plan" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"H1"* ]]
}

@test "rejects plan with no H2 tasks" {
  init_roadmap
  cat >"$PLAN_FILE" <<'EOF'
# Just an H1, no tasks

Some prose only.
EOF
  run "$SCRIPT" "test-plan" "$PLAN_FILE" --project-root "$PROJECT" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"H2"* ]]
}

@test "end-to-end: creates board, cards, epic, and sets active_plan" {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi

  write_sample_plan
  init_roadmap

  run "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT"
  [ "$status" -eq 0 ]

  # Plan board exists with three tasks
  [ -d "${PROJECT}/.superpowers-kanban/plans/sample/tasks" ]
  count=$(ls "${PROJECT}/.superpowers-kanban/plans/sample/tasks/" | wc -l)
  [ "$count" -eq 3 ]

  # Epic on roadmap
  ls "${PROJECT}/.superpowers-kanban/roadmap/tasks/" | grep -q "plan-sample-feature\|plan-"

  # Config updated
  run python3 -c "import json; print(json.load(open('${PROJECT}/.superpowers-kanban/config.json'))['active_plan'])"
  [ "$status" -eq 0 ]
  [ "$output" = "sample" ]
}

@test "end-to-end: refuses if plan board already exists without --force" {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi

  write_sample_plan
  init_roadmap
  "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT" >/dev/null 2>&1

  run "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "end-to-end: --force appends to existing plan board" {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi

  write_sample_plan
  init_roadmap
  "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT" >/dev/null 2>&1

  run "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT" --force
  [ "$status" -eq 0 ]
  count=$(ls "${PROJECT}/.superpowers-kanban/plans/sample/tasks/" | wc -l)
  [ "$count" -eq 6 ]   # 3 from first run + 3 from --force run
}

@test "end-to-end: epic title does not double-prefix 'Plan:'" {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi

  init_roadmap
  cat >"$PLAN_FILE" <<'EOF'
# Plan: Already prefixed

Body.

## Only task

Body.
EOF
  "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT" >/dev/null 2>&1
  # Epic title should be "Plan: Already prefixed" (one prefix), not "Plan: Plan: ..."
  # YAML may quote the value because it contains a colon, so match both forms.
  run grep -h '^title:' "${PROJECT}/.superpowers-kanban/roadmap/tasks/"*.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan: Already prefixed"* ]]
  [[ "$output" != *"Plan: Plan:"* ]]
}

@test "end-to-end: epic title adds 'Plan:' prefix when H1 lacks it" {
  if ! command -v kanban-md >/dev/null 2>&1; then
    skip "kanban-md not on PATH"
  fi

  init_roadmap
  cat >"$PLAN_FILE" <<'EOF'
# Auth feature

Body.

## Only task

Body.
EOF
  "$SCRIPT" "sample" "$PLAN_FILE" --project-root "$PROJECT" >/dev/null 2>&1
  run grep -h '^title:' "${PROJECT}/.superpowers-kanban/roadmap/tasks/"*.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"Plan: Auth feature"* ]]
}
