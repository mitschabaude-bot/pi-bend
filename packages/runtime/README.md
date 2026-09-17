# Bend runtime foundations

This package supplies primitives missing from Bend 2.0.4 that the faithful pi library port requires. Implementations are pure Bend. The compiler's normal native backend is used without prototype C effects, host numeric callbacks or JavaScript runtime support.

`src/ref.bend` provides shared identity and atomic updates over Bend channels. `Ref<A>` is a copyable handle even when A is affine. `modify` owns the value exclusively and takes a pure state transformation; only `Data` values can be copied out by `read`. This lets stream events retain the same live response reference rather than a stale snapshot.

`src/deferred.bend` provides first-settlement results and repeated observations. `subscribe` registers an observation before returning its single-use ticket; `wait` consumes that ticket. Waiting, late and repeated observers receive the original result. `result` combines registration and waiting. Resolving a shared reference preserves its identity.

`src/callback.bend` provides reusable first-class callback handles despite Bend's affine closures. Construction supplies closed callback code and a typed runtime capture environment; libraries subsequently accept and store the resulting runtime `Callback<Input, Output>` value. Each call obtains a fresh affine closure and releases the factory before invoking user code, allowing concurrent async calls. Inputs and outputs may themselves be affine. The factory uses one explicitly documented guarded `@unsafe` corecursion: construction returns a closure, and each invocation constructs one successor. There is no background actor or artificial invocation limit.

These shared primitives currently require owner-directed disposal after aliases and observers retire. The current Bend channel runtime does not reclaim live channel rows merely because handles are dropped. Automatic shared-object reclamation therefore remains a language/runtime prerequisite for JavaScript-equivalent object lifetimes. These primitives do not establish completion of pi's event-stream or subscription semantics. The generic stream has separate upstream tests in `packages/ai/test/event-stream.bend`.

`src/u64.bend` implements unsigned fixed-width arithmetic modulo 2^64, bit operations, logical shifts, rotations, comparison, and quotient/remainder division. Values use two U32 limbs, ordered high then low. Division by zero returns `None`; shifts of at least 64 bits produce zero; rotations reduce their count modulo 64. `multiplyWords` exposes the exact 32-by-32-bit product needed by wider arithmetic.

`src/u128.bend` provides exact 64-by-64-bit multiplication and wide intermediates with sticky-bit shifting. It is used to retain the full product before binary64 rounding.

`src/f64.bend` represents every IEEE-754 binary64 bit pattern and implements addition, subtraction, multiplication and division with round-to-nearest, ties-to-even. It retains signed zeros and subnormal results. Arithmetic NaNs become a canonical quiet NaN; payload preservation is not an API guarantee. Comparisons return `None` for unordered NaN operands and treat signed zeros as equal. Unsigned integer conversion rounds directly from the 64-bit integer. Alignment retains guard, round and sticky bits; cancellation and underflow are normalized before the final rounding. Operations never pass through F32. Decimal parsing/formatting and remaining numeric operations are still required before full integration with pi's number APIs.

Run the independent vector tests from the repository root:

```sh
python3 tests/u64_vectors.py
python3 tests/f64_vectors.py
sh tests/runtime-concurrency.sh
```

Python generates expected results from arbitrary-precision integers and host binary64 arithmetic. It writes constant input/output vectors, then compiles and executes Bend assertions. Python supplies no behavior to the implementation or native executable. The tests currently cover 272 unsigned/wide arithmetic vectors and 1,077 floating-point vectors, each checking all four operations, comparison and integer conversion. These tests supplement, rather than replace, the future port of pi's numeric and model-cost tests.

Concurrency tests check retained reference identity, 1,000 competing updates, affine ownership, result fan-out, ignored duplicate settlements, repeated callback invocation, and overlapping async callback calls. Gates and explicit registrations coordinate the tests; no sleeps are used to guess scheduling order.

`src/fifo.bend` supplies the persistent two-list FIFO used by the event stream and per-iterator request queues. Enqueue/dequeue are amortized constant time along a queue history; transferring incoming values reverses the list only when the outgoing side empties. Stream tests cover buffered and waiting-consumer ordering across transfers.

`src/record.bend` represents own enumerable string data properties, with replacement/deletion and JavaScript object key enumeration: canonical array indices below 2^32-1 are numeric, and other keys retain insertion order. It is distinct from JavaScript Map ordering and does not implement prototypes, accessors or symbol properties. Operations currently scan persistent property lists, suitable for small metadata/section records; large dynamic-object integration may need a different storage implementation. `python3 tests/record_vectors.py` checks 50 deterministic mutation sequences against actual JavaScript own-property enumeration, including index boundaries, leading zeros, Unicode names and deletion/reinsertion. JavaScript is a test oracle only.
