---
description: Show aggregated progress across all plan boards. Counts cards by status per plan, finds the matching roadmap epic via the plan:<id> tag, and reports total/done/in-progress/blocked. Pass --apply to also move each epic's status on the roadmap to reflect its plan's actual state.
---

# /roadmap-status

Usage:

```text
/roadmap-status                # report only
/roadmap-status --apply        # report and update epic statuses
/roadmap-status --json         # machine-readable output
```

## Steps for the agent

1. **Invoke `superpowers-kanban` skill** for the model.

2. **Verify pre-conditions:**
   - `.superpowers-kanban/roadmap/` exists. If not, tell the user to run `/kanban-init`.
   - `kanban-md` is on PATH.

3. **Generate the report:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/roadmap-status"
   ```

   If the user asked for `--apply`, pass that flag too. The script:
   - Walks every `.superpowers-kanban/plans/<plan-id>/` board.
   - For each, counts cards by status (backlog/todo/in-progress/review/done/archived) and counts the blocked flag.
   - Finds the matching roadmap epic by the tag `plan:<plan-id>` (added by `/kanban-add-plan`).
   - Computes target epic status: all-done → `done`, any active/blocked → `in-progress`, otherwise → `todo`.
   - Without `--apply`: only prints the report and flags drifted epics.
   - With `--apply`: runs `kanban-md move` for each drifted epic.

4. **Surface the output verbatim.** The script's text formatting is the source of truth — do not paraphrase the numbers.

## When to use `--apply`

Use it routinely after a `/kanban-auto` run to keep the roadmap in sync. Safe to run repeatedly — moves are idempotent.

## DO NOT

- Do NOT compute progress percentages yourself; the script does it.
- Do NOT change an epic's status by editing its file directly.
- Do NOT touch plans that don't have a matching epic card. The script will surface them (`epic_status: -`) so the user can decide whether to create the epic or rename the plan.
