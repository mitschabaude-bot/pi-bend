# Upstream test parity

The behavioral target is the pinned pi-mono revision recorded in `upstream-inventory.json`. Port the upstream assertions, fixtures, failure cases and regression scenarios with each component. Additional local smoke tests and successful live model calls do not establish parity.

The inventory includes every discovered upstream test/spec source, including packages whose applicability still needs review. `pending` means unported, `partial` means some assertions have native equivalents, and `ported` requires every applicable assertion to pass. A suite may be excluded only with a written scope reason. JavaScript extension loading is excluded by the user's request, but extension hooks, lifecycle and behavior remain requirements for Bend extensions.

Check the pinned source and inventory with `python3 scripts/test-inventory.py`. Changes to upstream source hashes require review. Never change expectations solely to make the Bend implementation pass.

`truncate_differential.py` compares native results with upstream code through a test-only TypeScript oracle. This is supplemental coverage, not a substitute for porting the named upstream tests. Production code does not import or execute TypeScript.

The truncation suite exposed isolated UTF-16 surrogate handling, which is now preserved by JSON and replaced with U+FFFD when a partial UTF-8 tail is decoded. All nine upstream truncation tests have native equivalents, including the exhaustive and seeded fuzz cases. The grep line helper counts UTF-16 units. Terminal tests still require a virtual-terminal harness and native editor/rendering implementation; API-specific Unicode sanitization remains a separate provider requirement.

The five generic event-stream cases are ported in `packages/ai/test/event-stream.bend`, retaining their names and assertions. `sh tests/event-stream.sh` runs them on one and four runtime threads, alongside four supplementary lifecycle/shared-identity regressions. Exact integer fixtures use U32 as the generic event type, and the string-result fixture remains a separate instantiation. This test suite does not cover all async-generator protocol methods or JavaScript scheduler behavior; those module gaps remain explicit in `packages/ai/README.md`.

All nine system-message-replay cases are ported, including declaration projection from an executable tool. `sh tests/transcript.sh` runs the nine original cases plus native text and transport-tool edge cases. `python3 tests/record_vectors.py` uses JavaScript only as an oracle for own-property and insertion-ordered Map mutation. The replay fixtures use the verified TypeBox 1.3.27 empty-object data shape; the schema builders and validators remain unported.

The state-change case is implemented in `packages/ai/test/tool-state.bend` and invoked by the replay test entry point. It preserves both original assertions: changed definitions produce an ordered removal/addition, and identical states produce empty changes. Its empty-object schema fixture matches the pinned TypeBox output; it does not claim builder/validator parity. `python3 tests/tool_state_vectors.py` directly compares another 79 state pairs with upstream, including the original inputs and duplicate/error-order regressions.

The combined history case preserves the original transcript, additive and redeclared-message assertions. `python3 tests/tool_history_vectors.py` additionally compares both history predicates directly with upstream for 61 cases on one and four threads. Repeated same-reference invalid schemas must still throw via the native error result, while first declarations and entries after a detected redefinition remain unvalidated.

The executable declaration case uses `agent.AgentTool` with typed reusable callbacks and an explicit base-tool projection, preserving the three original equality assertions. An additional counter check ensures projection never invokes preparation or execution. The nine-case suite passes on one and four threads. TypeBox static relationships, schema validation, general live-object semantics and agent execution lifecycle remain open independently of this suite.

The pi-ai max-thinking suite is partial: `packages/ai/test/model-thinking.bend` preserves the two standalone model-metadata cases and their original fields/assertions. Catalog lookups and Codex payload checks remain unported. `python3 tests/model_metadata_vectors.py` compares the original upstream leaf helper bodies with Bend across thinking, clamping, identity and API matching cases; the TypeScript extraction/type erasure is test-only.
