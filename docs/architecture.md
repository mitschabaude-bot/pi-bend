# Architecture fidelity

The target is pi-mono revision `46c9de402`, including its library design. The current executable in `src/` is a bootstrap prototype: it verified Bend compilation, native effects, authentication and a live tool loop. It does not establish architecture parity. Canonical ports live under the corresponding upstream paths in `packages/`.

## Required boundaries

| Upstream package | Library responsibilities to preserve | Current gap |
| --- | --- | --- |
| `ai` | Typed messages, content, usage, models, provider factories, transcript normalization, credentials, injectable transports, streaming events and stream results | Prototype passes generic JSON through a single hard-coded provider |
| `agent` | `Agent`, `AgentState`, `AgentContext`, `AgentMessage`, `AgentTool`, `AgentToolResult`, `AgentLoopConfig`, `StreamFn`, event subscriptions, tool hooks, queues, concurrent execution and settlement | Prototype combines provider invocation, tool dispatch and session writes in one loop |
| `agent/harness` | Execution environment, filesystem/shell interfaces, resources, reducer/drive layers, typed results, session storage and conformance, compaction | Native OS calls exist; harness interfaces and lifecycle are unported |
| `tui` | `Component`, `Terminal`, editor interfaces, reusable components, screen implementations, differential renderer, input protocols and themes | Unicode/native terminal primitives exist; the library is unported |
| `coding-agent` | SDK/session orchestration, resources, settings, tools/renderers, print/JSON/RPC/interactive modes and extensions | Prototype CLI lacks the SDK and most lifecycle semantics |
| Supporting packages | Preserve dependencies used by these libraries, including chord and telemetry; assess protocol/client/server and storage entry points against the reference | Applicability and export inventory pending |

The `ai` root in this revision is explicitly side-effect free. Provider factories, API implementations, compatibility registration and OAuth entry points are separate. The agent stream contract uses a normalized transcript with system messages carrying prompts and tool declarations. Porting an older mental model of pi would miss these contracts.

## Representation rules

Typed upstream records and unions become Bend records and algebraic data types, preserving each field and variant. Optional values remain distinguishable from explicit false, zero and null. JSON belongs at serialization boundaries and at upstream fields intentionally typed as arbitrary data. It is not the replacement for `Message`, `Model`, `AgentState` or typed events.

Upstream generic tools, custom messages and schema-validated arguments must retain their type relationships. Promise/callback/async-iterator APIs need documented Bend IO equivalents with the same cancellation, error, callback ordering, backpressure and settlement contracts. JavaScript declaration merging needs a typed Bend extension mechanism. These are implementation requirements, not reasons to discard extension points.

Complex dependencies belong in pure Bend, including HTTP/TLS, cryptographic operations, Unicode algorithms and numeric support. Missing language primitives should be added to Bend instead of replacing these libraries with C or JavaScript glue. The prototype C adapters are temporary migration liabilities. Operating-system primitives must remain injectable through the ported library interfaces so upstream mocked/conformance tests have equivalents.

## Module acceptance

For each module, record its upstream source and public exports; port the full data model and call contracts; port its tests; verify downstream composition; then migrate its callers. A module is not complete solely because a demonstration works. Track intentional language adaptations separately from remaining gaps.

The first canonical leaf module is `packages/agent/src/harness/utils/truncate.bend`. Public result field names and `truncateHead`, `truncateTail`, `truncateLine`, `formatSize` names match upstream. Bend has no optional call arguments, so head/tail take an explicit `TruncationOptions` record containing `Maybe` fields; `defaultOptions()` supplies the defaults. `truncateLine` takes an explicit limit, with `truncateLineDefault` supplying its default. Exported constants retain their names as nullary functions. Counts use `Nat`. This module still needs downstream integration; it does not imply the agent harness is ported.

## Runtime prerequisites for the core types

Bend 2.0.4 provides `F32`, while TypeScript numbers use binary64. Provider costs, sampling values and other numeric APIs require a binary64 solution before those types can be considered faithful; silently substituting F32 is not acceptable. The prototype's decimal JSON tokens only preserve serialization and do not solve numeric operations.

`packages/runtime/src/u64.bend` provides pure-Bend 64-bit integer operations, `u128.bend` supplies exact products, and `f64.bend` uses them for binary64 arithmetic, comparison and unsigned integer conversion. Independent vector tests pass; decimal parsing/formatting and remaining numeric operations are still prerequisites for complete integration. This package is a language support dependency, not a replacement for pi's library boundaries. Initial faithful content, usage and model-cost records now live in `packages/ai/src/types.bend`; that module remains explicitly partial.

`AssistantMessageEvent.partial` is a shared live response object in upstream, not an event-time snapshot. Immutable copies alone would change that contract. The event-stream port therefore needs an explicit shared-state representation and tests for consumers that retain event references. `EventStream.result()` settlement and queued-consumer termination also need distinct tests.

Pure-Bend `Ref`, `Deferred` and reusable `Callback` primitives now provide the shared identity, settlement and callback foundations. They use standard Bend channels rather than custom foreign code. Native concurrency tests cover retained identities, atomic updates, fan-out and concurrent callback invocation. Their explicit disposal requirement is a temporary mismatch with JavaScript garbage collection; managed shared-object reclamation remains required. All five upstream generic event-stream cases now have separate passing native ports, including consumer registration order and explicit end behavior. The stream module preserves typed callbacks, the shared result promise, per-iterator request serialization and live payload references. Assistant-event specialization, generator return/throw, recoverable callback errors, general scheduler equivalence and downstream integration remain open; passing this suite does not complete those contracts. See `packages/ai/README.md` for the API adaptation and lifetime boundaries.

`AgentTool` exposes argument preparation, schema validation, streaming updates, abort signals, structured details, tool usage, replay policy and execution-mode overrides. The prototype's `ToolResult{text,error}` is insufficient and is not the target tool API.
