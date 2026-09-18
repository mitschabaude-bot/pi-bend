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
- Upstream tests are inventoried by source hash: 549 suites discovered across pi-mono, with applicability review still needed for auxiliary packages. The truncation and generic event-stream suites have full native ports; regional-indicator width and system-message-replay coverage are partial; the remaining suites are pending. See `tests/UPSTREAM.md` for the acceptance rules and current gaps.
- Pure-Bend runtime foundations: unsigned/wide arithmetic passes 272 independent vectors; binary64 addition/subtraction/multiplication/division, comparison and integer conversion pass 1,077 vectors covering signed zero, subnormals, rounding ties, cancellation, overflow, infinities and NaNs. These modules use no custom C/JS effects. Decimal parsing and complete integration remain open; shortest formatting is tested separately below.
- `packages/ai/src/types.bend` starts the typed library port with faithful content, usage, model-cost records and stop reasons. Numeric fields use binary64, and optional values remain distinct. The module is partial; the full Model/schema/options contracts and declaration comparison remain unported.
- Pure-Bend shared references, deferred results and reusable callback handles pass native concurrency tests. These support live stream-event references and runtime callback values. Automatic lifetime reclamation remains open; explicit disposal is currently required.

- Generic `EventStream<T, R>` now passes all five upstream regression cases on one and four runtime threads, plus four native lifecycle/shared-identity cases. Buffered delivery, waiting-consumer FIFO, per-iterator next serialization and distinct final-result settlement have canonical typed implementations. The module is still partial: return/throw, recoverable callback failures, scheduler equivalence and downstream integration remain pending.

- Canonical user/assistant/tool-result messages and all twelve assistant-event variants now have typed declarations, including shared live message/content references and opaque caller-typed payloads. The assistant stream factory passes native tests for all variants, success/error extraction, setup failure and retained identities on one and four threads. These tests supplement existing upstream coverage; schema relationships, dynamic-value integration, serialization and provider composition remain open.

- Raw/normalized contexts, system messages and generic tool declarations now have canonical types. Context normalization, prompt rendering, system replay and collapse pass six of nine upstream replay-suite cases, plus native separator/ordering/identity and transport-tool regressions. Own-property records and insertion-ordered maps each pass 50 JavaScript differential mutation sequences. Declaration comparison, schema validation and custom-role integration remain pending.

- Exact unsigned arbitrary-precision arithmetic now passes 179 independent vectors plus power and input cases, including values needed for extreme binary64 exponents. Integer decimal parsing/formatting is implemented in pure Bend. Schema declaration serialization/comparison remains pending.

- Pure-Bend shortest binary64 formatting matches JavaScript on 1,092 bit patterns, including dense subnormal cases, exponent boundaries and decimal midpoint ties in both directions. JSON numeric spelling also handles non-finite values and signed zero. Decimal parsing, full JSON/schema serialization and performance evaluation remain pending.

- Explicit canonical `JsonValue` serialization matches JavaScript on 892 string cases and 114 structured values, with native checks for 2,000 nested arrays and UTF-16-equivalent map keys. Arbitrary dynamic-value/schema serialization and typed message/tool wire codecs remain pending.

Build issue: the current Bend compiler consumes roughly 10 GB compiling the combined application. Keep the generated C entry-point adaptation explicit in `scripts/entry.py`; never hide compiler changes in generated artifacts.

The final port must replace the prototype libcurl/ICU/custom C dependencies with pure Bend implementations and missing Bend primitives. Bootstrap demonstrations above do not satisfy this requirement. `scripts/build-pure.sh` compiles canonical Bend tests without prototype effects, generated-entry-point patching, libcurl or ICU.
