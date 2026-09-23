# Compaction core

`tests/compaction.bend` builds the fixtures of upstream `compaction.test.ts` and `compaction-serialization.test.ts` as chained session entries and prints one JSON line per scenario. `tests/compaction_check.py` pins the upstream expectations (27 checks) against `packages/coding-agent/src/core/compaction/compaction.bend` and `compaction/utils.bend`.

- Token calculation, `getLastAssistantUsage` (skips aborted and all-zero usage), `estimateContextTokens` (last non-zero usage as the anchor plus trailing estimates) and `shouldCompact`.
- `findCutPoint`: the actual-token-difference, no-valid-cut, all-fit and split-turn cases, plus the context-visible custom message budget. The first and split-turn cases are as loose as upstream (the cut is at a user or assistant message; a cut at an assistant message reports the turn start at index 2).
- `buildSessionContext` with none, one and several compactions, the first entry kept, and model and thinking-level changes.
- `prepareCompaction`: system messages are not conversation history, repeated compactions are skipped while the kept messages still fit, and previously kept messages are summarized again once the recent window moves past them.
- `serializeConversation`: long tool results are truncated, short ones and user/assistant text are not; thinking, tool calls and tool results use upstream's labels.
- File operations: modified files exclude read-only ones and both lists are sorted into upstream's `<read-files>`/`<modified-files>` sections.

The summarizing `compact` needs a model; the AgentSession scenarios run it over the faux provider (`tests/agent-session.md`). Not ported: the large-session fixture and the LLM summarization cases, which need `ANTHROPIC_OAUTH_TOKEN`.

```sh
bun build/bend-process-files/bend2/main.ts tests/compaction.bend -o build/compaction.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=4 sh scripts/build-pure.sh tests/compaction.bend build/compaction
python3 tests/compaction_check.py --runner build/compaction.js
python3 tests/compaction_check.py --runner build/compaction --threads 4
```
