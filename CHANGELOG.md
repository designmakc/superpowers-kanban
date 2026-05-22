# Changelog

All notable changes to **superpowers-kanban** will be documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — initial alpha

First public release. Companion plugin for [Superpowers](https://github.com/obra/superpowers); installs side-by-side with upstream and adds an agent-driven kanban workflow on top of [`kanban-md`](https://github.com/antopolskiy/kanban-md).

### Added

- **Plugin scaffold**: `.claude-plugin/{plugin,marketplace}.json`, MIT license.
- **`bin/install-kanban-md`** — bootstraps the kanban-md binary (PATH check → `go install` → goreleaser tarball download for the current OS/arch). Honors `KANBAN_MD_VERSION` and `KANBAN_MD_BIN_DIR`.
- **`/kanban-init`** — sets up `.superpowers-kanban/` with an empty roadmap board and a `plans/` container; installs kanban-md's own agent skills for Claude Code.
- **`/kanban-add-plan <id> <plan.md>`** — converts a plan from `superpowers:writing-plans` into a kanban-md board (one card per H2 task), adds an epic to the roadmap, and sets `active_plan` in config. Idempotent; supports `--dry-run` and `--force`.
- **`/kanban-auto`** — orchestrator loop. Picks the next `todo` card, dispatches a fresh subagent via `superpowers:subagent-driven-development`, parses the marker (`KANBAN_DONE` / `KANBAN_QUESTION` / `KANBAN_ERROR`), advances or blocks the card accordingly, and repeats until the board is empty, a question pauses the loop, the STOP file appears, or `max_iterations` is reached.
- **`/kanban-resume <id> "<answer>"`** — claims a blocked card, appends the answer under a timestamped `## Answer` heading, unblocks it, sends it back to `todo`, and releases the claim so the next pick can grab it.
- **`/roadmap-status [--apply] [--json]`** — aggregates card counts across every plan board, finds the matching roadmap epic by `plan:<id>` tag, and (with `--apply`) syncs each epic's status to reflect plan progress.
- **`/kanban-view [--port N]`** — read-only web viewer (Python stdlib only). Six-column kanban view per board, card detail pages, JSON API at `/api/boards` and `/api/board`. Binds to `127.0.0.1` only.
- **Skills** — `superpowers-kanban` (the model + question protocol) and `superpowers-kanban-auto-mode` (loop semantics, subagent prompt template, safety stops).
- **SessionStart hook** — when a session starts in a project that has `.superpowers-kanban/`, injects a compact status summary (active plan, card counts per status, BLOCKED card warning, slash-command reminder) into the agent's context.
- **Tests** — 58 bats tests covering install script, plugin metadata, plan parsing, auto-mode helpers, roadmap aggregation, viewer endpoints, session-start hook, and a full end-to-end pipeline.

### Not yet supported

- Codex, Cursor, Gemini, OpenCode, Copilot harnesses — the plugin is Claude Code first.
- Multiple concurrent active plans — single `active_plan` slot in config.
- The orchestrator loop in `/kanban-auto.md` documents the procedure but the actual iteration is driven by the parent agent at invocation time; end-to-end orchestration will be exercised in real sessions and refined.
