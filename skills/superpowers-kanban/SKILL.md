---
name: superpowers-kanban
description: Use when the user mentions a kanban board, asks to plan a roadmap, asks to break a plan into cards, or runs any `/kanban-*` or `/roadmap-*` slash command. Defines how plans, roadmaps, and cards relate, and how this plugin integrates with Superpowers' brainstorming, writing-plans, and subagent-driven-development skills.
---

# superpowers-kanban

This plugin sits **on top of** upstream Superpowers and adds a persistent kanban layer for plans, plus an auto-mode loop where subagents pick up cards and execute them. The kanban engine is [`kanban-md`](https://github.com/antopolskiy/kanban-md): a file-based, agent-first kanban CLI by `antopolskiy`. Cards are markdown files with YAML frontmatter, stored in the user's project repo.

## Concepts

**Board.** A kanban-md directory with a `config.yml` and a `tasks/` folder. Two kinds:

- **Roadmap board** at `.superpowers-kanban/roadmap/`. One per project. Each card represents an **epic** (one design/plan) and has frontmatter pointing at its detail board.
- **Plan board** at `.superpowers-kanban/plans/<plan-id>/`. One per plan. Cards represent the bite-sized tasks produced by `superpowers:writing-plans`.

**Card statuses** (kanban-md defaults, do not rename):
`backlog → todo → in-progress → review → done → archived`

A card may additionally be **blocked** — orthogonal to status, used when work is paused for a human answer.

**Claim.** Before a subagent edits a card, it must hold an exclusive claim on it via `kanban-md pick --claim <agent>`. Claims auto-expire (default 1h).

## When this skill applies

Invoke this skill BEFORE any of:

- creating, moving, or completing a kanban card
- running `/kanban-init`, `/kanban-add-plan`, `/kanban-auto`, `/kanban-resume`, `/kanban-view`, `/roadmap-status`
- breaking a plan from `superpowers:writing-plans` into cards
- responding to "execute the plan" or "start working on the kanban"

## Workflow integration

The pipeline composes upstream Superpowers skills with this plugin's commands:

1. **`superpowers:brainstorming`** — refine the idea, produce design notes
2. **`superpowers:writing-plans`** — produce a detailed plan with bite-sized tasks
3. **`/kanban-add-plan`** (this plugin) — turn that plan into a new board: each plan task becomes a card in `todo`; an epic card is added to the roadmap board pointing at the new plan board
4. **`/kanban-auto`** (this plugin) — start the auto-loop. For each card: pick → dispatch fresh subagent via `superpowers:subagent-driven-development` → on completion move to review → run `superpowers:requesting-code-review` → done
5. **`superpowers:finishing-a-development-branch`** — when the plan board is empty

## Question protocol (the "blocked" status)

When a subagent decides it needs the user's input it MUST NOT just give up. It MUST:

1. Write its question into the card body under a `## Question` heading
2. End its turn with the exact line `KANBAN_QUESTION: <one-line summary>` so the auto-loop can parse it
3. The auto-loop then runs `kanban-md handoff <card-id> --blocked --note "<summary>" --release` which moves the card to `review`, marks it blocked, and releases the claim
4. The auto-loop stops and tells the user the card id + question
5. User answers via `/kanban-resume <card-id> "<answer>"`. The answer is appended under `## Answers` and the card returns to `todo`.
6. The next `pick` will surface this card again; the next subagent reads the answer in the card body.

## Files and directories

```
<user-project>/
  .superpowers-kanban/
    config.json              # plugin-level config (active plan, kanban-md path, etc.)
    roadmap/
      config.yml             # kanban-md board config
      tasks/<epic>.md        # frontmatter has plan_dir: plans/<plan-id>
    plans/
      <plan-id>/
        config.yml
        tasks/<card>.md
```

Cards SHOULD be committed to git — they are the durable record of agent work.

## Hard rules

- Never run two `/kanban-auto` loops in the same project at the same time
- Never edit a card without claiming it first (kanban-md will refuse if `require_claim` is set on the column)
- Never invent statuses. Use only the lifecycle above plus the orthogonal `blocked` flag.
- Never bypass the question protocol by asking the user mid-loop. If you have a question, follow the protocol exactly.
- The kill switch is the file `.superpowers-kanban/STOP`. The auto-loop must check for it before every pick.

## Out of scope for this skill

This skill describes the model and integration. The procedural details of the auto-loop live in `superpowers:superpowers-kanban-auto-mode` (added in M3). Invoke that skill when running `/kanban-auto`.
