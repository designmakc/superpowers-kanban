---
description: Start a read-only web viewer of all kanban boards in the current project. Renders the roadmap and every plan board as HTML drag-free kanban views, with card detail pages. Pure Python stdlib — no Node, no npm. Stops with Ctrl-C.
---

# /kanban-view

Usage:

```text
/kanban-view             # start on http://127.0.0.1:8765/
/kanban-view --port 8000 # custom port
```

## Steps for the agent

1. **Invoke `superpowers-kanban` skill.**

2. **Verify pre-conditions:**
   - `.superpowers-kanban/` exists. If not, tell the user to run `/kanban-init` first.
   - `kanban-md` is on PATH.

3. **Start the viewer in the background** so the user can keep working in this session:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/kanban-viewer" --port 8765 &
   ```

   Capture the URL (default `http://127.0.0.1:8765/`) and print it.

4. **Tell the user** the URL and that the viewer is **read-only**. To edit cards they should use:
   - `kanban-md <command>` from a shell (TUI: `kanban-md board`)
   - `/kanban-resume <id> "<answer>"` to answer questions
   - `/kanban-auto` to run the agent loop

5. **Remind the user how to stop it:** kill the process or run `pkill -f kanban-viewer`.

## What the viewer shows

- **Index page** (`/`) — list of all boards with card counts.
- **Board page** (`/board?id=<board>`) — six columns (backlog, todo, in-progress, review, done, archived). Each card shows id, title, tags, claim, and a BLOCKED badge if applicable.
- **Card page** (`/card?board=<board>&task=<id>`) — full body including any `## Question` and `## Answer (...)` sections.
- **JSON API** (`/api/boards`, `/api/board?id=<id>`) — for scripts or other tools.

## DO NOT

- Do NOT recommend the viewer as the way to edit cards. It is read-only by design.
- Do NOT change the port without telling the user — they may have firewall rules.
- Do NOT expose this beyond localhost. The viewer binds to `127.0.0.1` and has no auth; do not bind it to `0.0.0.0` or a public interface.
