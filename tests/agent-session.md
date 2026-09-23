# AgentSession over a faux provider

`tests/agent-session.bend` builds an `AgentSession` (`packages/coding-agent/src/core/agent-session.bend`) over a scripted provider, as upstream's `registerFauxProvider` does: every request pops the next scripted text and answers with a start/text/end event stream. `tests/agent_session_check.py` runs five scenario kinds and asserts on the printed JSON events (the print-mode `toSessionJsonEvent` rendering) and on the session file.

- `persist` prompts once against a file-backed session. The events run `agent_start, turn_start, message_start, message_end` (user), `message_start, message_update…, message_end` (assistant), `turn_end, agent_end` (`willRetry: false`), `agent_settled`; the file holds the header, the user entry and an assistant entry equal to the final `message_end` message, chained by `parentId`; `getLastAssistantText` returns the reply.
- `queue` steers and queues a follow-up before prompting an in-memory session. `queue_update` reports the steering text, then both queues, then empty queues; the steering message joins the first turn (upstream's loop fetches steering messages before the first request), the follow-up starts a second turn after the assistant settles, and the session holds both replies.
- `busy` holds the first request open (the provider reports `started` on a channel and waits for `release`) while the prompt runs in a spawned fiber. Meanwhile `isStreaming` is true, a plain `prompt` is refused with "Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message.", `prompt` with `steer` and `followUp` behaviors queue; after release the steering message gets the second turn, the follow-up the third, `queue_update` empties in that order, and the prompt fiber finishes with `isStreaming` false.
- `retry` scripts failures (a response starting with `!` fails with the rest as error message) under a `settings.json` retry policy: a transient error emits `auto_retry_start` (attempt, max attempts, delay, message) after `agent_end` with `willRetry: true`, drops the failed assistant message from the agent's context (the session keeps it), sleeps the backoff and continues the agent; the next successful assistant message emits `auto_retry_end` with `success: true` at its `message_end`; exhausting the budget emits `auto_retry_end` with `success: false` and the final error; disabled retry, non-retryable errors and context overflow do not retry; `abortRetry` from another fiber during the sleep ends with "Retry cancelled" and no further request.
- `mutate` sets the thinking level, the model and the session name. `setThinkingLevel("high")` on a model without reasoning clamps to `off` and emits `thinking_level_changed`; `setModel` records a `model_change` entry; `setSessionName` emits `session_info_changed` and records a `session_info` entry.

## Upstream cases implied

- suite/agent-session-prompt.test.ts: "prompts while idle and records a single text response".
- suite/agent-session-runtime.test.ts: "persists message_end assistant replacements to the session manager" (also checked live by `tests/print_cli_check.py`).
- suite/agent-session-prompt.test.ts: "throws when prompted during streaming without a streamingBehavior" (the busy scenario; the same result for the unqueued prompt, held at the provider instead of a waiting tool).
- agent-session-concurrent.test.ts: "should throw when prompt() called while streaming", "should allow steer() while streaming", "should allow followUp() while streaming" and "should allow prompt() after previous completes" (the busy scenario's second and third turns).
- suite/agent-session-queue.test.ts: "delivers follow-up messages only after the current run finishes" (queue and busy scenarios; the follow-up only starts after the assistant's turn and the delivered steering).
- suite/agent-session-retry-events.test.ts: "retries after a transient error and succeeds", "retries multiple transient failures and succeeds on the final attempt", "exhausts max retries and emits a failure event", "does not retry when retry is disabled", "does not retry non-retryable errors", "cancels retry sleep when abortRetry is called" (the retry scenarios; the harness counts provider calls as scripted responses consumed).
- agent-session-retry.test.ts: "retries after a transient error and succeeds", "exhausts max retries and emits failure"; "caps agent retry delay" is checked on `retryDelayMs` by `tests/retry_classify_check.py`.
- suite/agent-session-model-extension.test.ts: "setModel saves the model to the session and emits model_select" (the entry and event; `model_select` is an extension event), "clamps thinking levels to model capabilities and cycles available levels" (the clamp; `cycleThinkingLevel` is not ported).

## Adaptations

- Upstream opens the streaming window with a waiting tool; the port holds the provider request on a channel gate, since the bash tool and tool-waiting harness are not ported yet. `prompt` returns a `Fail` string where upstream throws.
- Upstream's harness reads `session.messages`; the runner reports entry counts and the last assistant text through the same public accessors (`messages`, `getLastAssistantText`, `sessionOf`).
- Extension hooks (`model_select`, input handlers, extension commands) are not ported; the cases that depend on them stay pending.
- Retry settings are read once when the session is created (upstream reads the settings manager on every decision); the port's settings manager is an immutable value and the session has no settings setter yet.
- Backoff delays beyond the timer's 32-bit millisecond range sleep one millisecond, as Node's timer overflow does. The backoff sleep is cancelled through an abort controller kept in the shared state; `abortRetry` after the sleep has already finished is a no-op.
- `isRetrying`, `abortRetry` and `abort` (cancel the sleep, then abort the agent) are the public surface; the summarization retry callbacks follow with compaction.

```sh
bun build/bend-process-files/bend2/main.ts tests/agent-session.bend -o build/agent-session.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/agent-session.bend build/agent-session
python3 tests/agent_session_check.py --runner build/agent-session.js
python3 tests/agent_session_check.py --runner build/agent-session --threads 4
```
