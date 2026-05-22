---
description: Convert a Superpowers plan markdown (produced by superpowers:writing-plans) into a kanban-md board. Adds an epic card to the roadmap that links to the new plan board, sets active_plan in config, and turns each H2 task heading in the plan into a card with status=todo.
---

# /kanban-add-plan

Usage:

```text
/kanban-add-plan <plan-id> <path-to-plan.md>
```

`<plan-id>` is a kebab-case slug (lowercase letters, digits, hyphens) used as the directory name. `<path-to-plan.md>` is the plan file produced by `superpowers:writing-plans`.

## Steps for the agent

1. **Invoke `superpowers-kanban` skill** before doing anything else.

2. **Verify prerequisites:**
   - `.superpowers-kanban/roadmap/` exists. If not, tell the user to run `/kanban-init` first and STOP.
   - `kanban-md` is on PATH. If not, tell the user to run `/kanban-init` first.
   - The plan markdown file exists and contains at least one `## ` heading. If the structure looks wrong (no H1, no H2 sections), surface the file and ask the user to fix it before continuing.

3. **Dry-run first.** Show the user what will be created without modifying anything:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/kanban-add-plan" <plan-id> <path-to-plan.md> --dry-run
   ```

   Print the parsed epic title and the list of tasks. If the count or titles look wrong (e.g. one giant task instead of bite-sized ones), STOP and ask the user whether to continue. Common cause: the plan markdown wasn't run through `superpowers:writing-plans` and just has freeform structure.

4. **Apply.** Only after the dry-run was clean (or the user confirmed):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/kanban-add-plan" <plan-id> <path-to-plan.md>
   ```

   The script will:
   - Create the plan board at `.superpowers-kanban/plans/<plan-id>/` (errors out if it already exists; pass `--force` to append instead)
   - Add one card per H2 heading in the plan, status `todo`, tagged `plan:<plan-id>`
   - Add an epic card to the roadmap titled `Plan: <H1 title>`, status `todo`, tagged `type:epic,plan:<plan-id>`, body links to the plan board
   - Update `.superpowers-kanban/config.json` to set `active_plan: <plan-id>`

5. **Show the result** to the user:

   ```bash
   kanban-md --dir .superpowers-kanban/plans/<plan-id> board
   ```

   And remind them the next step is `/kanban-auto` (M3).

## Expected plan markdown format

```markdown
# Plan: Add user authentication

<optional design summary — becomes the epic body on the roadmap>

## Add User model with email + password fields

<task 1 body: files to touch, code, verification>

## Add /login endpoint

<task 2 body>

## Add session cookie middleware

<task 3 body>
```

Rules:
- One H1 at the top — becomes the epic title.
- Each H2 becomes one card. Pick task titles that are imperative and self-contained.
- Body between the H1 and the first H2 becomes the epic body on the roadmap.
- Headings inside fenced code blocks are NOT treated as task boundaries.

## Failure modes

- Plan board already exists → script exits with an error. Ask the user whether to add cards on top with `--force` or pick a different `plan-id`.
- Plan has zero H2 sections → script refuses. Ask the user to re-run `superpowers:writing-plans` to produce a properly structured plan.
- `kanban-md create` failed for any card → script aborts mid-flight; partial state is on disk. Tell the user; do NOT silently retry. The plan board is salvageable by deleting it and re-running.

## DO NOT

- Do not start the auto-loop here. That's `/kanban-auto`.
- Do not edit the plan markdown to "fix" it before running the script. If the structure is wrong, the user fixes their plan; we do not invent task boundaries.
- Do not pass `--force` automatically. Forcing must be an explicit user decision.
