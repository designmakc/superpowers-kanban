---
description: Initialize superpowers-kanban in the current project. Installs the kanban-md binary if missing, creates .superpowers-kanban/ with an empty roadmap board, and registers the plugin's skills with the agent.
---

# /kanban-init

Set up superpowers-kanban for this project. Run this once per project; it is idempotent — re-running it does NOT wipe existing boards.

## Steps for the agent

1. **Invoke `superpowers-kanban` skill** (this plugin) before doing anything else.

2. **Install the binary if missing.** Run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/install-kanban-md"
   ```

   The script no-ops if `kanban-md` is already on PATH. After it runs, verify:

   ```bash
   kanban-md --version
   ```

   If the binary is not on PATH, tell the user how to add `~/.local/bin` (or `$(go env GOPATH)/bin`) to their PATH and stop.

3. **Install kanban-md's own skills for the Claude Code agent.** These teach the agent the `kanban-md` CLI surface and complement this plugin's workflow skill:

   ```bash
   kanban-md skill install --agent claude --skill kanban-md --skill kanban-based-development
   ```

4. **Create the project structure.** `kanban-md init` always creates a `kanban/` subdirectory in the cwd and interactively asks whether to add it to .gitignore. We want it tracked in git, so we answer "n" and rename. Skip if `.superpowers-kanban/roadmap/` already exists:

   ```bash
   mkdir -p .superpowers-kanban
   if [ ! -d .superpowers-kanban/roadmap ]; then
     (cd .superpowers-kanban && printf 'n\n' | kanban-md init --name roadmap)
     mv .superpowers-kanban/kanban .superpowers-kanban/roadmap
   fi
   mkdir -p .superpowers-kanban/plans
   ```

5. **Write `.superpowers-kanban/config.json`** if missing, with these defaults:

   ```json
   {
     "version": 1,
     "active_plan": null,
     "agent_name": "claude",
     "auto_mode": {
       "max_iterations": 20,
       "claim_ttl_minutes": 60
     }
   }
   ```

6. **Add `.superpowers-kanban/` to git tracking.** Do NOT add it to `.gitignore`. Cards are durable artifacts and belong in the repo. If `.gitignore` already excludes it, prompt the user before changing.

7. **Confirm to the user** with a short report:
   - kanban-md version
   - path to the roadmap board
   - next step: `/kanban-add-plan <plan-id>` (after `superpowers:writing-plans` produces a plan)

## Failure modes

- `kanban-md` install failed → print the install script's stderr verbatim, suggest `go install` or manual download, do NOT continue
- `kanban-md init` returned non-zero → surface its output, do NOT continue
- Project is not a git repo → still proceed, but warn the user that cards won't be versioned

## DO NOT

- Do not create any plan boards here. `/kanban-init` only sets up the project shell. Plan boards are created by `/kanban-add-plan` after a plan exists.
- Do not start the auto-loop here. That's `/kanban-auto`.
- Do not modify the upstream Superpowers plugin or its skills.
