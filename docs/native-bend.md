# Native Bend cleanup

This records the completed cleanup of JavaScript object and array emulation, performed before resuming the full port. Preserve pi's modular libraries, meaningful typed interfaces, algorithms, tool behavior and event ordering. Use immutable values and explicit state transitions. Synchronization belongs to effectful stream/agent machinery, not ordinary nested records.

## Decisions

- Remove descriptors, reflective property inspection/definition/deletion, prototypes, symbols, sparse JS arrays, object extensibility, JavaScript `typeof` and object identity comparisons. These were supplemental compatibility work, not established pi contracts.
- Dictionaries retain insertion order, with no numeric-key sorting. Ordinary strings such as `__proto__` have no special meaning.
- Tool declaration equality is structural: dictionary order does not matter, list order and values do. Gregor explicitly approved this on 2026-09-18. Upstream `packages/ai/src/utils/transcript.ts:140` compares serialized declarations; the adaptation means reordering schema fields alone no longer triggers tool redefinition/provider fallback.
- Numeric structural equality treats `0` and `-0` as equal, including inside nested values. Gregor explicitly approved treating `[0, -0]` as non-unique on 2026-09-18. Schema `uniqueItems` therefore rejects it, unlike the pinned TypeBox implementation; `tests/unique_items_check.py` records direct and nested signed-zero cases as approved differences.
- Schemas and arguments use immutable JSON-compatible data. Optional configuration lives in typed `Maybe` fields; tool callbacks live in the executable tool record. No stringify/parse cloning or callable schema hooks.
- Constrained sampling uses ordinary variants and a record with optional grammar strings. Property insertion order and an extra distinction between missing/undefined grammar entries are removed.
- Cost calculation returns its computed value rather than mutating an aliased cost record. Numerical behavior is retained.
- Transcript normalization/replay are pure functions returning new values.

## Meaningful contracts to preserve

Upstream `packages/ai/test/validation.test.ts` requires primitive coercion and optional non-nullable null removal, while retaining nullable nulls. These are schema normalization rules and need no JavaScript object machinery. The primitive subset is implemented; full recursive validation was already pending and remains so.

Upstream `packages/agent/test/agent-loop.test.ts:480` requires before-tool hooks to change arguments used for execution, without revalidation. Preserve that capability with an explicit returned argument update. Removing mutation must not silently remove the hook's capability.

Upstream `packages/agent/test/agent-loop.test.ts:1060` requires the context/messages returned by `prepareNextTurn` to reach the next provider request. Preserve this with explicit values and state transitions.

## Approved streaming behavior

Upstream agent events shallow-copy assistant messages while retaining nested mutable content. An early retained event can therefore expose later changes. Gregor explicitly approved immutable event snapshots on 2026-09-18: each event keeps the content it had when emitted, and subsequent events carry subsequent values. The request pipeline and assistant stream tests verify retained snapshots.

## Completed cleanup

Removed the dynamic value/reflection runtime, descriptors, own-property APIs, prototype/symbol/sparse-array support, and the DOM Event/EventTarget/listener/onabort compatibility layer. Their supplemental compatibility tests are retired. Numeric helpers and Unicode wire encoding remain where they support pi's actual data and serialization.

Canonical AI/agent records now contain ordinary values: messages, content, usage/cost, diagnostics, tools, schemas, contexts, configurations, options and hooks. Transcript operations, tool selection, declaration comparison and result/turn transformations are pure. Argument preparation returns typed values; event emission and callbacks remain IO operations. Only running-agent state and asynchronous resource machinery retain synchronized cells. Opaque application-supplied generic values may explicitly contain resource handles; the library does not recursively freeze such resources.

Cancellation uses a typed reason and a first-settled deferred value, with removable observations. Dictionary keys use native string equality and insertion order, including numeric-looking keys. JSON quoting handles Unicode at the codec boundary; it does not redefine dictionary key identity.

Meaningful behavior changes include the approved structural equality, signed-zero uniqueness and immutable snapshot decisions above. Other changes are native API adaptations: cost functions return values; hooks return updates; configuration absence uses `Maybe`; cancellation uses typed observations. In-place mutations by JS extensions are outside the requested extension scope. The upstream before-tool argument-update capability remains represented explicitly, but integration with the complete executor was already pending and remains so.

## Verification and scope

The original five event-stream tests and nine replay tests retain their names and behavioral assertions. The native agent runner checks callback ordering, conversion and credential failures, immutable snapshots, explicit hook/queue updates, typed argument preparation, emission failures, truncated calls and all 21 completion cases. Source-derived vectors separately check policies, result merging, turn updates, pricing, schemas and tool history. `sh tests/native-cleanup.sh` runs the migration checks; `tests/UPSTREAM.md` records current commands/counts.

The former supplemental identity/mutation harnesses for API keys, context conversion, turn preparation, queues, stopping, assistant responses, tool preparation/emission and truncated calls were replaced with native contract checks. Their historical vector counts are not current coverage claims, and not every old supplemental scheduler scenario has been retained. Reflection/DOM behavior is intentionally no longer an acceptance target.

This completes the native-representation cleanup of the existing code, not the full port. The upstream inventory remains 3 ported, 3 partial and 543 pending suites. Full validation, providers, the complete agent executor, terminal parity and Bend extensions remain unfinished. Gregor resumed the main goal after accepting this cleanup.

The configurable default stream function uses an explicit host-owned registry instead of a JavaScript module variable. Hosts share the registry to preserve the upstream default scope. Providers remain typed borrowed callbacks; replacing or clearing the default does not retire callbacks selected by running loops. Missing defaults are typed errors with the upstream message.

Gregor approved closing the asynchronous agent-loop event stream and returning a typed error from the run result when the underlying loop fails (2026-09-18). Upstream `agentLoop`/`agentLoopContinue` attach only a success handler to the loop promise, so rejection can leave the stream unfinished and surface as an unhandled rejection. The native wrapper must surface failure explicitly and terminate event iteration; this behavior is implemented in `packages/agent/src/loop-stream.bend`. This approval does not add an `agent_end` event to failed runs.


The source `AgentState.systemPrompt` getter is represented by the pure `agent-state.systemPrompt(state)` query, which replays system messages from the immutable transcript. It is not a stored field that could diverge from `messages`. Pending tool IDs use an immutable string set; state transitions return new values, and runtime/listener ownership remains outside the state snapshot.
