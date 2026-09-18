# Port status

Reference: pi 0.85.1, commit `46c9de402`. This checklist describes the requested destination, not completed features. JavaScript extension compatibility is explicitly excluded by the user.

- [ ] Native build and dependency setup
- [ ] JSON and incremental SSE parsing
- [ ] HTTPS, streaming, cancellation, timeouts, retries, proxies, WebSockets
- [ ] OpenAI OAuth credential loading, refresh and persistence
- [ ] Provider adapters and model catalog parity
- [ ] Agent loop, event ordering, steering, tool validation and cancellation
- [ ] Read, bash, edit, write, grep, find, ls tools with upstream semantics
- [ ] Project instructions, skills, prompt templates, settings and themes
- [ ] Session persistence, tree navigation, continue/resume/fork and compaction
- [ ] Print, JSON event and RPC modes; embedding interface
- [ ] Terminal editor, differential rendering, Markdown, images, shortcuts and dialogs
- [ ] Bend extension interface, discovery, hooks and custom tools/UI
- [ ] Native Linux/macOS portability; account for upstream Windows support
- [ ] Upstream-derived behavioral and terminal snapshot tests
- [ ] Final pure-Bend pi-bend subagent develops and tests a feature

Authentication preflight: upstream pi successfully called `openai-codex/gpt-5.6-sol` using the existing private auth file on 2026-09-17. No interactive login was required. This is not yet evidence for authentication implemented in Bend.

## Milestones

- Native JSON parser/serializer: nested structures, exact number spelling, escapes, surrogate pairs, malformed input rejection tested.
- Native OS effects: file I/O, subprocess output/status/timeouts, streaming HTTP through libcurl. Local HTTP fixture splits Unicode into individual bytes to test transport boundaries.
- SSE parser: split events, CRLF, comments, multiline data and terminal marker tested.
- Native OpenAI call succeeded with `PI_BEND_OPENAI_OK`. Credential loading and streaming execute in the native executable. Refresh/persistence is implemented but has not yet been exercised against expired live credentials.
- Print-mode agent loop and read/write/exact-edit/bash tools compile. Tests cover files, offsets, rejected ambiguous edits, exit codes and timeouts. Fuzzy/multi-edit, image reading and exact truncation parity remain open.
- Native session persistence and explicit-file resume pass a local provider fixture. Entries have version-3 session headers, linked IDs, canonical messages, and custom raw-provider transcript snapshots. Full upstream session import, branching, compaction and recovery remain open.
- Provider fixture verifies transient-error retry, tool items preserved when completion omits them, continued tool conversations, and disabled tools refusing unsolicited calls.
- A live native pi-bend process implemented a Python slugify function and three passing tests in a disposable project. A subsequent invocation developed the Bend truncation module in this repository; review and parity validation are separate from that execution proof.
- Native Unicode segmentation covers combining marks, emoji sequences, CJK, controls and word boundaries through ICU. Terminal rendering is not implemented yet.
- The subagent-written truncation module, subsequently reviewed and adapted to the canonical package/API layout, passes all nine upstream cases, including the 300,000-character regression and 57,405 byte-limit checks. Review removed a redundant tail copy that made large inputs quadratic and added UTF-16 compatibility. The module has not yet replaced the prototype tool truncation paths.
- Upstream tests are inventoried by source hash: 549 suites discovered across pi-mono, with applicability review still needed for auxiliary packages. The truncation, generic event-stream and system-message-replay suites have full native ports; regional-indicator width, max-thinking and models-runtime coverage are partial; the remaining suites are pending. See `tests/UPSTREAM.md` for the acceptance rules and current gaps.
- Pure-Bend runtime foundations: unsigned/wide arithmetic passes 272 independent vectors; binary64 addition/subtraction/multiplication/division, comparison and integer conversion pass 1,077 vectors covering signed zero, subnormals, rounding ties, cancellation, overflow, infinities and NaNs. These modules use no custom C/JS effects. Decimal parsing and complete integration remain open; shortest formatting is tested separately below.
- `packages/ai/src/types.bend` starts the typed library port with faithful content, usage, model-cost records and stop reasons. Numeric fields use binary64, and optional values remain distinct. The module is partial; model data records are implemented, while schema and provider-option contracts remain open; schema-data declaration comparison is implemented separately.
- Pure-Bend shared references, deferred results and reusable callback handles pass native concurrency tests. These support live stream-event references and runtime callback values. Automatic lifetime reclamation remains open; explicit disposal is currently required.

- Generic `EventStream<T, R>` now passes all five upstream regression cases on one and four runtime threads, plus four native lifecycle/shared-identity cases. Buffered delivery, waiting-consumer FIFO, per-iterator next serialization and distinct final-result settlement have canonical typed implementations. The module is still partial: return/throw, recoverable callback failures, scheduler equivalence and downstream integration remain pending.

- Canonical user/assistant/tool-result messages and all twelve assistant-event variants now have typed declarations, including shared live message/content references and opaque caller-typed payloads. The assistant stream factory passes native tests for all variants, success/error extraction, setup failure and retained identities on one and four threads. These tests supplement existing upstream coverage; schema relationships, dynamic-value integration, serialization and provider composition remain open.

- Raw/normalized contexts, system messages and generic tool declarations now have canonical types. Context normalization, prompt rendering, system replay and collapse pass all nine upstream replay-suite cases, plus native separator/ordering/identity and transport-tool regressions. Own-property records and insertion-ordered maps each pass 50 JavaScript differential mutation sequences. Full schema-object declaration comparison, schema validation and custom-role integration remain pending.

- Exact unsigned arbitrary-precision arithmetic now passes 179 independent vectors plus power and input cases, including values needed for extreme binary64 exponents. Integer decimal parsing/formatting is implemented in pure Bend. Schema-data declaration serialization/comparison is covered below.

- Pure-Bend shortest binary64 formatting matches JavaScript on 1,092 bit patterns, including dense subnormal cases, exponent boundaries and decimal midpoint ties in both directions. JSON numeric spelling also handles non-finite values and signed zero. Decimal parsing, full JSON/schema serialization and performance evaluation remain pending.

- Explicit canonical `JsonValue` serialization matches JavaScript on 892 string cases and 114 structured values, with native checks for 2,000 nested arrays and UTF-16-equivalent map keys. Arbitrary dynamic-value/schema serialization and typed message/tool wire codecs remain pending.

- Schema-data snapshots match JavaScript JSON round trips on 156 cases, including twelve actual pinned-TypeBox fixtures, covering omitted metadata, non-enumerable and symbol properties, array omissions, numbers and Unicode. The pi-ai schema bridge also checks canonical serialized output; native checks cover explicit unsupported hooks and 2,000-level nesting. Live-object hooks, cycles, schema builders/validation and full typed-tool integration remain pending; no additional upstream suite is complete.

- Constrained-sampling configurations retain required-field and grammar-variant insertion order. Their typed JSON codec and grammar mutations pass 115 JavaScript comparisons, with existing transcript tests passing on one and four threads. Extra runtime fields, shared mutable configurations and full declaration integration remain pending.

- `toToolDeclaration` and `declarationsEqual` now handle schema-data tools through canonical JSON. Serialized declarations and comparisons match the actual upstream functions for 53 tool pairs, including ordering and error precedence. Full schema types, general extension objects and complete mutable identity semantics remain pending; the replay suite is complete.

- `getToolStateChanges` preserves upstream filter/map sequencing, last-definition lookups and duplicate/output order for schema-data tools. All 79 direct upstream cases pass; the original changed-definition and unchanged-state assertions are included in the replay suite. Mutable adapters and full schema types remain pending.

- `hasToolRedefinitions` now retains shared tool references and preserves lazy comparison/error behavior. Both history predicates match upstream for 61 histories on one and four threads. All nine original replay-suite cases pass; full schema-object integration remains open.

- Canonical agent tool/result types retain all upstream fields and use typed callback handles. Explicit `AgentTool` to `Tool` projection completes the replay suite’s executable declaration case without invoking callbacks. Schema/argument inference, validation, abort integration and execution lifecycle remain pending. A checked-in Bend loader patch fixes cross-package shared-module namespaces; both import orders and cycle rejection pass regression tests.

- Full model/compatibility/routing data records now retain the source fields and optionality. Model compatibility is indexed by the API discriminator. Eleven interface field sets, all known/custom API construction paths and three rejected API/configuration combinations are checked. Model registry and codecs remain pending; no additional upstream suite is marked complete.

- Model thinking support/clamping and runtime identity/API predicates now match original upstream helper bodies across 212 thinking configurations, 64 model pairs and 30 API checks. Two standalone max-thinking cases are ported; catalog/provider cases and static API narrowing remain open.

- `calculateCost` now updates and returns the original nested cost reference. All five charges match upstream for 159 cases on one and four threads, including tier order/boundaries, one-hour writes and extreme numbers; alias mutation is checked separately. The original models-runtime pricing-tier case passes. The remaining runtime suite and provider integration remain pending.

- Abort-state foundations now preserve first settlement, preflight failures, falsy supplied reasons and shared reason identity. Native tests pass on one and four threads, including 100 competing abort calls; the existing shared-reference, deferred and callback concurrency checks also pass. EventTarget listeners, cleanup, dependent/timeout signals, full default-error behavior and model-store integration remain pending. No upstream suite status changes for this prerequisite.

Build issue: the current Bend compiler consumes roughly 10 GB compiling the combined application. Keep the generated C entry-point adaptation explicit in `scripts/entry.py`; never hide compiler changes in generated artifacts.

The final port must replace the prototype libcurl/ICU/custom C dependencies with pure Bend implementations and missing Bend primitives. Bootstrap demonstrations above do not satisfy this requirement. `scripts/build-pure.sh` compiles canonical Bend tests without prototype effects, generated-entry-point patching, libcurl or ICU.

- Deferred observations now support atomic cancellation and waiter removal; abort observations use the same primitive. Tests cover 128 settlement races, stale handles beyond a 64-bit counter carry, optional settled values and 1,000 cancellations with no retained abort observers. Existing generic/assistant stream assertions remain unchanged in meaning. EventTarget semantics and the pi abort-race utility remain pending; no additional upstream suite is marked complete.

- A compiler-level `Chan.same` primitive now supports pure `Ref.same`/`Callback.same` identity checks. Native checks pass on one and four threads; JS-backend and negative type checks pass too. The listener reference traces also establish Node traversal behavior; their native comparison is described below. This primitive does not mark EventTarget or any additional upstream suite complete.

- The internal listener registry now matches 36 Node traversal traces on one and four threads, including twelve explicit identity/reentrancy/mutation cases and 24 seeded sequences. Native checks cover concurrent registration/once/removal, UTF-16 names, option preservation, pre-invocation skip/stop and retired-node cleanup. EventTarget fields/flags, error handling, signal options and abort integration remain pending; upstream suite statuses are unchanged.

- Shared Node Event state now matches 17 host traces and 147 property checkpoints on one and four threads. Native tests retain event/target identity, redispatch guards, throw cleanup, caller ownership and exact timestamps. `WebEvent` and `eventType` are explicit Bend naming adaptations. Clock-backed construction is described below; EventTarget integration and error reporting remain pending, and no additional upstream suite is complete.

- Exact monotonic ticks now back a pure-Bend runtime clock and Event constructor. All 276 interval bit-pattern comparisons pass, along with native one/four-thread and JS-backend clock/constructor checks. Startup origin sharing, EventTarget integration and broader clock/timer APIs remain pending; no additional upstream suite is complete.

- The typed EventTarget dispatcher now runs 36 Node traversal cases plus ten callback/flag/recursion/error-order traces on one and four threads. Actual callbacks receive shared target/event identities; failures preserve later callbacks and enqueue reports in order. Automatic next-tick delivery, promise/object listeners, complete signal options and abort integration remain pending. No additional upstream suite is marked complete.

- AbortSignal now shares the typed EventTarget dispatcher while retaining its full receiver/event-target identity. Twenty-four Node event traces pass on one and four threads, covering settled-state visibility, trust, reentrancy, listener options/removal, explicit dispatch, retained events and error payload/order. One hundred concurrent abort attempts additionally dispatch exactly once. Existing abort-state assertions and 46 dispatcher traces pass unchanged in behavior. Full signal APIs, automatic error delivery, Promise scheduling and lifetime reclamation remain pending; no additional upstream suite is complete.

- Callable/null `onabort` getter/setter behavior now matches 32 Node traces on one and four threads, including stable first-assignment position, replacement/clearing during dispatch, separate listener registrations, original callback identity, actual aborts and errors. Existing abort-event and abort-state tests remain passing. Dynamic non-callable property values, descriptors, listener-count hooks and automatic error delivery remain pending; upstream suite statuses are unchanged.

- Canonical agent declarations now include all ten event variants, extensible messages, queue/thinking modes, the shared tool-call alias and both tool-hook result records. Source field/optionality checks, native one/four-thread identity/payload tests and negative payload-type compilation pass. Event emission, hook merging, state accessors and loop behavior remain pending; no upstream suite status changes.

- The agent loop now has typed internal tool outcomes and a pure-Bend hook-result merge helper. It matches the pinned upstream merge expression across 108 cases on one/four threads, preserving absent-return identity, new-object allocation, nullish/falsy distinctions and shared payload references. Hook execution, dynamic extra properties, errors, event ordering and loop scheduling remain pending; upstream suite statuses are unchanged.

- Agent tool-batch policy now matches 126 upstream execution-mode cases and 121 termination cases on one/four threads. It preserves whole-batch sequential overrides, first-definition lookup, parallel defaults and nonempty/all-explicit-true termination. Native checks cover live tool/call/result updates and prohibit tool execution during selection. Actual scheduling, event ordering and agent-loop integration remain pending; no upstream suite is newly complete.

- The agent loop now exposes a typed event sink and ports both tool-event emission helpers. Five original-source success/failure traces pass on one/four threads; explicit gates verify awaited callbacks, start-before-end ordering, failure propagation and shared message/result identity. Global Promise scheduling, tool-result construction, subscriptions and full loop execution remain pending; no additional upstream suite is complete.

- Tool-result artifact construction now retains canonical fields/shared payloads and uses Unix wall-clock timestamps through a small compiler primitive plus pure-Bend signed conversion. All 146 conversion vectors, native one/four-thread clock/artifact checks and JS clock lowering pass. A compiler identifier fix also covers punctuation/Unicode module paths. Full Date APIs, dynamic result normalization and complete loop execution remain pending; upstream suite statuses are unchanged.

- Tool-call argument preparation now preserves original/new call identity, post-callback comparisons and metadata, and recoverable error identity. Six upstream helper comparisons and a distinct raw/output type test pass on one/four threads. Schema validation, dynamic extra properties, callback receiver/scheduling semantics and full pipeline integration remain pending; upstream suite statuses are unchanged.

- Agent context and hook/turn-update contracts now preserve shared object/array identities and distinct raw/validated argument types. Run-context initialization copies its message array while retaining elements and tools. Agent-end/turn-end arrays now use the same shared representation. Source field checks, native one/four-thread alias/copy/ownership tests and negative validated-argument typing pass. Full arrays, state accessors, configuration and loop execution remain pending; upstream suite statuses are unchanged.

- Provider request, stream and simple-stream option declarations now retain inherited fields/optionality, typed lifecycle callbacks, shared maps and closed option variants. Source checks, native one/four-thread projection/identity checks and invalid-variant compilation pass. Fetch/telemetry/signal runtime integration, provider behavior, defaults and dynamic fields remain pending; upstream suite statuses are unchanged.

- The agent loop configuration now retains all 34 inherited fields and typed callback contracts. Its stream function requires normalized transcript input and the canonical assistant event stream. Source field checks, native one/four-thread identity/projection checks, and invalid context/error-return compilation pass. Callback policies, provider/runtime integration, state accessors and full loop behavior remain pending; upstream suite statuses are unchanged.

- Next-turn update application now matches 195 cases from the actual `runLoop` source block on one/four threads. It preserves absent/empty-update distinctions, config shallow copies, context/model/message-array identity, thinking-off removal and original-state immutability. Hook invocation, steering polls, dynamic properties and full turn orchestration remain pending; upstream suite statuses are unchanged.

- Next-turn preparation now awaits the configured callback before applying its update, passes the shared completed-turn context and preserves callback-side mutations on success or failure. Five original-source comparisons pass on one/four threads, with explicit settlement gates and identity/count checks. Queue polling, turn events, receiver semantics, global Promise scheduling and full loop orchestration remain pending; upstream suite statuses are unchanged.

- Steering/follow-up callback polling and the post-preparation steering guard now match 24 original-source cases on one/four threads. Nonempty pending arrays skip the second poll, returned arrays/messages retain identity, callbacks are awaited, and errors propagate unchanged. Tests include shared-array mutation during callback suspension and forbid invoking the opposite queue. Queue storage, complete turn integration and global Promise scheduling remain pending; upstream suite statuses are unchanged.

- Completed-turn stop decisions now connect to awaited end-event emission or steering polling, matching six original-source traces on one/four threads. Tests gate each callback stage, preserve exact context/pending/end-array identities, observe callback-side queue replacement, and propagate hook/event/queue failures without later actions. Main-loop construction and execution, follow-up orchestration and global Promise scheduling remain pending; upstream suite statuses are unchanged.

- The assistant-request transform/conversion prefix now matches ten original-source traces on one/four threads. It awaits both callbacks, captures the original message array, observes converter replacement after transformation, retains supplied/output identities and context mutations, and skips conversion on transform failure. Normalization, key resolution, provider dispatch and stream handling remain pending; upstream suite statuses are unchanged.
