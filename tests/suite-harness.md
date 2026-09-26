# Harness-based coding-agent suites

`tests/suite-harness.bend` ports upstream `packages/coding-agent/test/suite/harness.ts` (`createHarness`). It builds an `AgentSession` over the faux provider of `tests/regressions.bend` (its `Fixture`, replies and holds), an in-memory session, the settings of the scenario's agent directory, a system prompt section (upstream's test resource loader declares a system prompt, so the first request is preceded by a `system` message), and the scenario's tools, all registered and active (upstream `baseToolsOverride`). Every session event is printed as a JSON line (upstream `harness.events`). `tests/suite_harness_check.py` runs the scenarios and applies each upstream test's assertions:

```sh
BEND=build/bend-native-toolchain/bend2/main.ts
bun $BEND tests/suite-harness.bend -o build/suite-harness.js
python3 tests/suite_harness_check.py                                   # Bun lane
python3 tests/suite_harness_check.py --suite-harness build/suite-harness-native --threads 4
```

Tools are Bend callbacks: `echo` returns its `text` argument after a prefix; `wait` sends a custom message (`triggerTurn: false`) while it runs, as #8537's background task does.

## Coverage

- `suite/agent-session-bash-persistence.test.ts`: all eleven tests. Six run in `tests/agent_session_check.py` (`bash` and `bash_deferred` scenarios); `cancels running bash commands with abortBash`, `aborts all active bash executions`, `persists user, assistant, toolResult, and custom messages in order`, `does not emit message_end for bash execution messages` and `persists aborted assistant messages` run here.
- `suite/regressions/8537-custom-message-tool-result-ordering.test.ts`: all three tests.
- `test/branch-summarization.test.ts` runs in `tests/branch_summarization_check.py` (`generate` mode of `tests/branch-summarization.bend`).

## Adaptations

- `harness.faux.setResponses` is the scenario's scripted reply list. Tool-call replies stream as upstream's `fauxToolCall` blocks (start, argument deltas, end).
- Waiting for `tool_execution_start` or `message_update` becomes a channel the operation or faux stream signals. `persists aborted assistant messages` streams the first chunk of the 20,000-character reply, then waits until the request's signal is aborted and ends the stream as aborted, as upstream's faux checks its signal between chunks.
- `cancels running bash commands with abortBash`: upstream checks `isBashRunning` after one event-loop tick; here the check runs once the operation has been entered. The operation rejects with `aborted` once its signal is aborted, like upstream's.
- Branch summarization's summarizer request carries only the transcript and the output cap (`SummaryRequest`), so it cannot set a tool choice; the session's summarizer options (`summaryOptions`) set none. The tool-choice half of `does not override tool choice for branch summaries` holds by construction; its 4096-token cap is checked.
