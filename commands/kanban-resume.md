---
description: Answer a card that was blocked by KANBAN_QUESTION. Appends the answer to the card body, unblocks it, and sends it back to todo so the next /kanban-auto picks it up.
---

# /kanban-resume

Usage:

```text
/kanban-resume <card-id> "<your answer text>"
```

The answer can be multi-line; quote it (or use a HEREDOC if your client supports it).

## Steps for the agent

1. **Invoke `superpowers-kanban` skill.**

2. **Verify the card is actually blocked.** Read the card via `kanban-md`:

   ```bash
   BOARD=$("${CLAUDE_PLUGIN_ROOT}/bin/kanban-active-board")
   kanban-md --dir "$BOARD" show <card-id>
   ```

   If the card is not blocked, tell the user and STOP. (We don't want to silently overwrite an in-progress card with an "answer" that doesn't belong there.)

3. **Resume the card:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/kanban-resume" <card-id> "<answer>"
   ```

   The script:
   - Appends `## Answer (<timestamp>)\n\n<answer>` to the card body
   - Runs `kanban-md edit <id> --unblock`
   - Runs `kanban-md move <id> todo` so the next `pick` will surface it

4. **Tell the user what to do next.** Two options:
   - Run `/kanban-auto` to resume the loop (the next pick will return this card)
   - Answer more blocked cards first, then `/kanban-auto`

## Failure modes

- Card not blocked → script does nothing; surface and stop.
- Card id doesn't exist → kanban-md error; print it verbatim.
- No active plan → `kanban-active-board` errors. Tell the user to set one via `/kanban-add-plan`.

## DO NOT

- Do NOT start the auto-loop here. That's `/kanban-auto`. Resume is for answering, not for executing.
- Do NOT edit the card body by hand. Use the script so the answer ends up under a proper `## Answer (timestamp)` heading the subagent will read.
- Do NOT unblock cards that weren't blocked by a question — those need investigation, not an "answer".
