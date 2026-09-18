# Port status

The full-port goal resumed after the native Bend cleanup on 2026-09-18. See [native-bend.md](native-bend.md) for the approved representation decisions. The native cleanup replaces earlier object-compatibility milestones; Git history retains their implementation history.

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
- Native library data now uses immutable Bend values and explicit returned updates. Structural tool equality and immutable event snapshots are approved adaptations. The JS reflection/dynamic-object and DOM event compatibility layers have been removed; historical milestone claims for them are retired. See [native-bend.md](native-bend.md).
- Current supplemental coverage includes typed option/configuration projection, pricing, schema primitive coercion, transcript/tool history, agent policy and request/event sequencing. These checks do not complete the full agent or validation suites. See [tests/UPSTREAM.md](../tests/UPSTREAM.md) for the current commands and counts.

- Resumed canonical agent integration: after-tool finalization invokes and awaits hooks, applies overrides and converts hook failures to error results. Nine native scenarios pass with channel-gated async checks. The agent event-stream factory now settles message histories on agent_end and owns its callback cleanup. Public loop entry points, tool execution/update tracking, preparation/validation and batch scheduling remain unfinished; upstream suite statuses are unchanged.

- Added a native update scope for each tool invocation, with affine completion tickets, late-update rejection, failure propagation and separate resource-drain settlement. Source-oracle checks confirm upstream failure selection; native checks pass on one/four threads, including 256 concurrent completions. Event forwarding and executor integration remain pending. No upstream suite statuses were promoted.

- Prepared tool execution now composes the executor, invocation-scoped update forwarding, ordered emission starts, asynchronous listener settlement and typed error conversion. Eight gated scenarios pass on one/four threads. A separate composed test runs actual execution through after-tool finalization, termination policy, result-message emission and canonical agent-stream settlement. Validated preparation, batch scheduling and public loop entry points remain pending; upstream suite statuses are unchanged.

- Native tool preparation now composes lookup, optional adaptation, required injected validation, before-hook updates and cancellation/blocking with actual prepared execution. Twelve native pipeline cases cover order, failure precedence, first-match selection, context updates and no revalidation after hook changes. The canonical schema validator, batch scheduling and public loop entry points remain pending; upstream suite statuses are unchanged.

- Added a pure-Bend typed schema evaluator for primitive kinds, structural constants/enumerations, allOf/anyOf/oneOf/not, nested object properties/required/additional properties and array tuple/item constraints. It passes 930 checks against pi-ai's pinned TypeBox 1.3.27 on one/four threads. Native fixtures cover ordinary dictionary keys, missing versus explicit null, immutable inputs, exclusive unions and non-finite numbers. JSON-schema compilation, remaining constraints, references, diagnostics and integration with coercion/tool validation remain pending; this does not promote the validation suite.

- Extended native schema evaluation with inclusive/exclusive numeric bounds, item/property counts and contains-count bounds. The expanded TypeBox differential set contains 2,700 checks on one/four threads, plus native edge fixtures. String-length constraints require the pinned dependency’s grapheme behavior; those and uniqueItems (pending a signed-zero behavior decision), multipleOf, schema loading, diagnostics and full validation integration remain pending. Upstream suite statuses are unchanged.

- Added a native core JSON-schema loader returning typed errors with schema paths. Loaded declarations feed the existing evaluator directly; 1,980 TypeBox comparisons, 16 unsupported-keyword rejections and native malformed/nested-path tests pass on one/four threads. Unsupported keywords are rejected explicitly, including nested alternatives. Object/array cross-keyword behavior uses the whole schema rather than field order. Remaining vocabulary, references, diagnostics and normalization/coercion integration remain open; upstream suite statuses are unchanged.

- Connected collection-count and contains constraints to the native schema loader. Count limits and accumulated counts use compact exact integers, avoiding machine-word overflow and unary allocation for large declarations. Expanded typed/loaded comparisons cover 3,150 cases each; native checks cover invalid bounds and exact conversion through the largest finite binary64 integer. Full coercion, references, remaining schema vocabulary and tool-validation integration remain pending.

- Connected native schema checking to immutable optional-null normalization. Required, nullable and referenced null fields survive; optional non-nullable fields are omitted, and declared nested properties/items are traversed. The source-derived helper/cache oracle passes 244 comparisons on one/four threads. A boolean-schema cache quirk remains an explicit pending behavior decision, and unsupported nullability checks return errors. Recursive coercion, full validation/reference handling and tool-entry integration remain pending.

- Added native recursive plain-schema coercion: ordered schema composition, original-first union checks, isolated candidates, scalar coercion and nested object/array traversal. All 388 source-derived comparisons pass on one/four threads, including retained caller inputs and independent failed candidates. Boolean-cache behavior and unsupported union constraints remain explicit gaps. Full conversion/normalization/validation orchestration, references, diagnostics and public tool-validation entry points remain pending.
