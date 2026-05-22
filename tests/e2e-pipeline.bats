#!/usr/bin/env bats
# End-to-end pipeline test: init → add-plan → pick → block → resume →
# pick again → done. Verifies all the helper scripts compose correctly,
# the file state on disk is consistent at each step, and the roadmap
# epic tracks plan progress when --apply runs.
#
# Skipped if kanban-md is not on PATH.

BIN="${BATS_TEST_DIRNAME}/../bin"

setup() {
  SCRATCH="$(mktemp -d)"
  PROJECT="${SCRATCH}/proj"
  mkdir -p "$PROJECT"
  cd "$PROJECT"
  git init -q >/dev/null 2>&1
  export CLAUDE_PROJECT_DIR="$PROJECT"
  export CLAUDE_PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
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

@test "full pipeline: init → add-plan → pick → block → resume → done" {
  require_kanban_md

  # === 1. Init (simulates /kanban-init) ===
  mkdir -p .superpowers-kanban
  (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap >/dev/null 2>&1)
  mv .superpowers-kanban/kanban .superpowers-kanban/roadmap
  mkdir -p .superpowers-kanban/plans
  cat >.superpowers-kanban/config.json <<'EOF'
{"version":1,"active_plan":null,"agent_name":"claude","auto_mode":{"max_iterations":20,"claim_ttl_minutes":60}}
EOF
  [ -d .superpowers-kanban/roadmap ]
  [ -d .superpowers-kanban/plans ]
  [ -f .superpowers-kanban/config.json ]

  # === 2. /kanban-add-plan ===
  cat >plan.md <<'EOF'
# Plan: Auth feature

Need email/password auth.

## Add User model

Create model.

## Add login endpoint

Implement endpoint.
EOF
  run "${BIN}/kanban-add-plan" auth plan.md --project-root .
  [ "$status" -eq 0 ]
  [ -d .superpowers-kanban/plans/auth/tasks ]
  task_count=$(ls .superpowers-kanban/plans/auth/tasks | wc -l)
  [ "$task_count" -eq 2 ]
  # active_plan should be set
  active=$(python3 -c "import json; print(json.load(open('.superpowers-kanban/config.json'))['active_plan'])")
  [ "$active" = "auth" ]

  # === 3. kanban-active-board resolves to the new plan ===
  run "${BIN}/kanban-active-board" --project-root .
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.superpowers-kanban/plans/auth" ]]

  # === 4. First pick (simulates one iteration of /kanban-auto) ===
  card_json=$("${BIN}/kanban-pick" --project-root .)
  card_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])" <<<"$card_json")
  [ -n "$card_id" ]
  # The card should now be in in-progress, claimed by claude
  board=$("${BIN}/kanban-active-board" --project-root .)
  status=$(kanban-md --dir "$board" --json show "$card_id" | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
t = d['task'] if isinstance(d.get('task'), dict) else d
print(t['status'])
")
  [ "$status" = "in-progress" ]

  # === 5. Subagent simulates: needs user input → block-question ===
  # in-progress is require_claim — pass the existing claim to edit.
  kanban-md --dir "$board" edit "$card_id" --claim claude --append-body "## Question\n\nWhich hashing scheme should we use?" >/dev/null
  run "${BIN}/kanban-block-question" "$card_id" "which hashing scheme?" --project-root .
  [ "$status" -eq 0 ]
  # Card should be in review, blocked, claim released
  show_json=$(kanban-md --dir "$board" --json show "$card_id")
  parsed=$(python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
t = d['task'] if isinstance(d.get('task'), dict) else d
print(t.get('status'), bool(t.get('blocked')), t.get('claimed_by') or '')
" <<<"$show_json")
  [[ "$parsed" == "review True"* ]]

  # === 6. /roadmap-status --apply reflects the in-progress plan ===
  run "${BIN}/roadmap-status" --project-root . --apply
  [ "$status" -eq 0 ]
  epic_status=$(kanban-md --dir "${PROJECT}/.superpowers-kanban/roadmap" --json list | python3 -c "
import json,sys
data = json.loads(sys.stdin.read())
items = data if isinstance(data, list) else data.get('tasks', [])
for t in items:
    if 'plan:auth' in (t.get('tags') or []):
        print(t['status']); break
")
  [ "$epic_status" = "in-progress" ]

  # === 7. /kanban-resume with answer ===
  run "${BIN}/kanban-resume" "$card_id" "Use bcrypt with cost 12" --project-root .
  [ "$status" -eq 0 ]
  # Card back in todo, unblocked, body has Answer section
  show_json=$(kanban-md --dir "$board" --json show "$card_id")
  st=$(python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
t = d['task'] if isinstance(d.get('task'), dict) else d
print(t['status'], bool(t.get('blocked')))
" <<<"$show_json")
  [[ "$st" == "todo False" ]]
  body=$(python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
t = d['task'] if isinstance(d.get('task'), dict) else d
print(t.get('body',''))
" <<<"$show_json")
  [[ "$body" == *"## Answer"* ]]
  [[ "$body" == *"bcrypt"* ]]

  # === 8. Pick again — should re-surface the resumed card ===
  run "${BIN}/kanban-pick" --project-root .
  [ "$status" -eq 0 ]
  picked_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])" <<<"$output")
  [ "$picked_id" = "$card_id" ]

  # === 9. Subagent simulates DONE: review → done ===
  kanban-md --dir "$board" move "$card_id" review --claim claude >/dev/null
  kanban-md --dir "$board" move "$card_id" done --claim claude >/dev/null
  st=$(kanban-md --dir "$board" --json show "$card_id" | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
t = d['task'] if isinstance(d.get('task'), dict) else d
print(t['status'])
")
  [ "$st" = "done" ]

  # === 10. Pick the second card and DONE it ===
  card2_json=$("${BIN}/kanban-pick" --project-root .)
  card2_id=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])" <<<"$card2_json")
  kanban-md --dir "$board" move "$card2_id" review --claim claude >/dev/null
  kanban-md --dir "$board" move "$card2_id" done --claim claude >/dev/null

  # === 11. Board empty → kanban-pick exits 3 ===
  set +e
  "${BIN}/kanban-pick" --project-root . >/dev/null 2>&1
  code=$?
  set -e
  [ "$code" -eq 3 ]

  # === 12. /roadmap-status --apply: epic should be done ===
  "${BIN}/roadmap-status" --project-root . --apply >/dev/null
  final_epic_status=$(kanban-md --dir "${PROJECT}/.superpowers-kanban/roadmap" --json list | python3 -c "
import json,sys
data = json.loads(sys.stdin.read())
items = data if isinstance(data, list) else data.get('tasks', [])
for t in items:
    if 'plan:auth' in (t.get('tags') or []):
        print(t['status']); break
")
  [ "$final_epic_status" = "done" ]

  # === 13. SessionStart hook surfaces the done state ===
  hook="${BATS_TEST_DIRNAME}/../hooks/session-start"
  run "$hook"
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['hookSpecificOutput']['additionalContext'])")
  [[ "$ctx" == *"done=2"* ]]
}
