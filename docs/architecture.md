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

## Native representation

Ordinary messages, content, schemas, tools, configurations, contexts, headers and usage/cost records are immutable Bend values. Lists are persistent lists; dictionaries preserve insertion order and compare native string keys. Typed optional fields carry absence explicitly. No prototype, descriptor, own-property, sparse-array or object-identity runtime is required.

Tool declaration comparison is structural, and streaming events retain immutable snapshots. Both intentional behavior changes were approved by Gregor. Hooks express changes through returned records: before-tool hooks return arguments/context, next-turn hooks return context/messages/model/thinking, and after-tool hooks return optional result overrides. See [native-bend.md](native-bend.md) for upstream contracts and coverage.

Synchronization stays in explicit effect resources: running-agent state, stream queues, callback factories, deferred results and cancellation observations. Resource handles currently require owner-directed disposal. Cancellation uses typed reasons and removable observations, without DOM event machinery. Full agent execution, cancellation integration and managed resource lifetimes remain open.

Pure-Bend numeric foundations implement binary64 arithmetic, exact integer/rational conversion, parsing and shortest formatting. JSON has its own codec boundary. These dependencies preserve numeric behavior without replacing pi's typed library architecture.

Current module status and limitations are recorded in [pi-ai](../packages/ai/README.md), [pi-agent](../packages/agent/README.md), [runtime](../packages/runtime/README.md) and [test coverage](../tests/UPSTREAM.md).

Native schema builders live in `packages/runtime/src/schema-builder.bend`. A `Declaration` carries the JSON schema sent to providers, an executable schema constraint, and an explicit immutable conversion policy. Composition keeps those three representations together; runtime validation and conversion need no hidden host-language metadata. Primitive types, JSON-compatible literals, arrays, tuples, unions and objects have factories. Object fields explicitly wrap a declaration as required or optional. Object conversion uses the proposed literal-key dictionary policy; its differences from TypeBox await approval before public integration. `withOptions` supports annotations, numeric bounds, collection limits, uniqueness and boolean additional-property constraints. It returns a new declaration, recompiles its wire schema, and updates union candidate constraints. Structural overrides fail explicitly. Other options, schema-valued additional-property conversion and integration into AI tool validation remain unfinished.

`packages/agent/src/tool-batch.bend` owns sequential batch scheduling independently of per-call execution. Each invocation receives the previous immutable state and returns the next state, one delivered message and its termination flag. The scheduler checks cancellation after completion and reduces termination across the processed batch. A per-call operation must compose the existing preparation, execution, finalization and event-delivery stages; that adapter and the parallel scheduler remain pending.
