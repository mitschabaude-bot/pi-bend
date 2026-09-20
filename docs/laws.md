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

## Relationship to pi and existing tests

The FIFO supports `packages/agent/src/pending-message-queue.bend`, corresponding to `PendingMessageQueue` in pinned pi-mono `packages/agent/src/agent.ts:140`. Six pending-queue laws now establish initialization, enqueue order, changing mode without changing messages, clearing without changing mode, mode-dependent delivery, and the equivalence of `hasItems` with a nonempty message sequence. The delivery specification uses list head/tail semantics: All emits everything and empties the queue; OneAtATime emits exactly the oldest message, or nothing for an empty queue. Both preserve the mode.

Eight paired-queue laws cover enqueue, clear, mode changes and drain. Each operation has a selected-queue contract and an isolation contract: its effect matches the pending-queue operation, and the other queue stays unchanged. These apply to either queue kind and arbitrary initial states. The selected-queue contracts compose with the pending-queue laws; they do not merely assert that an operation equals itself.

These 17 public laws and nine supporting lemmas do not prove transcript isolation or asynchronous consumption. The upstream “should support steering message queue” and “should support follow-up message queue” tests assert transcript isolation, which remains an integration obligation. Paired initialization, `clearAll`, and combined `hasQueuedMessages` also remain outside this law set.

No upstream suite status changes and no existing tests are removed in this milestone. The agent-queue differential and integration tests cover larger contracts than these pure queue transitions. Future coverage entries should name the upstream assertion and the law that implies it before retiring a redundant unit case.

## Checking the proof gate

`python3 scripts/check-proofs.py` checks the real proofs, rejects the open specification, and rejects removing the enqueue proof on which later proofs depend. It creates disposable copies of the local import closure with seven independent mutations: dropping the newly enqueued value, omitting the dequeued value, skipping incoming-list reversal, forgetting the mode on clear, discarding messages on mode change, clearing the other queue on enqueue, and clearing the other queue on drain. Each mutated module must still typecheck, while the corresponding proof must fail. This checks sensitivity of the proof gate; mutation testing is not the evidence for universal correctness. Python only launches the Bend checker and records diagnostics.

The initial [FIFO validation record](proof-validation/2026-09-20-fifo.json) and expanded [queue validation record](proof-validation/2026-09-20-queues.json) retain source/checker hashes and positive/negative outcomes. The installed checker is used without the compiler cache experiment. Proofs concern the checked pure definitions; compiler/runtime correctness, native execution, resource exhaustion and performance remain separate evidence obligations. No end-to-end pi correctness claim follows from these laws.

## Next coverage

Next progress through collections, parser boundaries and agent state transitions, including the remaining wrapper and transcript contracts. DNS feature expansion stays paused while this workflow is established on existing foundations. Preserve external reference tests and IO/concurrency/terminal/performance tests throughout that transition.
