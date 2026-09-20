# Laws and proof coverage

Gregor authorized agent-authored general specifications on 2026-09-20. Laws must be honest attempts to capture intended behavior, independent of implementation accidents. Prefer universally quantified properties that imply upstream examples. Meaningful boundaries, such as an empty queue, are valid laws; arbitrary regression inputs remain tests. Never weaken a contract to make a proof pass. These proof milestones change no production implementations.

`LAWS.bend` is the public specification entry point, importing component contracts from `laws/`; `PROOF.bend` imports their implementations and supporting lemmas from `proofs/`. `bend PROOF.bend` must succeed. The current import closure reports `All terms check, with 1 unsafe annotation.` Agent types import effectful runtime definitions (callback factories and stream driving); no queue law or proof calls those definitions or uses `@unsafe`. This summary is retained in the validation record, and the gate rejects an increased annotation count. The laws file alone intentionally fails because its obligations are open. The native regression entry point runs `scripts/check-proofs.py` before its executable suites.

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

The dictionary and set laws complement the queue contracts; the total including the ordered-map laws below is 35 public contracts and 33 supporting lemmas. Lookup at other keys, insertion order, and unique-key preservation are not yet proved. `tests/record_vectors.py` remains: its 50 operation sequences exercise insertion, replacement, reinsertion, ordering and the separate ordered-map implementation, beyond this law set. None of those tests or upstream suite statuses are retired or promoted here.

## Ordered-map equivalence

Five laws compare `OrderedMap` with the dictionary API through its complete entry sequence: empty construction, lookup, set, remove, and arbitrary edit histories. `edit_sequence` quantifies over every finite sequence of writes/deletes, arbitrary initial maps, arbitrary keys and every Data value type. Its inductive proof composes the individual operation laws. The separate insertion implementation compares string arguments in the opposite order, so its equivalence proof uses the established string-equality symmetry theorem.

This proves collection parity for every operation history of the form exercised by `tests/record_vectors.py`, including mixed replacement/deletion/reinsertion. The differential test also checks an external insertion-order model and native execution; equivalence between two Bend implementations alone does not establish either of those, so the test remains. The laws apply to the map used by `packages/ai/src/utils/transcript.bend` for tool replay and declaration indexing, but do not prove transcript traversal or the map's `values` projection.

## Relationship to pi and existing tests

The FIFO supports `packages/agent/src/pending-message-queue.bend`, corresponding to `PendingMessageQueue` in pinned pi-mono `packages/agent/src/agent.ts:140`. Six pending-queue laws now establish initialization, enqueue order, changing mode without changing messages, clearing without changing mode, mode-dependent delivery, and the equivalence of `hasItems` with a nonempty message sequence. The delivery specification uses list head/tail semantics: All emits everything and empties the queue; OneAtATime emits exactly the oldest message, or nothing for an empty queue. Both preserve the mode.

Eight paired-queue laws cover enqueue, clear, mode changes and drain. Each operation has a selected-queue contract and an isolation contract: its effect matches the pending-queue operation, and the other queue stays unchanged. These apply to either queue kind and arbitrary initial states. The selected-queue contracts compose with the pending-queue laws; they do not merely assert that an operation equals itself.

These 17 public laws and nine supporting lemmas do not prove transcript isolation or asynchronous consumption. The upstream “should support steering message queue” and “should support follow-up message queue” tests assert transcript isolation, which remains an integration obligation. Paired initialization, `clearAll`, and combined `hasQueuedMessages` also remain outside this law set.

No upstream suite status changes and no existing tests are removed in this milestone. The agent-queue differential and integration tests cover larger contracts than these pure queue transitions. Future coverage entries should name the upstream assertion and the law that implies it before retiring a redundant unit case.

## Checking the proof gate

`python3 scripts/check-proofs.py` checks the real proofs, rejects the open specification, and rejects removing the enqueue proof on which later proofs depend. It creates disposable copies of the local import closure with seventeen independent mutations: dropping the newly enqueued value, omitting the dequeued value, skipping incoming-list reversal, forgetting the mode on clear, discarding messages on mode change, clearing the other queue on enqueue, clearing the other queue on drain, retaining matching dictionary entries, discarding unrelated dictionary entries, making string-set removal a no-op, dropping a new dictionary key, retaining the old value on replacement, making set insertion a no-op, retaining an extra copy of the old entry during replacement, dropping an ordered-map key during replacement, making ordered-map removal a no-op, and always reporting missing on ordered-map lookup. Each mutated module must still typecheck, while the corresponding proof must fail. A failure may occur in a supporting lemma before the public contract: the duplicate-entry mutation, for example, invalidates the existing lookup proof construction even though lookup-after-set alone would still hold. Rejection demonstrates sensitivity of the proof gate, not that every failed proof falsifies its theorem; mutation testing is not the evidence for universal correctness. Python only launches the Bend checker and records diagnostics.

The initial [FIFO validation record](proof-validation/2026-09-20-fifo.json), expanded [queue validation record](proof-validation/2026-09-20-queues.json), [collection validation record](proof-validation/2026-09-20-collections.json), [insertion validation record](proof-validation/2026-09-20-insertion.json), [update-composition validation record](proof-validation/2026-09-20-update-composition.json), and [ordered-map validation record](proof-validation/2026-09-20-ordered-map.json) retain source/checker hashes and positive/negative outcomes. The installed checker is used without the compiler cache experiment. Proofs concern the checked pure definitions; compiler/runtime correctness, native execution, resource exhaustion and performance remain separate evidence obligations. No end-to-end pi correctness claim follows from these laws.

## Next coverage

Next extend collection coverage to preservation of other keys and update composition, then parser boundaries and agent state transitions, including the remaining wrapper and transcript contracts. DNS feature expansion stays paused while this workflow is established on existing foundations. Preserve external reference tests and IO/concurrency/terminal/performance tests throughout that transition.
