# Upstream test parity

The behavioral target is the pinned pi-mono revision recorded in `upstream-inventory.json`. Port the upstream assertions, fixtures, failure cases and regression scenarios with each component. Additional local smoke tests and successful live model calls do not establish parity.

The inventory includes every discovered upstream test/spec source, including packages whose applicability still needs review. `pending` means unported, `partial` means some assertions have native equivalents, and `ported` requires every applicable assertion to pass. A suite may be excluded only with a written scope reason. JavaScript extension loading is excluded by the user's request, but extension hooks, lifecycle and behavior remain requirements for Bend extensions.

Check the pinned source and inventory with `python3 scripts/test-inventory.py`. Changes to upstream source hashes require review. Never change expectations solely to make the Bend implementation pass.

`truncate_differential.py` compares native results with upstream code through a test-only TypeScript oracle. This is supplemental coverage, not a substitute for porting the named upstream tests. Production code does not import or execute TypeScript.

The truncation suite exposed isolated UTF-16 surrogate handling, which is now preserved by JSON and replaced with U+FFFD when a partial UTF-8 tail is decoded. All nine upstream truncation tests have native equivalents, including the exhaustive and seeded fuzz cases. The grep line helper counts UTF-16 units. Terminal tests still require a virtual-terminal harness and native editor/rendering implementation; API-specific Unicode sanitization remains a separate provider requirement.

The five generic event-stream cases are ported in `packages/ai/test/event-stream.bend`, retaining their names and assertions. `sh tests/event-stream.sh` runs them on one and four runtime threads, alongside four supplementary lifecycle and explicit resource-handle regressions. Exact integer fixtures use U32 as the generic event type, and the string-result fixture remains a separate instantiation. This test suite does not cover all async-generator protocol methods or JavaScript scheduler behavior; those module gaps remain explicit in `packages/ai/README.md`.

All nine system-message-replay cases are ported, including declaration projection from an executable tool. `sh tests/transcript.sh` runs the nine original cases plus native text and transport-tool edge cases. `python3 tests/record_vectors.py` checks native persistent dictionaries. Replay fixtures use plain JSON Schema values. Dynamic-object/identity supplemental tests were retired during the native Bend migration; see `docs/native-bend.md`. Full schema builders and validation remain unported.

The state-change case is implemented in `packages/ai/test/tool-state.bend` and invoked by the replay test entry point. It preserves both original assertions: changed definitions produce an ordered removal/addition, and identical states produce empty changes. Its empty-object schema fixture matches the pinned TypeBox output; it does not claim builder/validator parity. `python3 tests/tool_state_vectors.py` directly compares 72 state pairs with upstream, including the original inputs and duplicate-definition regressions.

The combined history case preserves the original transcript, additive and redeclared-message assertions. `python3 tests/tool_history_vectors.py` additionally compares both history predicates directly with upstream for 55 cases on one and four threads. JS-only invalid-schema/reflection fixtures are retired. Native schemas are immutable data, and structural equality is tested independently.

The executable declaration case uses `agent.AgentTool` with typed reusable callbacks and an explicit base-tool projection, preserving the three original equality assertions. An additional counter check ensures projection never invokes preparation or execution. The nine-case suite passes on one and four threads. TypeBox static relationships, schema validation and agent execution lifecycle remain open independently of this suite.

The pi-ai max-thinking suite is partial: `packages/ai/test/model-thinking.bend` preserves the two standalone model-metadata cases and their original fields/assertions. Catalog lookups and Codex payload checks remain unported. `python3 tests/model_metadata_vectors.py` compares the original upstream leaf helper bodies with Bend across thinking, clamping, identity and API matching cases; the TypeScript extraction/type erasure is test-only.

The models-runtime suite is partial: `packages/ai/test/model-cost.bend` ports the original request-wide pricing-tier case and all its charge assertions. `python3 tests/model_cost_vectors.py` also compares 159 complete results with the unmodified upstream cost function and checks the returned cost value on one and four threads. Registry/provider/auth cases remain unported. Costs are immutable values; no nested reference disposal is required.


The native cleanup preserves the inventory statuses: 3 ported, 3 partial and 543 pending suites. `sh tests/native-agent.sh` replaces the former supplemental API-key/context/response/queue/stop/preparation/emission/truncation identity-and-mutation harnesses with native request, hook, failure and snapshot checks. This is not a claim that every former supplemental scheduling scenario has been retained. The complete upstream agent-loop suite remains pending.

Other retained supplemental checks include 84 tool selections, 126 execution policies and 121 termination cases, 74 before-hook decisions, 195 turn updates, 108 result merges, 21 completion cases, 159 pricing vectors, 760 primitive coercions, 418 schema-type coercions, 2,670 type predicates, 7 schema-type filters, 50 dictionary sequences and 115 typed sampling configurations. These counts describe vectors, not fully ported upstream suites. JSON checks cover 892 quoting inputs and 114 native structured values. Native structural equality tests explicitly cover reordered dictionaries and ordered arrays.


After resuming the full port, `packages/agent/test/tool-finalization.bend` adds nine native scenarios for the actual hook invocation/finalization path, with channel gates checking awaited settlement. `agent-event-stream.bend` checks nonempty/empty final histories, buffered ordering and ignored late pushes. Both run through `tests/native-agent.sh` on one/four threads. They supplement the still-pending full `agent-loop.test.ts` port and do not change its status.


`tests/tool_update_scope.py` adds supplemental coverage for invocation-scoped update tracking. It executes the pinned `executePreparedToolCall` helper for failure-selection/late-update checks, runs native scope transitions and 256 concurrent completions on one/four threads, and verifies that copying a completion ticket is rejected by the compiler. The full `agent.test.ts` cases “should ignore tool updates after the tool execution settles” and “should ignore a settled parallel tool update while another tool is still running” still require the agent/executor and remain unported.


`packages/agent/test/tool-execution.bend` checks prepared execution with delayed/immediate update delivery, original versus validated arguments, tool/listener error precedence, late callbacks and resource drain. Its eight cases use channels rather than timing assumptions. `tool-execution-stream.bend` composes the production execution helper, update emitter, after-tool hook, termination policy, result-message emission and canonical stream, checking ordered events and final history. These run on one/four threads through `tests/native-agent.sh`; complete public-agent test cases still require loop orchestration and remain pending.
