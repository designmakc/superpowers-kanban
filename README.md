# superpowers-kanban

A **companion plugin** for [Superpowers](https://github.com/obra/superpowers) that adds an agent-driven kanban workflow on top of [`kanban-md`](https://github.com/antopolskiy/kanban-md).

Plans get broken into bite-sized cards. Agents pick up cards autonomously, execute them via Superpowers' `subagent-driven-development` workflow, and pause whenever they need a human answer. After you answer, work resumes until the board is empty.

> **Status:** alpha — M1 (foundation) only. M2-M6 in progress on branch `claude/superpower-orba-kanban-ALTky`. See [roadmap](#roadmap) below.

## What this is and is not

- ✅ A **companion plugin** that installs alongside upstream Superpowers
- ✅ **Claude Code first**; other harnesses can be added later
- ✅ Stores card data as **markdown files in your project's git repo**
- ❌ Not a fork of Superpowers. Install both side-by-side.
- ❌ Not a replacement for `kanban-md`. This plugin **wraps** it; you still need the binary.

## Prerequisites

1. [Superpowers](https://github.com/obra/superpowers) installed in your harness.
2. [`kanban-md`](https://github.com/antopolskiy/kanban-md) binary on PATH. `/kanban-init` will install it for you if missing.

## Installation (Claude Code)

```text
/plugin marketplace add designmakc/superpowers-kanban
/plugin install superpowers-kanban@superpowers-kanban
```

Then in any project:

```text
cd my-project && claude
> /kanban-init
```

`/kanban-init` is idempotent — safe to run on existing projects.

## Workflow

1. Brainstorm an idea — Superpowers' `brainstorming` skill auto-triggers.
2. Produce a plan — Superpowers' `writing-plans` skill produces a detailed plan.
3. **`/kanban-add-plan <plan-id>`** — turn that plan into a board. Each plan task becomes a card.
4. **`/kanban-auto`** — start the auto-loop. Agents pick cards one by one and work through them.
5. When an agent needs your input, the card is moved to **blocked** and the loop stops. The agent's question is in the card body.
6. **`/kanban-resume <card-id> "your answer"`** — unblock and resume.

## Commands

| Command | Status | Purpose |
|---|---|---|
| `/kanban-init` | M1 ✅ | Initialize the plugin in a project |
| `/kanban-add-plan` | M2 ⏳ | Convert a Superpowers plan into a board |
| `/kanban-auto` | M3 ⏳ | Run the auto-loop |
| `/kanban-resume` | M3 ⏳ | Answer a blocked card and resume |
| `/roadmap-status` | M4 ⏳ | Show aggregated progress across all plans |
| `/kanban-view` | M5 ⏳ | Open a read-only web viewer of all boards |

## Data layout (in your project)

```
<your-project>/
  .superpowers-kanban/
    config.json
    roadmap/
      config.yml
      tasks/<epic>.md        # frontmatter: plan_dir
    plans/<plan-id>/
      config.yml
      tasks/<card>.md
```

These files are normal text — commit them, review them in PRs, diff them like any code.

## Card statuses

`backlog → todo → in-progress → review → done → archived`, plus an orthogonal `blocked` flag for cards awaiting a human answer. These come from kanban-md; do not invent new statuses.

## Question protocol

When a subagent needs a human answer:

1. It writes the question into the card body under `## Question`.
2. It ends its turn with `KANBAN_QUESTION: <summary>`.
3. The auto-loop runs `kanban-md handoff <card-id> --blocked` and stops.
4. You answer via `/kanban-resume <card-id> "..."`.
5. The next subagent for that card sees your answer in the card body.

## Roadmap

- [x] **M1** — Foundation: plugin/marketplace metadata, `install-kanban-md`, base skill, `/kanban-init`
- [ ] **M2** — `/kanban-add-plan` integrates with `superpowers:writing-plans`
- [ ] **M3** — `/kanban-auto` + `/kanban-resume` + auto-mode skill + question protocol
- [ ] **M4** — Roadmap aggregation + `/roadmap-status`
- [ ] **M5** — Read-only web viewer + `/kanban-view`
- [ ] **M6** — Session-start hook, end-to-end tests, polish
- [ ] Later — Mirror to Codex / Cursor / Gemini / Copilot harnesses

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

- [Jesse Vincent](https://github.com/obra) and the Prime Radiant team for [Superpowers](https://github.com/obra/superpowers).
- [`antopolskiy`](https://github.com/antopolskiy) for [`kanban-md`](https://github.com/antopolskiy/kanban-md), which does all the heavy lifting under the hood.
