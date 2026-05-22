---
description: Start the kanban auto-loop. The orchestrator picks the next todo card from the active plan board, dispatches a fresh subagent to execute it, parses the result, and repeats — stopping when a card needs a human answer (KANBAN_QUESTION), when the board is empty, when STOP file appears, or after max_iterations.
---

# /kanban-auto

## Setup for the agent (orchestrator)

1. **Invoke `superpowers-kanban` skill** for the model.
2. **Invoke `superpowers-kanban-auto-mode` skill** for the loop semantics — that skill is the source of truth for the procedure below; this command is a thin entry point.

## Pre-flight (run these in this order, fail fast)

```bash
# Confirm active plan
ACTIVE=$(python3 -c "import json,sys; print(json.load(open('.superpowers-kanban/config.json')).get('active_plan') or '')")
[ -n "$ACTIVE" ] || { echo "No active_plan set. Run /kanban-add-plan <id> <plan.md> first."; exit 1; }

# Resolve board dir
BOARD=$("${CLAUDE_PLUGIN_ROOT}/bin/kanban-active-board")

# STOP file check
[ ! -f .superpowers-kanban/STOP ] || { echo "STOP file present. Delete .superpowers-kanban/STOP to resume."; exit 1; }

# Lock file check — refuse if a fresh lock exists; otherwise claim it
LOCK=.superpowers-kanban/auto-lock
TTL_MIN=$(python3 -c "import json; print(json.load(open('.superpowers-kanban/config.json')).get('auto_mode',{}).get('claim_ttl_minutes',60))")
if [ -f "$LOCK" ]; then
  age_sec=$(( $(date +%s) - $(stat -c %Y "$LOCK") ))
  if [ "$age_sec" -lt $(( TTL_MIN * 60 * 2 )) ]; then
    echo "Another /kanban-auto loop appears to be running (lock: $LOCK, age ${age_sec}s). Refuse."
    exit 1
  fi
  echo "Stale lock found; reclaiming."
fi
echo "$(date -u +%FT%TZ) claude" > "$LOCK"

MAX_ITER=$(python3 -c "import json; print(json.load(open('.superpowers-kanban/config.json')).get('auto_mode',{}).get('max_iterations',20))")
echo "Active plan: $ACTIVE | Board: $BOARD | Max iterations: $MAX_ITER"
```

## The loop

Repeat up to `$MAX_ITER` times. At the start of each iteration:

1. **Check STOP file**:
   ```bash
   [ ! -f .superpowers-kanban/STOP ] || { echo "STOP file detected. Exiting."; rm -f "$LOCK"; exit 0; }
   ```

2. **Pick next card**:
   ```bash
   if ! card_json=$("${CLAUDE_PLUGIN_ROOT}/bin/kanban-pick" 2>&1); then
     ec=$?
     if [ "$ec" -eq 3 ]; then
       echo "Board empty. Active plan complete."
       rm -f "$LOCK"
       exit 0
     fi
     echo "kanban-pick failed: $card_json"
     rm -f "$LOCK"
     exit 1
   fi
   ```

3. **Read card** from the JSON. Extract `id`, `title`, `body`, and the file path.

4. **Dispatch a subagent** using the `Agent` tool with the prompt template from `superpowers-kanban-auto-mode` skill. Use `subagent_type: "general-purpose"`. Pass the card id, title, body, board dir, and project root.

5. **Parse the subagent's result**. Take the last non-empty line:

   | Marker | Action |
   |---|---|
   | `KANBAN_DONE` | `kanban-md --dir $BOARD move <id> review`, then run `superpowers:requesting-code-review` on the card's diff. On pass: `kanban-md --dir $BOARD move <id> done`. On fail: `kanban-md --dir $BOARD edit <id> --append-body "## Review feedback\n\n<feedback>" && kanban-md --dir $BOARD move <id> todo --claim "" --release` (release claim and return for another try) |
   | `KANBAN_QUESTION: <summary>` | `"${CLAUDE_PLUGIN_ROOT}/bin/kanban-block-question" <id> "<summary>"` then STOP the loop: print the card id, summary, and `Answer with: /kanban-resume <id> "<your answer>"` |
   | `KANBAN_ERROR: <summary>` | `kanban-md --dir $BOARD edit <id> --release --append-body "## Error\n\n<summary>" && kanban-md --dir $BOARD move <id> todo`. Increment a consecutive-errors counter. If it reaches 3 → stop. |
   | (no marker found) | Treat as ERROR with summary `"no marker; ended with: <last line>"` |

6. **Continue** to next iteration (back to step 1).

## End-of-loop cleanup

Always remove the lock file before exiting:

```bash
rm -f "$LOCK"
```

## Output to the user

Print a one-line status after every iteration so the user can follow:

```text
[iter N/MAX] card #ID "<title>" → DONE | QUESTION | ERROR
```

At the end, print a summary: cards picked, cards done, cards blocked, cards errored, plus the next suggested action.

## DO NOT

- Do NOT answer questions yourself. ALL questions go through `KANBAN_QUESTION` → `/kanban-resume`.
- Do NOT change a card's status by editing its file. Always use `kanban-md`.
- Do NOT bump `max_iterations` mid-loop.
- Do NOT dispatch more than one subagent at a time.
- Do NOT remove the lock file from anywhere except the orchestrator's exit path.
