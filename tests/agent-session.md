# AgentSession over a faux provider

`tests/agent-session.bend` builds an `AgentSession` (`packages/coding-agent/src/core/agent-session.bend`) over a scripted provider, as upstream's `registerFauxProvider` does: every request pops the next scripted text and answers with a start/text/end event stream. `tests/agent_session_check.py` runs three scenarios and asserts on the printed JSON events (the print-mode `toSessionJsonEvent` rendering) and on the session file.

- `persist` prompts once against a file-backed session. The events run `agent_start, turn_start, message_start, message_end` (user), `message_start, message_update…, message_end` (assistant), `turn_end, agent_end` (`willRetry: false`), `agent_settled`; the file holds the header, the user entry and an assistant entry equal to the final `message_end` message, chained by `parentId`; `getLastAssistantText` returns the reply.
- `queue` steers and queues a follow-up before prompting an in-memory session. `queue_update` reports the steering text, then both queues, then empty queues; the steering message joins the first turn (upstream's loop fetches steering messages before the first request), the follow-up starts a second turn after the assistant settles, and the session holds both replies.
- `mutate` sets the thinking level, the model and the session name. `setThinkingLevel("high")` on a model without reasoning clamps to `off` and emits `thinking_level_changed`; `setModel` records a `model_change` entry; `setSessionName` emits `session_info_changed` and records a `session_info` entry.

## Upstream cases implied

- suite/agent-session-prompt.test.ts: "prompts while idle and records a single text response".
- suite/agent-session-runtime.test.ts: "persists message_end assistant replacements to the session manager" (also checked live by `tests/print_cli_check.py`).
- suite/agent-session-queue.test.ts: "delivers follow-up messages only after the current run finishes" (the run is a text-only turn here; the tool-waiting variant needs the bash/wait tool harness).
- suite/agent-session-model-extension.test.ts: "setModel saves the model to the session and emits model_select" (the entry and event; `model_select` is an extension event), "clamps thinking levels to model capabilities and cycles available levels" (the clamp; `cycleThinkingLevel` is not ported).

## Adaptations

- The faux provider answers synchronously, so the streaming window in which `prompt` must refuse without a `streamingBehavior` cannot be opened here; that error path is exercised by the busy check in the live print CLI checks only when a real provider is slow, and is otherwise a pending contract.
- Upstream's harness reads `session.messages`; the runner reports entry counts and the last assistant text through the same public accessors (`messages`, `getLastAssistantText`, `sessionOf`).
- Extension hooks (`model_select`, input handlers, extension commands) are not ported; the cases that depend on them stay pending.

```sh
bun build/bend-process-files/bend2/main.ts tests/agent-session.bend -o build/agent-session.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/agent-session.bend build/agent-session
python3 tests/agent_session_check.py --runner build/agent-session.js
python3 tests/agent_session_check.py --runner build/agent-session --threads 4
```
