# Harness-based coding-agent suites

`tests/suite-harness.bend` ports upstream `packages/coding-agent/test/suite/harness.ts` (`createHarness`). It builds an `AgentSession` over the faux provider of `tests/regressions.bend` (its `Fixture`, replies and holds), an in-memory session, the settings of the scenario's agent directory, pi's default system prompt for the active tools (upstream's test resource loader has no prompt override), and the tools: pi's built-in read, bash, edit and write when the upstream test passes no `tools` (`Builtins`), otherwise exactly the scenario's tools (`Scripted`, upstream `baseToolsOverride`). Every session event is printed as a JSON line (upstream `harness.events`). `tests/suite_harness_check.py` runs the scenarios and applies each upstream test's assertions:

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
- `suite/agent-session-boundaries.test.ts`: the turn_end and agent_before_settle boundary cases scripted by `boundaryScenario` (handoff compaction, the three queue schedulings, verbatim replacement and unsent input through threshold compaction, pre-settlement custom message, pending agent_end context, deferred pre-settlement follow-up, invalid explicit continuation) and all of `durable length recovery` but `omits a recoverable projected replacement by its source entry ID`.
- Extension regressions (inline extensions loaded into the harness's runner): #3982 (message_end replacement), #1717/#2113 (both tests), #5998, #8935, #6363 (all three tests), #3688 (session_before_tree cancel) and #9178's second test (a navigation waiting in session_before_tree).
- `suite/lax-message-content.test.ts` (all six), #2023, and #9789 but its before_agent_start case.
- `suite/agent-session-compaction-model-overrides.test.ts`: all tests but `captures model identity before awaiting summarization auth` (no native summarization-auth step to interleave a model change into).

## Adaptations

- `harness.faux.setResponses` is the scenario's scripted reply list. Tool-call replies stream as upstream's `fauxToolCall` blocks (start, argument deltas, end).
- Waiting for `tool_execution_start` or `message_update` becomes a channel the operation or faux stream signals. `persists aborted assistant messages` streams the first chunk of the 20,000-character reply, then waits until the request's signal is aborted and ends the stream as aborted, as upstream's faux checks its signal between chunks.
- `cancels running bash commands with abortBash`: upstream checks `isBashRunning` after one event-loop tick; here the check runs once the operation has been entered. The operation rejects with `aborted` once its signal is aborted, like upstream's.
- Branch summarization's summarizer request carries only the transcript and the output cap (`SummaryRequest`), so it cannot set a tool choice; the session's summarizer options (`summaryOptions`) set none. The tool-choice half of `does not override tool choice for branch summaries` holds by construction; its 4096-token cap is checked.
- Extension factories are Bend functions (`Ext.InlineExtension`), and handlers print what upstream's tests collect in arrays (`preflight`, `result_hook`, `extension_event`, `roles_at_tool_call`, `command_result`).
- #6363's `extension command waitForIdle waits for session-level settlement`: the command context actions are Bend callbacks bound with `ExtensionRunner.bindCommandContext` (upstream `bindExtensions({ commandContextActions })`); "not finished before the tool is released" is the order of the `released` and `command_result` lines.
- #8935: after the aborted batch the run ends with an aborted assistant message, which upstream's test does not assert on.
- Upstream tests append to `harness.sessionManager` and then set `agent.state.messages = buildSessionContext().messages`; here the seed is stored before the session is created, or appended later with `AgentSession.appendSessionMessage` and loaded with `refreshSessionContext` (upstream `refreshContext()`).
- The compaction-override scenarios print the recorded `session_before_compact` preparation (`preparation` lines), and the summary request's output cap with the request (`request` lines' `maxTokens`).
- lax-message-content: the session-entry cases decode JSON lines (`entry_messages`). The in-memory cases use an empty content list, since a Bend tool result, `message_end` replacement or custom message cannot omit its content; they check that the empty content reaches agent state and the next turn.
- Boundary scenarios script their handlers (`BoundaryScript`: a turn_end and/or agent_before_settle action that may fire once, only for one outcome, send messages through the ExtensionAPI and return drafts and a continuation; an agent_end sender; a session_before_compact supplier). Handlers that read `ctx.sessionManager.getBranch()` upstream read the harness session's branch.
- Upstream collects `requests` from response factories; here every request's serialized context is printed and the requests after the first are compared.

