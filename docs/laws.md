# Laws and proof coverage

Gregor authorized agent-authored general specifications on 2026-09-20. Laws must be honest attempts to capture intended behavior, independent of implementation accidents. Prefer universally quantified properties that imply upstream examples. Meaningful boundaries, such as an empty queue, are valid laws; arbitrary regression inputs remain tests. Never weaken a contract to make a proof pass. Laws accompany production implementations; each milestone states which behavior it establishes.

`LAWS.bend` is the public specification entry point, importing component contracts from `laws/`; `PROOF.bend` imports their implementations and supporting lemmas from `proofs/`. `PROOF.bend` must check with a compiler supplying its imported runtime primitives (see the current command below). The last completed root gate reports `All terms check, with 36 unsafe annotations.` (the gate accepts any `All terms check` summary; the instantiation count is not evidence). The gate audits 21 exact existing source declarations: callback factory, DNS search/address/transport loops, random-index retry, file-fold driver, event-stream/HTTP/SSE drivers, schema comparison, JSON encoding, schema-to-JSON conversion, strict-schema traversal/nullability (now inside `constrained-sampling.bend`), Responses processing and the SSE cursor. The difference between source declarations and the compiler summary includes template instantiation accounting. Laws and proofs contain no `@unsafe`; this does not establish termination or correctness of those imported routines. The summary and exact declarations are retained in the validation record; unexpected declarations or summaries fail the gate. The laws file alone intentionally fails because its obligations are open. The native regression entry point runs `scripts/check-proofs.py` before its executable suites. The compiler is trusted: mutation tests and deliberately broken/open/missing-proof checks have been removed from the workflow at Gregor’s request. Earlier mutation records below are historical evidence, not ongoing requirements.

## Coverage summary

Current as of 2026-09-22. The gate is `python3 scripts/check-proofs.py`, which type-checks `LAWS.bend` and `PROOF.bend` with the installed native toolchain (`build/bend-native-toolchain/bend2/main.ts`, or `BEND` when set) and audits the exact set of `@unsafe` source declarations the closure reaches. Each law file constrains the module it is named after; a proof file of the same name in `proofs/` supplies the proofs, with shared lemmas in `proofs/string-equality.bend`, `proofs/list-reverse.bend` and `proofs/absurd.bend`.

| Law file | Laws | Constrains |
| --- | ---: | --- |
| `laws/abort.bend` | 2 | `packages/runtime/src/abort.bend` |
| `laws/agent-loop.bend` | 22 | `packages/agent/src/agent-loop.bend` (execution mode, termination, hooks, batches, stream lease) |
| `laws/agent.bend` | 36 | `packages/agent/src/agent.bend` (state, queues, events, owner, continue planning) |
| `laws/bounded.bend` | 6 | `packages/runtime/src/bounded.bend` |
| `laws/calendar.bend` | 1 | `packages/runtime/src/calendar.bend` |
| `laws/compaction.bend` | 4 | `packages/coding-agent/src/core/compaction/plan.bend` |
| `laws/connection-driver.bend` | 28 | `packages/runtime/src/connection-driver.bend` |
| `laws/dns-message.bend` | 25 | `packages/runtime/src/dns-message.bend` |
| `laws/dns-resolver.bend` | 9 | `packages/runtime/src/dns-resolver.bend` |
| `laws/dns-transport.bend` | 13 | `packages/runtime/src/dns-transport.bend` |
| `laws/f64.bend` | 8 | `packages/runtime/src/f64.bend` (comparison outcomes, finiteness, NaN-propagating extrema) |
| `laws/fetch.bend` | 9 | `packages/runtime/src/fetch.bend` |
| `laws/fifo.bend` | 3 | `packages/runtime/src/fifo.bend` |
| `laws/hosts.bend` | 14 | `packages/runtime/src/hosts.bend` |
| `laws/http-exchange.bend` | 6 | `packages/runtime/src/http-exchange.bend` |
| `laws/http-message.bend` | 11 | `packages/runtime/src/http-message.bend` |
| `laws/http-response.bend` | 35 | `packages/runtime/src/http-response.bend` |
| `laws/json.bend` | 7 | `packages/ai/src/utils/json.bend` |
| `laws/list-interleave.bend` | 4 | `packages/runtime/src/list-interleave.bend` |
| `laws/openai-client.bend` | 41 | `packages/ai/src/api/openai-client.bend` |
| `laws/openai-completions.bend` | 3 | `packages/ai/src/api/openai-completions.bend` (getCompat as field-wise override of detection; detection never enables opt-in features) |
| `laws/openai-responses-stream.bend` | 9 | `packages/ai/src/api/openai-responses-stream.bend` |
| `laws/openai-responses.bend` | 19 | `packages/ai/src/api/openai-responses.bend` |
| `laws/openai-sse.bend` | 12 | `packages/ai/src/api/openai-sse.bend` |
| `laws/ordered-map.bend` | 5 | `packages/runtime/src/ordered-map.bend` |
| `laws/provider-retry.bend` | 18 | `packages/ai/src/utils/provider-retry.bend` |
| `laws/record.bend` | 7 | `packages/runtime/src/record.bend` |
| `laws/resolver-config.bend` | 25 | `packages/runtime/src/resolver-config.bend` |
| `laws/sha256.bend` | 1 | `packages/runtime/src/sha256.bend` |
| `laws/simple-options.bend` | 7 | `packages/ai/src/api/simple-options.bend` |
| `laws/sse.bend` | 7 | `packages/runtime/src/sse.bend` |
| `laws/string.bend` | 6 | `packages/runtime/src/string.bend` |
| `laws/text.bend` | 5 | `packages/runtime/src/text.bend` |
| `laws/thinking-levels.bend` | 8 | `packages/ai/src/utils/thinking-levels.bend` |
| `laws/timer.bend` | 5 | `packages/runtime/src/timer.bend` |
| `laws/transcript.bend` | 14 | `packages/ai/src/utils/transcript.bend` |
| `laws/transform-messages.bend` | 20 | `packages/ai/src/api/transform-messages.bend` |
| `laws/transform-tool-results.bend` | 11 | `packages/ai/src/api/transform-tool-results.bend` |
| `laws/url.bend` | 32 | `packages/runtime/src/url.bend` |
| `laws/utf8.bend` | 6 | `packages/runtime/src/utf8.bend` |
| `laws/uuid.bend` | 3 | `packages/ai/src/utils/uuid.bend` (UUIDv7 ordinary ids strictly ordered across followers and clock rollback) |
| `laws/validation.bend` | 7 | `packages/ai/src/utils/validation.bend` |
| `laws/x509.bend` | 1 | `packages/runtime/src/x509.bend` (trust anchors) |
| **Total** | **513** | |

The sections below are the dated history of how this coverage was built; earlier sections keep the file names they used at the time.

## FIFO sequence contracts

The specification observes a queue through its public `drain` operation and models removal using ordinary list head/tail semantics. All laws quantify over every Data element type. Enqueue/dequeue laws cover arbitrary queues, including every incoming/outgoing list arrangement, rather than selected reachable examples.

| Law | Proved contract | Implementation |
| --- | --- | --- |
| `fifo_empty` | A newly created queue contains no values. | `fifo.new`, `fifo.drain` |
| `fifo_enqueue` | Enqueue preserves the entire previous sequence and appends exactly the supplied value. | `fifo.enqueue`, `fifo.drain` |
| `fifo_dequeue` | Dequeue returns the sequence's first value and retains exactly its tail; empty queues return no value and remain empty. | `fifo.dequeue`, `fifo.drain` |

The proofs use structural induction for Base list append associativity, append's empty identity and reverse-accumulator distribution. The queue representation is inspected only in the proof. No unproved project assumptions, holes, unsafe proof definitions, foreign implementations or finite enumeration are used as proof evidence.

## Dictionary and string-set contracts

Seven dictionary laws quantify over every Data value type, arbitrary string keys, and arbitrary property lists (including lists with duplicate keys). Empty dictionaries return `None`; deletion makes lookup of the removed key return `None`; repeating deletion has no further effect; every nonmatching head entry retains its original name, value and position before the recursively filtered tail. The conditional survivor law requires evidence that string comparison returns false, not an assumed equivalence or a finite list of selected strings. Together these express deletion's absence, stability and survivor behavior. Structural induction proves the first two recursive properties; four supporting lemmas handle filtered heads and property lists.

Six string-set laws cover empty membership, membership after insertion, absence after removal, idempotent removal, idempotent insertion, and removal after insertion. Their proofs reuse the dictionary laws through the production wrapper. These proofs contain no unsafe annotations and do not invoke effectful runtime definitions.

The fifth dictionary law, `lookup_after_set`, proves that lookup returns the supplied value after either insertion or replacement, for every dictionary, key and value. Its proof uses string equality reflexivity and symmetry proved from Base's actual comparison definitions: structural induction on arbitrary-width words, then characters and strings. Those are general supporting facts, not assumptions about the comparator or finite character enumeration. The separate helper proofs live in `proofs/string-equality.bend`; no Base or production code changed.

Two further dictionary laws compare whole dictionary values: `set_overwrite` says two writes to the same key equal the final write alone; `remove_after_set` says removing a key after setting it equals removing it from the original dictionary. Both cover arbitrary original property lists, including duplicates, and arbitrary initial/final values. The equality includes entry sequence and surrounding values; it is stronger than comparing lookup at the written key. The set wrapper inherits insertion idempotence and removal-after-insertion through these proofs. These laws do not independently establish that a single write preserves every other key or its position.

The dictionary and set laws complement the queue contracts; the total including ordered-map, decoder and agent-owner laws below is 78 public contracts and 48 supporting lemmas. Lookup at other keys, insertion order, and unique-key preservation are not yet proved. `tests/record_vectors.py` remains: its 50 operation sequences exercise insertion, replacement, reinsertion, ordering and the separate ordered-map implementation, beyond this law set. None of those tests or upstream suite statuses are retired or promoted here.

## Ordered-map equivalence

Five laws compare `OrderedMap` with the dictionary API through its complete entry sequence: empty construction, lookup, set, remove, and arbitrary edit histories. `edit_sequence` quantifies over every finite sequence of writes/deletes, arbitrary initial maps, arbitrary keys and every Data value type. Its inductive proof composes the individual operation laws. The separate insertion implementation compares string arguments in the opposite order, so its equivalence proof uses the established string-equality symmetry theorem.

This proves collection parity for every operation history of the form exercised by `tests/record_vectors.py`, including mixed replacement/deletion/reinsertion. The differential test also checks an external insertion-order model and native execution; equivalence between two Bend implementations alone does not establish either of those, so the test remains. The laws apply to the map used by `packages/ai/src/utils/transcript.bend` for tool replay and declaration indexing, but do not prove transcript traversal or the map's `values` projection.

## Line-decoder chunk boundaries

Three laws specify empty chunks, chunk composition and chronological output continuation. For every pending decoder state and every pair of input lists, continuing collection after the first chunk equals decoding their concatenation. `continuation_output` separately proves that this continuation is exactly a fresh `decode` call on the retained decoder followed by concatenation of previous and newly emitted lines. Together these establish the usual streaming split/concatenation invariant for both final state and output, including empty chunks. They quantify over all U32 input values (a superset of bytes) and require no assumptions about the pending CR or UTF-8 content.

The proof uses structural induction over input lists and the existing collector, with proved reverse/append identities for the output accumulator. It treats `consume` as a state transition; therefore it does not independently prove UTF-8 decoding, CR/LF emission timing, boundary detection or SSE event assembly. `tests/line_decoder_vectors.py` retains its SDK oracle comparisons over chunk partitions, flushes and boundary detection, plus native execution. No upstream suite is promoted by these chunk laws.

## Finalization and SSE blank blocks

`flush_result` quantifies over every pending line-decoder state. It emits each pending line once and returns the initial decoder state: an empty reading buffer emits no line; a nonempty reading buffer emits its decoded contents; pending carriage-return state emits the before buffer and, when present, the after buffer in order. `repeated_flush` derives that a second flush emits nothing. These laws use the existing `line` byte-decoding function, whose UTF-8 semantics remain a separate obligation. They cover the repeated-flush invariant exercised by `tests/line_decoder_vectors.py`, without replacing that test's native execution or SDK comparisons.

Two SSE laws quantify over every event name, data list and diagnostic list: blank-block processing clears both pending buffers, and a second blank emits no event. This covers the approved diagnostic-retention change even for empty blocks. It does not discard the diagnostic lines attached to an emitted event; the laws concern the next decoder state. `tests/sse_decoder_vectors.py` retains its adapted SDK oracle for event fields, parsing and emitted diagnostic contents, which these laws do not yet specify. No production behavior changes in this milestone.

## Agent owner and transcript isolation

Six laws quantify over all nine generic agent types and arbitrary owned states. Enqueueing into either queue, applying any pure queue transformation, and draining a queue leave the entire `AgentState` unchanged. This includes transcript messages, model, thinking level, tools, streaming/current-message fields, pending tool IDs and errors. The queue contents and returned drain results remain governed by the separate queue contracts.

User-editable `applyChange` transitions preserve streaming status, current message, pending tool IDs and error for every change constructor. Message replacement produces exactly the supplied message list, and append preserves the whole prior sequence followed by the supplied message. These native immutable-value contracts capture meaningful upstream state assertions without copying JavaScript identity semantics.

The enqueue law implies the pure transition property behind pinned `packages/agent/test/agent.test.ts:658` (“should support steering message queue”) and `:668` (“should support follow-up message queue”): a queued message is not appended to the transcript. It does not claim the message was absent beforehand. The replacement/append laws correspond to assertions at lines 641–655. The IO owner still needs its existing integration tests: locks, lifecycle commit, asynchronous delivery and listener sequencing are outside these proofs. No upstream suite status is promoted and no integration test is removed.

## Agent message-event contracts

Five event laws quantify over arbitrary agent states, messages, event details and all eleven Data parameters of `processEvent`. Message start/update set the current partial message and preserve transcript history. Message end appends exactly the supplied message to history and clears the partial message. Agent end preserves history and clears the partial message, irrespective of its reported-message payload. Every event constructor preserves model, thinking level, executable tools and streaming status.

These contracts follow pinned `packages/agent/src/agent.ts:561–596`. In particular, agent end must not set the streaming flag to false; idle status is reached after listener settlement and owner finalization. The laws verify the pure reducer's behavior, not the timing or execution of listener settlement, tool execution, synchronization or event emission. Two additional laws reuse the generic string-set proofs: tool start leaves the tool-call ID present, and tool end leaves it absent regardless of result payload or failure flag. They quantify over arbitrary initial pending sets and arbitrary IDs, including already-present/absent IDs. These are membership guarantees, not a proof that other IDs remain unchanged.

Two finalization laws establish that `finishRun` clears streaming status, the current message and the pending-tool set while preserving the recorded error; it also preserves transcript history. This contrasts with `AgentEnd`, which does not declare the run idle. The laws do not establish that finalization is invoked at the correct time; listener settlement and lifecycle ownership still require integration evidence. Turn-error extraction and preservation of unrelated pending IDs remain proof gaps.

## DNS query construction

`creation_preserves_intent` quantifies over every request-options value, ID and question. Observing the constructed request recovers exactly those options (flags and complete optional EDNS value), ID and question. This law checks the pure construction boundary; it does not prove that the effectful search driver passes the intended options or that their wire encoding is valid. The DNS search integration fixture separately inspects every outgoing candidate and alias question across plain and explicit-option searches.

## Resolver request preparation

Two generic laws establish that request-policy preparation retains the entire parsed resolver-options value and rejects every report containing at least one diagnostic, preserving the complete diagnostic sequence. The runtime test independently checks request-field selection for all 512 supported feature subsets with duplicate flags and two numeric configurations, plus malformed/unknown-token rejection. These laws do not claim that transport, retry, rotation or reload settings are already consumed by the network driver.

## Configured resolver search

Two universally quantified laws establish that a prepared search plan retains the request policy and candidate cursor selected by its configuration, name, dot count and absolute-name flag. They cover this composition boundary; they do not prove the underlying search algorithm or effectful execution. Mutations that replace the request policy with defaults or discard the dot count must fail the corresponding proof. The live configured-search fixture independently checks transmitted bytes and candidate order, including no-TLD behavior, across native and Bun execution. Proof evidence records the checked source closure and negative controls.

The configuration acceptance boundary additionally rejects every nonempty option-diagnostic sequence for arbitrary option values and domains, retaining all diagnostics in order. This law covers the strict preparation consumed by OS configuration assembly, including diagnostics for earlier tokens whose values were later overridden. System-configuration proof evidence records the full gate and its added acceptance mutation. It does not decide acceptance policy for separate server, scope, hostname or file diagnostics.

## Abort result arbitration

Two laws quantify over arbitrary reason, failure and value types. A retained abort always determines the selected outcome, independently of the operation's result or cancellation state. Without an abort, every completed result is preserved exactly, including either its success payload or its failure payload. `abortable-datagram.recv` and `.send` use this pure arbitration after retiring their observers and joining their watchers. The same laws apply to packet results and send completion because they quantify over the result type. The laws prove selection at that final observation boundary; they do not prove IO race ordering or resource retirement. Proof evidence includes mutations that drop the reason or completed result.

## Relationship to pi and existing tests

The FIFO supports the pending-queue section of `packages/agent/src/agent.bend`, corresponding to `PendingMessageQueue` in pinned pi-mono `packages/agent/src/agent.ts:140`. Six pending-queue laws now establish initialization, enqueue order, changing mode without changing messages, clearing without changing mode, mode-dependent delivery, and the equivalence of `hasItems` with a nonempty message sequence. The delivery specification uses list head/tail semantics: All emits everything and empties the queue; OneAtATime emits exactly the oldest message, or nothing for an empty queue. Both preserve the mode.

Eight paired-queue laws cover enqueue, clear, mode changes and drain. Each operation has a selected-queue contract and an isolation contract: its effect matches the pending-queue operation, and the other queue stays unchanged. These apply to either queue kind and arbitrary initial states. The selected-queue contracts compose with the pending-queue laws; they do not merely assert that an operation equals itself.

These 17 public laws and nine supporting lemmas do not prove transcript isolation or asynchronous consumption. The upstream “should support steering message queue” and “should support follow-up message queue” tests assert transcript isolation, whose pure owner transition is now covered above; synchronized runtime execution remains an integration obligation. Paired initialization, `clearAll`, and combined `hasQueuedMessages` also remain outside this law set.

No upstream suite status changes and no existing tests are removed in this milestone. The agent-queue differential and integration tests cover larger contracts than these pure queue transitions. Future coverage entries should name the upstream assertion and the law that implies it before retiring a redundant unit case.

## UDP retry sequencing

Four laws specify `dns-udp-schedule` through an independent list model: the selected server order repeated for the requested number of rounds. Initialization must denote exactly that sequence. For every cursor, including arbitrary current and original lists, one step must return exactly the head and leave exactly the tail of its denoted sequence. Separate boundary laws require zero attempts and empty server lists to produce no attempt. All quantify over every Data server-entry type, preserving complete entries and duplicate values.

The implementation stores a current suffix, the original selected order and a remaining-round count, avoiding an expanded attempts-by-servers list. The proofs establish sequence preservation and exhaustion, not timeout calculation, correct rotation selection, DNS packet matching, retry classification, IO execution or compiler correctness. An inductive helper proves that repeating an empty list any number of times stays empty. Three gate mutations discard later rounds, discard pending servers, or prevent restarting; each remains well typed and must fail the relevant public law. Validation retains the full gate output.

## UDP timeout budgets

Six laws cover `dns-udp-timeout`: every representable duration is positive; normalization preserves any positive natural value; zero normalizes to one second; the first server's raw budget is undivided; both positions of a two-server configuration have equal complete budget results for every U32 timeout input. A positive duration stores its number of seconds beyond the first, so its positivity is structural. One helper proves two-server equality through either validation branch. A sixth law rejects conversion of every duration above the supported 40-second maximum, quantified over an arbitrary excess natural value. These are general invariants and meaningful boundaries, not selected regression equalities.

The three-server arithmetic and rejection of direct timeout inputs above 30 are additionally checked by compiled native/Bun execution against the pinned reference formula across the full parsed timeout domain, all valid original positions, and invalid boundaries. Those arithmetic/validation properties are not yet general theorems. Timing policy does not advance retries, select rotation, install a timer or define configuration acceptance for excess server entries. Proof evidence and compiled formula evidence keep those scopes distinct.

The checked seconds-to-milliseconds conversion is exercised with the compiled formula cases. Attempt-scope proof evidence includes an additional well-typed mutation that accepts an oversized duration. The nested deadline adapter uses the isolated timer candidate; its expiry/parent classification and resource retirement are integration-tested, not covered by that arithmetic law.

## UDP server-plan preparation

Three laws cover the `dns-udp-plan` boundary. For arbitrary Data server values and arbitrary lists, erasing assigned position metadata yields exactly the original accepted list or the defined layout error. Timing a located entry preserves its complete payload, position and supplied duration. A failed layout cannot become a partially accepted timed plan. The supported domain is one to three entries; empty and excess lists fail explicitly. This does not prove the complete timed-list traversal or every assigned position label.

Compiled composition checks exercise the preparation output through the existing rotation implementation and retry cursor, preserving server/budget associations across offsets and retry rounds, including duplicate payload values. Proof evidence and composition evidence distinguish generic invariants from executed cases. Four additional mutations lose payloads/positions or swallow layout errors and must be rejected by the gate.

## Checking the proof gate

`python3 scripts/check-proofs.py` checks the real proofs, rejects the open specification, and rejects removing the enqueue proof on which later proofs depend. It creates disposable copies of the local import closure with 57 independent mutations covering queue ordering/isolation, dictionary and set updates, ordered-map equivalence, line chunk accumulation/finalization, SSE blank-block behavior, owner state isolation, user-editable state transitions message-event reductions, pending-tool membership, finalization DNS request options and strict preparation. Validation records retain each exact mutation and diagnostic. Each mutated module must still typecheck, while the corresponding proof must fail. A failure may occur in a supporting lemma before the public contract: the duplicate-entry mutation, for example, invalidates the existing lookup proof construction even though lookup-after-set alone would still hold. Rejection demonstrates sensitivity of the proof gate, not that every failed proof falsifies its theorem; mutation testing is not the evidence for universal correctness. Python only launches the Bend checker and records diagnostics.

The initial FIFO validation record, expanded queue validation record, collection validation record, insertion validation record, update-composition validation record, ordered-map validation record, line-decoder validation record, finalization validation record, agent-owner validation record, agent-event validation record, tool/finalization validation record, DNS intent validation record, and resolver request validation record retain source/checker hashes and positive/negative outcomes. The installed checker is used without the compiler cache experiment. Proofs concern the checked pure definitions; compiler/runtime correctness, native execution, resource exhaustion and performance remain separate evidence obligations. No end-to-end pi correctness claim follows from these laws.

## Next coverage

The proof workflow is established across existing queues, collections, parser boundaries and agent owner/event transitions. Resume native DNS implementation with generic laws alongside new pure behavior; keep broadening existing proof coverage as those components are touched. Remaining obligations include turn-error extraction, preservation of unrelated keys/tool IDs, unique-key invariants, SSE field/content semantics, synchronized owner commits and event ordering. Preserve external reference tests and IO/concurrency/terminal/performance tests throughout this transition. The law milestones are not completion of the full port or of all existing correctness work.

### Generic IO boundary laws

`connection-plan.unavailable_does_not_connect` quantifies over arbitrary resolution/context types and values, error reason and affine result types, family preference, and an arbitrary effectful connector. It proves that executing an unavailable plan is equal to the immediate pure return of its complete original resolution. Thus this branch cannot call the connector, even one that would fail, allocate a resource or perform IO. This is an IO-program equality at the dispatch boundary; it is not a universal DNS, socket-ownership or scheduler theorem.

The dispatcher uses ordinary erased type parameters and a first-class connector, so the law can quantify over them. The HTTP resolver adapter supplies its specialized connector to that generic boundary. Keeping the dispatcher in `connection-plan` also avoids importing the whole effectful DNS implementation merely to prove this boundary. The gate checks 196 public laws and 57 supporting lemmas and rejects 124 typed mutations, including an unavailable branch changed to invoke its connector with an empty list. Existing source-annotation and proof-summary audits remain unchanged.

### Received response metadata

The eight `http-response-metadata` laws quantify over arbitrary status lines, received fields, accumulated headers and body-exposure flags. The partition law proves that folding concatenated fields equals folding the first part and then the second. Empty and single-field boundaries constrain that fold to preserve actual fields; public-header retention ties the constructor to it. Separate laws retain the original head, numeric status and exposure flag and classify success by the numeric 200–299 range. These concern immutable projection, not body lifecycle, wire validation or IO scheduling. The gate now checks 206 public laws and 57 supporting lemmas and rejects 129 typed mutations, including erased received fields, success at 300 and erased exposure. No new unsafe declaration supplies a proof.

### Response progress and cleanup

Ten `http-response-progress` laws quantify over arbitrary head/body payloads, trailer fields, exposure flags and transport/cleanup error types. They preserve final-head metadata, nonempty chunks and trailers, treat empty chunks as continued reading, suppress hidden-body bytes without hiding errors, and retain both primary and cleanup failures. The gate checks 216 public laws and 57 supporting lemmas and rejects 132 typed mutations. The pure progress definitions remain separate from the external-reader-controlled IO loops; no unsafe definition is used to prove these claims. [Ownership integration](http-response-ownership.md) supplies finite IO trace and native socket evidence rather than asserting universal resource retirement.

### Acquired HTTP byte source

Five `http-body-source` laws quantify over arbitrary byte lists, error types/mappings, affine transport state types, close functions and retained trailers. They preserve the byte payload, distinguish EOF from an empty chunk, retain the supplied mapping for read/close failures, and establish an IO-program equality: releasing an already-closed body is an immediate success regardless of the transport close function. The gate checks 221 public laws and 57 supporting lemmas and rejects 134 typed mutations, including erased payloads and EOF replaced with a chunk. Importing this adapter brings its three existing IO-loop annotations into the root's explicit audit; no law invokes them or claims their termination. Callback serialization and resource retirement have separate finite integration evidence.

### Cancellation classification boundaries

Six `http-abort-classification` laws quantify over arbitrary error types and classification functions. Lone transport/cleanup errors delegate to the supplied classifier; combined causes, unexpected events and missing head/completion cannot become cancellation. The gate checks 227 public laws and 57 supporting lemmas and rejects 136 typed mutations, including hidden combined failures and an ignored transport classifier. Native error constructors and effectful provider composition have separate [finite validation](openai-responses.md); the generic laws are not an exhaustive proof of those adapters. The root's unsafe-declaration audit is unchanged.

### Buffered response consumption

Two more `bounded-bytes` laws guarantee exact in-order completion for every fitting input and rejection of every nonempty excess. Two supporting lemmas specify the accumulator after arbitrary fitting input. Six `http-body-buffer` laws preserve successful bytes, read failures and independent/combined cleanup failures and establish immediate termination of pure collection decisions on any excess. Existing chunk-composition proofs make these guarantees independent of input chunk boundaries. The gate checks 235 public laws and 59 supporting lemmas and rejects 142 typed mutations. The [effectful consumer evidence](http-body-consumption.md) remains separate; its external-source-controlled IO loop is not imported into or used by the proof root.

### Retry success ownership

Six `provider-retry` laws quantify over arbitrary Bend value quantities and success/error types, including affine resources. They express IO-program equalities for success, completed/retry continuation dispatch, abort/exhaustion precedence and application failures. The gate checks 241 public laws and 59 supporting lemmas and rejects 145 typed mutations. These branch/effect guarantees do not prove termination of arbitrary callbacks or universal resource retirement; [socket ownership and upstream regressions](provider-retry.md) supply complementary executed evidence. No unsafe declaration was added to the proof root.


### Provider HTTP response ownership and diagnostics

Four `provider-http-response` laws quantify over arbitrary source/error types, effect functions, metadata, body owners and diagnostic outcomes. They guarantee immediate unchanged successful handoff, failed-status consumption before producing the failure, preservation of diagnostic results, and status/header projection without losing the original provider error. The gate checks 245 public laws and 59 supporting lemmas and rejects 148 typed mutations. The existing buffered-body IO loop enters the audited import closure (ten named local declarations; the compiler reports eight annotations); no proof relies on its termination. [Effect and native HTTP checks](provider-retry.md) cover the actual reads, closes and retry composition.


### Typed OpenAI errors and whole-character budgets

Nine `openai-http-error` laws retain arbitrary metadata, diagnostics, construction failures, selected values, normalized inputs and retry originals. Five `text-unit-budget` laws establish chunk composition, a stable prefix after exhaustion, complete fitting-character retention, exclusion of a nonfitting character and the empty-input boundary. The gate checks 259 public laws and 59 supporting lemmas, rejecting 153 typed mutations with the same unsafe import audit. [Codec, source-oracle and native HTTP evidence](openai-responses.md) remain distinct from the generic proofs.

### Provider request hooks and response ownership

Eight `provider-request` laws quantify over arbitrary payload/model/error and affine owner types. They preserve exact replacements and errors, establish no-effect hook-absence/failure boundaries, retain successful owners and require release before returning both hook and cleanup outcomes. `provider-response-view` preserves the whole response during canonical metadata projection. The gate checks 268 public laws and 59 supporting lemmas, rejecting 157 typed mutations. The explicit unsafe-declaration audit is unchanged; its summary parser additionally recognizes the two-annotation success reported by the response-view import. Real HTTP checks supply separate finite hook ordering, retries and resource evidence.

### Outer Responses lifecycle

Fifteen `openai-responses-lifecycle` laws quantify over message fields, argument/diagnostic/error types, failure causes and callback handles. They preserve terminal events and unrelated message fields, enforce cancellation/stop-reason and primary/cleanup precedence, establish last-write failure updates and require stream closure before returning the run result. The gate checks 283 public laws and 59 supporting lemmas and rejects 163 typed mutations. Its unsafe audit is unchanged. [Native HTTP, processor and concurrent event-stream checks](openai-responses.md) remain separate finite evidence.

### Asynchronous Responses session ownership

Ten `openai-responses-session` laws preserve canonical publication, final snapshots and borrowed task/stream/result state. They establish effect-free completed waits, publication-callback retirement before returning, and joining before stream disposal for arbitrary typed run outcomes and handles. The gate checks 293 public laws and 59 supporting lemmas and rejects 168 typed mutations with the existing unsafe audit unchanged. [Gated ownership and HTTP integration](openai-responses.md) supply separate finite concurrency/resource evidence.

## Responses options and request preparation

Twelve new laws preserve every inherited/provider option through extension and projection, retain prepared fields and typed failures, reject the wrong model API, bypass downstream effects after credential/grammar rejection, and distinguish omitted/null/string fields over arbitrary objects. The two effect-rejection template laws specialize the wire/diagnostic types while quantifying over all runtime values; see the [scope and evidence](openai-responses.md). The gate checks 305 public laws and 59 supporting lemmas and rejects 178 well-typed mutations. Full-root checks remain mandatory; each localized mutation proof has an accepted unmodified baseline before the named contract must reject the mutant. The import closure now audits thirteen existing unsafe declarations, with twelve concrete compiler annotations; no new unsafe routine is introduced.

## Provider header state and OpenAI request headers

Twenty-four new laws cover immutable header layer/entry composition, replacement/removal provenance, wire materialization, timeout/error retention and authentication policy. Two supporting lemmas establish disjunction symmetry and empty-entry identity. The [scope and comparison evidence](openai-responses.md) distinguish these contracts from HTTP transmission or remote authentication. The gate checks 329 public laws and 61 supporting lemmas and rejects 189 typed mutations; existing unsafe imports remain unchanged.

## Native Responses retry classification

Nine new laws preserve typed native failure categories and cancellation/deadline precedence over arbitrary error payloads. The [native attempt design](openai-responses.md) states their limits and complementary network/resource checks. The full gate checks 399 public laws and 65 supporting lemmas and rejects 219 well-typed mutations, open obligations and a missing proof. The nineteen named unsafe declarations remain unchanged. Existing FIFO laws and helpers moved verbatim into `laws/fifo.bend`; queue mutation proofs now import that module locally, while full-root validation remains mandatory.

## Responses acquisition bridge

Three generic laws preserve all prepared client settings and payload, forbid transport effects for any envelope failure, and transfer successful envelopes unchanged. The existing provider-request laws supply hook selection and cleanup contracts. The full gate checks 402 public laws and 65 supporting lemmas and rejects 221 well-typed mutations, open obligations and a missing proof. Its nineteen named unsafe declarations are unchanged. [Acquisition design](openai-responses.md) describes the boundary and separates pure contracts from network/resource validation.

## Retry error embedding

Six `provider-retry-map` laws establish identity and composition of error embedding, retention of provider metadata and terminal classification, and unchanged transfer of arbitrary affine success owners. The full gate checks 408 public laws and 65 supporting lemmas and rejects 223 typed mutations, open obligations and a missing proof. The nineteen named unsafe declarations remain unchanged. [The native callback design](openai-responses.md) separates these pure guarantees from actual callback/transport ownership checks.

### Strict native retry durations (2026-09-21)

Three retry laws retain invalid-duration causes, distinguish cancellation and allow continuation after successful sleep. A fourth law rejects invalid durations without allocating a timer or cancellation observer for any error and signal. The full gate checks 412 public laws and 65 supporting lemmas and rejects 225 typed mutations, open obligations and a missing proof. Nineteen existing unsafe declarations are unchanged. These laws establish control flow and error preservation; the [duration record](provider-retry.md) separates them from numeric boundary tests and timer/resource audits.

### Canonical retry configuration and acquisition (2026-09-21)

The full gate checks 424 public laws and 67 supporting lemmas and rejects 228 typed mutations, open obligations and a missing proof. Added laws preserve validated retry fields and error causes, establish signal independence and isolate the canonical retry projection from unrelated settings. Configured acquisition laws retain errors and affine successful responses; its no-effects rejection law quantifies runtime inputs at explicitly documented closed template types. The exact unsafe declaration set remains nineteen; additional specializations make the checker report twenty-one instances. [Retry configuration](provider-retry.md) distinguishes these guarantees from numeric and IO validation.

### Scoped Responses body ownership (2026-09-21)

The full gate checks 429 public laws and 67 supporting lemmas and rejects 231 typed mutations, open obligations and a missing proof. Five new laws quantify disposal causes, final messages and error embeddings: reader-only, body-only and simultaneous disposal failures retain their causes, while lifecycle conversion preserves successful output and simultaneous primary/cleanup failures. These are value-preservation guarantees; live resource retirement remains an IO integration test. The existing SSE reader loop is newly reachable from the root: twenty unchanged unsafe source declarations produce twenty-two concrete checker annotations. No unsafe definition was added.

### Producer-owned session cleanup (2026-09-21)

The full gate checks 430 public laws and 67 supporting lemmas and rejects 232 typed mutations. The new law quantifies every lifecycle result and dependency cleanup program, requiring cleanup before returning that unchanged result. The ownership design and IO evidence cover the producer wiring, gated retirement, repeated joins and existing provider-session regressions. The unsafe source declaration set is unchanged.

### Native Responses session composition (2026-09-21)

Eight generic laws preserve supplied cancellation ownership, borrowed/local signal identity, affine response transfer, typed acquisition failures and canonical options during signal binding. The full gate checks 438 public laws and 67 supporting lemmas and rejects 235 typed mutations, including caller-signal disposal, dropped cancellation and dropped response hooks. The existing unsafe declaration set is unchanged. [Runtime evidence](openai-responses.md) separately exercises the composed transport and asynchronous lifecycle.

### Default service-tier pricing (2026-09-21)

Five generic laws cover unchanged usage, all token counters, absent tiers, model-independent flex policy and scaled cost calculation. The full gate checks 443 public laws and 67 supporting lemmas and rejects 238 typed mutations; three new mutations alter token counts, change unchanged usage or omit cache-write cost. [The pricing design](openai-responses.md) distinguishes these guarantees from numeric/runtime evidence and the two separately checked owner laws, which are not yet registered in the root. The unsafe declaration set is unchanged.

### Default session ownership (2026-09-21)

The full gate checks 448 public laws and 67 supporting lemmas and rejects 243 typed mutations. It includes the two pricing-owner laws and three session-composition laws: grammar preservation, installation of owned pricing, and pricing retirement before supplied dependencies. [Runtime formatting and ownership](openai-responses.md) have separate finite evidence. The twenty existing unsafe declarations still produce twenty-two concrete checker annotations. The subsequent hook-adapter gate passes with 455 public laws, 67 supporting lemmas and 246 rejected typed mutations. Its seven additional generic contracts cover success/error mapping, borrowed ownership and adapter retirement, with three mutations exercising dropped hooks and skipped disposal.

The preparation/acquisition gate checks 461 public laws and 67 supporting lemmas and rejects 249 well-typed mutations. It registers the two canonical hook-option preservation laws and four prepared-response ownership laws. New mutations lose the timeout, response hook or prepared base URL; each mutant typechecks before its contract fails. The full root retains twenty-two existing unsafe annotations. New preparation/request formatters and cleartext runtime ownership have separately recorded standalone proofs and are not counted in this root. Provider-core integration now passes 216 native/Bun plain/audited executions; the additional grammar-retention and callback-lifetime fixture passes 72 plain/audited native/Bun executions.

The formatter and dependency-owner gate checks 472 public laws and 67 supporting lemmas, rejecting 254 well-typed mutations. Eleven additional laws cover preparation diagnostics, primary request errors, dependency initialization failure, borrowed handles and disposal order. The root reports thirty-one concrete unsafe annotations from the unchanged twenty audited declarations; these counts differ because specialization produces multiple instances. The inverse-calendar success law remains standalone and is not counted here.

The completed calendar/date gate checks 482 public laws, 74 supporting lemmas and rejects 260 well-typed mutations. Six new mutations target unchecked reconstruction, changed literal years, lossy leap conversion, weekday acceptance and lost error causes. The four default-date-owner laws and five system-runtime laws remain standalone. The root retains the same twenty unsafe declarations and thirty-one concrete annotations.

The owned acquisition gate checks 502 public laws and 74 supporting lemmas and rejects 268 well-typed mutations. It registers the default/system-runtime, generic lazy-owner and request-plan laws. Eight new mutations target callback retirement, cleanup ordering, cause preservation, cancellation precedence and retained response callbacks. The existing file-fold driver enters this root, bringing its explicit audit to twenty-one source declarations and thirty-four concrete annotations; no new unsafe declaration was introduced. System-provider and default-SSE-hook laws have separate standalone evidence and are not included in these counts.

Eight [recursive native presentation laws](openai-responses.md) now pass standalone under the accepted isolated compiler. They retain primary diagnostics through payload, response, retry and processing wrappers for arbitrary error types and pure leaf functions. Three type-correct mutations that lose or replace the primary cause are rejected. These eight are outside the running expanded root gate and do not change its reported law count.

Seven [system-owned presentation laws](openai-responses.md) pass standalone, preserving initialization/request/release diagnostics and full recursive processing causes. Two type-correct cause-erasure mutations fail their intended contracts. These seven, like the native renderer's eight, remain outside the running expanded root gate.

The provider rendering and default-hook gate checks 522 public laws and 74 supporting lemmas, rejecting all 276 type-correct mutations, open obligations and a missing proof. It registers default SSE hooks, system error/ownership composition, streaming diagnostics and envelope diagnostics. The unchanged twenty-one exact unsafe source declarations produce forty-one specialized annotations. The default-clock pair remains unproved under the accepted compiler; the newer native/system presentation laws remain standalone and are not included in this count.

Nine [resolver diagnostic laws](resolver-diagnostic.md) pass standalone, including inductive option-count and concatenation invariants and arbitrary token/code/message preservation. Three type-correct information-loss mutations are rejected. These complement the fifteen standalone native/system renderer laws; none of these twenty-four is included in the completed 522-law root count.

At Gregor’s request, the trusted-compiler check now checks the unchanged 522-law/74-lemma root directly, without generating broken implementations or negative proof cases. The source audit and hashes remain. This run passes in 19.24 seconds; historical mutation campaigns are not part of the continuing workflow.

Six [concrete initialization diagnostic laws](openai-responses.md) pass standalone, preserving arbitrary OS causes, short-read counts and diagnostic collections. Singleton display is proved by structural induction. These remain outside the 522-law root; no mutation tests were run.

The diagnostic integration check now proves 552 public laws and 74 supporting lemmas. It registers the native/system error interpreters, resolver diagnostics and initialization formatter. The unchanged twenty-one unsafe source declarations still produce forty-one specialized annotations. The compiler is trusted; the check creates no broken implementations or negative proof cases. The default-clock pair remains outside this root because its proof still overflows the accepted checker.

The standard system-format check proves 553 public laws and 74 supporting lemmas. Its new contract connects every system initialization failure to the concrete initialization formatter; the existing recursive preservation laws also apply to this default handler. The exact unsafe declaration audit is unchanged.

### OpenAI Responses provider consolidation (2026-09-22)

The 35 law modules of the retired layer modules (`openai-body-responses-reader` … `openai-responses-system-render`) are deleted with those modules; most stated wrapper equalities of one-line adapters. Five modules replace them with 73 laws over the consolidated provider ([design](openai-responses.md)):

- `laws/openai-responses.bend` (19): cancellation precedes stop validation; an existing failure keeps its cause under cancellation; failure preserves every other assistant-message field; a disposal failure never replaces the processing outcome; a supplied signal is never disposed; a cancelled or rejected request never opens a transport; an acquisition failure never reaches the hooks; the Responses options are a lossless extension of `StreamOptions` (three round trips); disabled caching drops session affinity, explicit retention overrides the environment, the `24h` retention header requires compat and yields to explicit cache mode; absent, `default` and `auto` service tiers keep usage unchanged.
- `laws/openai-responses-stream.bend` (9): the response's service tier overrides the request; a terminal failure suppresses pricing and stop mapping; `max_output_tokens` is a length stop; tool calls promote a plain stop and never change length/error stops; stop mapping preserves every other message field; an end without a terminal response is an error.
- `laws/openai-sse.bend` (12): the SDK dispatch policy — a `[DONE]` marker suppresses later frames and is entered by prefix, `thread.*` events bypass error detection, JSON failures target the console for thread events and the client logger otherwise, `null`/`false`/empty-text `error` fields are messages while object/array/nonempty-text fields reject the stream, synthesized delivery carries the event name.
- `laws/openai-client.bend` (24): the previous header/authentication and `APIError` laws carried over unchanged, plus retry classification: non-retryable categories stay application errors, connection failures and expired deadlines become retryable provider errors with pi's messages, parent cancellation is never retried and overrides the transport category, invalid timeouts are never retried.
- `laws/fetch.bend` (9): native transport classification — only deadline expiry is a timeout, DNS inherits the request classification, resolver setup failures and terminal query failures are not retried, unanswered lookups are connection failures, a DNS deadline overrides the report.

Template (`~`) arguments must be closed in a law, so the lifecycle and transport laws instantiate `Reason`/`E`/`G` with `String`/`Unit`; the values they quantify over remain arbitrary. The root now checks 434 public laws and 74 supporting lemmas with the same unsafe declaration set minus the retired SSE reader (`openai-sse.bend drive` replaces `openai-sse-reader.bend drive`; the strict-schema pair moved into `constrained-sampling.bend`).

### Provider utilities consolidated (2026-09-22)

`packages/ai/src/utils` follows upstream's module boundaries again: `provider-retry.bend` holds the policy, loop, option validation, rendering and native effects ([design](provider-retry.md)); the headers section of `http-message.bend` holds the header record projections and provider-header overlays; the SDK's layered header state and status boundary moved into `openai-client.bend`, whose laws now include the fourteen header-layer laws (layer/entry partition, first-error preservation, observable latest setting, explicit removal until materialization) and three status-boundary laws (no body IO on success, diagnostic consumption before failure, retry-metadata projection). `laws/provider-retry.bend` absorbs the eight option-validation laws and the no-timer-effect sleep law. The 26 wrapper laws of the deleted hook-map, hook-options, owned-acquire, request, request-error, response-view, retry-config and retry-map layers are gone with those layers. `laws/json.bend` replaces `json-finite` now that the finiteness check lives in `json.bend`.

### Agent modules merged (2026-09-22)

`laws/agent-events.bend`, `laws/agent-owner.bend`, `laws/agent-queues.bend` and `laws/pending-queue.bend` now import `packages/agent/src/agent.bend` and `agent-loop.bend` directly; their statements are unchanged apart from the module-suffixed internal names. The audited unsafe set gains the existing recursive drivers those modules already contained (`agent-loop.bend`: `advanceCall`, `advanceLoop`, `consumeAssistantIterations`, `deliverParallel`, `deliverTurn`, `executeParallel`, `prepareParallel`, `sequentialBatch`; `agent.bend`: `dispatch`) and the schema/validation routines they import, which the law closure did not reach before. No unsafe definition was added.

### Runtime name resolution merged (2026-09-22)

The 24 law modules for DNS, resolver configuration, hosts and connection scheduling keep their statements and now import the six merged runtime modules; renamed internal names are the only textual change. The audited unsafe drivers moved with their code: `dns-message.bend drive` (search run), `dns-transport.bend driveTcpConnection`/`read`/`readUdpQuery`, `dns-resolver.bend drive` (address lookup). No unsafe definition was added.

### Runtime HTTP family merged (2026-09-22)

The HTTP, SSE, socket and line-decoder laws keep their statements over the five merged modules; the audited unsafe drivers moved with their code (`http-response.bend`: `seek`, `drive`, `driveBodyConsume`, `driveResponseReader`; `sse.bend`: `drive`).

### Law files grouped by module (2026-09-22)

`laws/` and `proofs/` now carry one file per constrained module rather than one per pre-merge source module: `dns-message`, `resolver-config`, `dns-transport`, `connection-driver`, `hosts`, `http-message`, `http-response`, `url`, `sse` and `agent` absorb the 38 files that constrained them (61 law files become 32; 401 laws unchanged). Statements are verbatim; the only textual changes are four collisions that the merge exposed: the resolver-search law `rejects_diagnostics` is `search_rejects_diagnostics` (the resolver-request law keeps the name), the line-decoder helper `decoderOf` is `lineDecoderOf`, and the helpers `cursor` and `remaining` became `searchCursor` and `remainingQueues` because same-named binders in neighbouring laws shadowed them. The remaining single-module files take their module's name too (`abort`, `bounded`, `calendar`, `dns-resolver`, `http-exchange`, `string`, `text`, `timer`, `utf8`). Earlier sections keep the file names they used at the time.

### Message transformation and replay repair (2026-09-22)

`laws/transform-messages.bend` (20) covers pi's `transformMessages` first pass and `laws/transform-tool-results.bend` (11) its second pass, both previously covered only by example fixtures. Image downgrade: no image survives, text-only content is unchanged, adjacent images share one placeholder, message roles and system/assistant messages are preserved. Replay: same-model text and tool calls replay verbatim; cross-model replay never carries a thinking block; redacted thinking is dropped across models and kept on the same model; signed thinking replays on the same model; blank unsigned thinking is dropped for either model; visible cross-model thinking becomes plain text; cross-model text and tool calls lose their signatures; replay identity holds when API, provider and model id all agree (proved with the string-equality lemmas). Tool-call id mapping: unmapped and empty mappings keep the result id, a nonempty mapping applies, and an identity normalization is not remembered. Repair: errored and aborted assistant turns are not replayed and clear pending calls; a replayable turn tracks exactly its tool calls (hypothesis `replayable(reason) == True`); tool results answer their call; system messages wait while calls are pending and pass otherwise; the effectful boundary with a frozen clock and closed type arguments proves that answered calls are left alone, an unanswered call gets an error-flagged "No result provided" result carrying its id and name, a flush without pending calls only releases held messages, and user and assistant turns release held messages before themselves. Template arguments must be closed, so the effectful laws instantiate the message parameters with `Unit`/`String`. The example fixtures remain for the literal placeholder texts and timestamps.

### Tool-argument coercion (2026-09-22)

`laws/validation.bend` (7) states the documented contract that primitive coercion only rewrites scalars: arrays and objects pass every primitive kind and every declared type list unchanged (the type-list laws rewrite the symbolic `primitiveType(head)` through the per-kind law, since string comparison against a symbolic type name does not reduce). The recursive driver's failures are final for every task shape, and boolean and empty object schemas accept every value unchanged. Example fixtures keep the AJV-compatible scalar rules, which compare concrete strings and numbers.

### Continue planning (2026-09-22)

Six laws in `laws/agent.bend` cover pi's `continue()` as the pure decision `continuationPlan`: a busy agent cannot continue; a transcript of only system messages cannot continue (for every length, by induction on the system list); a transcript ending in a user message resumes the run whatever precedes it (induction over the prefix with the accumulated "non-system seen" flag); after an assistant tail a queued steering message is prompted first with the initial steering poll skipped, otherwise a queued follow-up is prompted without skipping it, and with both queues empty the continue fails with the assistant-tail error. The queue laws hold for both queue modes, and the drained queues are proved to return to their fresh state. These correspond to the upstream agent tests for continue after streaming, follow-up processing and one-at-a-time steering, whose remaining assertions concern the effectful run.

### Transcript normalization and system-message replay (2026-09-22)

`laws/transcript.bend` (14) generalizes the ported system-message-replay fixtures. Normalization: no prompt and no tools (or a blank prompt and an empty tool list) add nothing; a nonempty prompt or a nonempty tool list becomes exactly one leading system message with the zero timestamp. Replay: supported mid-conversation system messages keep the transcript untouched; after collapse no system message follows the head; a transcript without system messages replays nothing and collapses to itself (three lemmas over the non-system message shapes, rewritten into the replay pipeline); replay keeps the first system timestamp across any later messages. Tools: the declared tool set ignores removals at the message level, an added tool is current, a later removal of the same name empties the current set (string-equality lemma) while the declared set keeps it, and any removal makes the tool history non-additive.

### Reasoning levels and thinking budgets (2026-09-22)

`laws/simple-options.bend` (7): clamped reasoning never exceeds high, clamping is idempotent and keeps every level up to high (the two excluded levels are discharged by eliminating the contradictory hypothesis `False == True` through a type-valued motive, `Truth(_)`, into `Empty.absurd`); explicit thinking budgets are used per level, empty custom budgets equal the defaults, and fitting the budget never changes the response ceiling while a budget below the ceiling is kept verbatim. `laws/thinking-levels.bend` (7): non-reasoning models only offer off; an explicit null mapping disables and an explicit value enables any level; unmapped levels are supported exactly up to high; `closest` takes the first candidate at or above the request, skips lower candidates carrying them as the fallback, and returns the fallback without candidates; `fromName` inverts `name` for every level (the RPC and settings wire form). These correspond to the upstream token-budget tests ("clamps xhigh and max to the high budget", "sends the configured budget for the requested level") and the thinking-level selection used by the coding agent.

### Tool execution mode, batch termination and the beforeToolCall decision (2026-09-22)

`laws/agent-loop.bend` (21) states the pure decisions of the agent loop that the upstream agent-loop tests exercise through live runs: a configured sequential mode wins; one sequential tool forces sequential execution of the whole batch (hypothesis on the per-tool scan, since tool names compare as symbolic strings); otherwise parallel tools run in parallel; an empty batch terminates, a batch of terminating results terminates, and a single continuing result continues the run; an aborted operation rejects every tool call with "Operation aborted"; without a hook result the call proceeds; a non-blocking hook lets the call proceed; a blocking hook rejects with its reason and its terminate flag, falling back to "Tool execution was blocked" for an absent or empty reason; an empty batch never terminates and a nonempty batch terminates exactly when every call opted in; queued messages continue the run without an agent_end event and a failed queue read fails the turn; only a length stop marks an assistant message truncated; at the stream lease a failed open has nothing to release, an earlier failure survives the release, a release failure fails a consumed response and a clean release keeps the message. The contradictory-hypothesis eliminators now live in `proofs/absurd.bend` (`false_is_not_true`, `true_is_not_false`) for reuse.

### Automatic-compaction decision (2026-09-23)

`laws/compaction.bend` (4) characterizes upstream `_checkCompaction`'s decision, `decideCompaction` in `core/compaction/plan.bend`, over every combination of its facts (skipped check, context overflow, recoverable length stop, completed response, recovery already attempted, context past the threshold): a skipped check never compacts; a compact-and-retry is planned exactly for a failed overflow whose recovery was not yet attempted, so recovery runs at most once until a completed or aborted response re-arms it; recovery is reported exhausted exactly for a repeated failed overflow; threshold compaction happens exactly when nothing overflowed and the context is past the threshold. The proofs are finite case splits over the six Booleans. The decision lives in its own dependency-free module so the proof closure adds no unsafe declarations; how AgentSession derives the facts from the assistant message, model and compaction boundary is covered by the faux-provider scenarios in `tests/agent-session.md`, which run "does not retry overflow recovery more than once" and the threshold and disabled cases end to end; "compacts successful overflow responses without retrying" is covered by the laws only.

The v0.87.1 turn decisions add two laws. `laws/agent-loop.bend`: queued messages continue the run and a failed queue read fails it whatever finishTurn decided, and an explicit continuation with nothing queued continues once on the current context (upstream "makes exactly one context-only request"). `laws/agent.bend`: previewing a pending queue yields exactly the messages the list-level delivery model says a drain emits, so `peekQueuedMessages` agrees with the next drain in both queue modes.

