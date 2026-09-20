# Laws and proof coverage

Gregor authorized agent-authored general specifications on 2026-09-20. Laws must be honest attempts to capture intended behavior, independent of implementation accidents. Prefer universally quantified properties that imply upstream examples. Meaningful boundaries, such as an empty queue, are valid laws; arbitrary regression inputs remain tests. Never weaken a contract to make a proof pass. No production implementation changed in this first proof milestone.

`LAWS.bend` is the public specification; `PROOF.bend` proves it and contains supporting algebraic lemmas. `bend PROOF.bend` must report `All terms check.` The laws file alone intentionally fails because its obligations are open. The native regression entry point runs `scripts/check-proofs.py` before its executable suites.

## FIFO sequence contracts

The specification observes a queue through its public `drain` operation and models removal using ordinary list head/tail semantics. All laws quantify over every Data element type. Enqueue/dequeue laws cover arbitrary queues, including every incoming/outgoing list arrangement, rather than selected reachable examples.

| Law | Proved contract | Implementation |
| --- | --- | --- |
| `fifo_empty` | A newly created queue contains no values. | `fifo.new`, `fifo.drain` |
| `fifo_enqueue` | Enqueue preserves the entire previous sequence and appends exactly the supplied value. | `fifo.enqueue`, `fifo.drain` |
| `fifo_dequeue` | Dequeue returns the sequence's first value and retains exactly its tail; empty queues return no value and remain empty. | `fifo.dequeue`, `fifo.drain` |

The proofs use structural induction for Base list append associativity, append's empty identity and reverse-accumulator distribution. The queue representation is inspected only in the proof. No unproved project assumptions, holes, `@unsafe` definitions, foreign implementations or finite enumeration are used as proof evidence.

## Relationship to pi and existing tests

The FIFO supports `packages/agent/src/pending-message-queue.bend`, corresponding to `PendingMessageQueue` in pinned pi-mono `packages/agent/src/agent.ts:140`. The laws establish its underlying append/removal ordering for arbitrary messages. They do not yet prove the wrapper's mode handling, `hasItems`, clearing, steering/follow-up isolation, transcript isolation, or asynchronous consumption. Those require additional laws or effectful integration evidence. In particular, the named upstream “should support steering message queue” and “should support follow-up message queue” tests assert transcript isolation, which these FIFO laws do not discharge.

No upstream suite status changes and no existing tests are removed in this milestone. The agent-queue differential and integration tests cover larger contracts than the FIFO alone. Future coverage entries should name the upstream assertion and the law that implies it before retiring a redundant unit case.

## Checking the proof gate

`python3 scripts/check-proofs.py` checks the real proofs, rejects the open specification, and rejects removing the enqueue proof. It then creates disposable copies with three independent mutations: dropping the newly enqueued value, omitting the dequeued value, and skipping reversal when transferring incoming values. Each mutated module must still typecheck, while its proof must fail at the relevant FIFO law. This checks sensitivity of the proof gate; mutation testing is not the evidence for universal correctness. Python only launches the Bend checker and records diagnostics.

The initial [validation record](proof-validation/2026-09-20-fifo.json) retains source/checker hashes and positive/negative outcomes. The installed checker is used without the compiler cache experiment. Proofs concern the checked pure definitions; compiler/runtime correctness, native execution, resource exhaustion and performance remain separate evidence obligations. No end-to-end pi correctness claim follows from these three laws.

## Next coverage

Next prove pending-message queue modes and steering/follow-up isolation, then progress through collections, parser boundaries and agent state transitions. DNS feature expansion stays paused while this workflow is established on existing foundations. Preserve external reference tests and IO/concurrency/terminal/performance tests throughout that transition.
