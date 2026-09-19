# Owned timer implementation — validation in progress

This additive primitive bundle appends `base.bend` to the installed Base and adds `effs/timer.c` and `effs/timer.js` in an isolated copy. It does not modify compiler code, the general scheduler, existing effects, or the installation. No C/JS retry policy is introduced: these effects only manage a native timer's deadline, wait, cancellation and retirement.

```sh
python3 scripts/prepare-timer-candidate.py build/bend-timer-candidate-fresh
python3 tests/timer_primitive_check.py build/bend-timer-candidate-fresh
python3 tests/timer_races_check.py build/bend-timer-candidate-fresh
python3 tests/abortable_sleep_check.py build/bend-timer-candidate-fresh
python3 tests/provider_retry_native_sleep_check.py build/bend-timer-candidate-fresh
python3 scripts/benchmark-timer.py build/bend-timer-candidate-fresh build/timer-performance.json
```

`Timer.new(U32)` starts a monotonic deadline and returns an affine `Timer` owner plus a duplicable `TimerCancel` capability. `Timer.wait` consumes and returns the owner with `True` for expiration or `False` for cancellation. Completion commits when a wait observes expiry or the poller selects it; cancellation before commitment wins once and removes a parked activation before returning. Cancellation after commitment, after cancellation, or through a retired/stale handle returns `False`. A completed/cancelled timer can be waited on again with the stored outcome. `Timer.close` consumes the owner; the owner cannot be closed while its wait is outstanding. Discarding the affine owner does not automatically close it: callers must retire it explicitly, as with other Bend resources.

The C effect uses a separate index/generation table, with a free list and generation-wrap retirement. Table capacity tracks the maximum concurrent timer count and is retained for reuse. The JS effect uses an opaque object. Both use the existing scheduler. Native cancellation unlinks one item from its singly linked parked queue; JS cancellation removes its wait entry. Those new paths are linear in the number of parked operations. They do not add work to existing scheduler paths when timers are unused. JS cancellation treats a wait already selected by the poller as committed, even before its continuation runs, matching the native commitment point.

Core tests pass on one/four native threads and Bun: immediate and parked expiry, cancellation before/during wait, repeated cancellation, head/middle/tail removal, old capabilities after close/slot reuse, 10,000 serial lifecycles, affine-owner copy rejection, and a program using only new/close. A disposable instrumented C copy observes one actual parked expiration, only three used registry slots, and zero live timer rows/waiters at exit. These observations do not prove general race safety or absence of leaks under every workload.

The 20-round alternating-order comparison preserves existing generated C exactly. Separate checks preserve generated JS exactly for the same fixtures. Median compiler wall time is approximately 1.1% lower for detached sleep and 1.0% higher for UTF-8; shared-host measurements are inconclusive, not evidence of performance neutrality. The candidate remains uninstalled. Broader performance validation and complete provider-wrapper integration remain pending. The primitive is our implementation work; adoption awaits our validation, not an upstream fix. Raw compiler comparisons are retained in `docs/bend-issues/2026-09-19-timer-candidate-performance.json` and `2026-09-19-timer-candidate-js-parity.json`.

## Lifetime requirement

Pi’s provider-retry tests require cancellation of backoff to remove the outstanding timer immediately, without a second request. Bend’s existing `IO.sleep` and `IO.spawn` return no cancellation handle. Racing a detached sleep against an abort would leave scheduler work alive until its deadline. The reduced `tests/runtime-detached-sleep.bend` confirms that the spawned 250 ms timer outlives caller completion on one/four native threads; this is expected behavior, not a leak. Source hashes and observations remain in `docs/bend-issues/2026-09-19-detached-sleep.json`.

## Completion and cancellation stress

`tests/timer_races_check.py` passes on one/four native threads and Bun. Each process runs 270 deadline/two-canceller combinations and two forced outcomes, then repeatedly creates and retires cohorts of 1, 128 or 1,024 parked timers. Retirement reverses creation order to exercise tail removal. Exactly one canceller wins when cancellation wins; neither wins when expiration commits. Repeated waits retain the result, and cancellation after retirement is harmless.

Disposable instrumentation counts creation, expiration, cancellation, close and outstanding waits. Every created timer is closed, every timer settles exactly once, and every run exits with zero live timers and timer waiters. Native registry slots track peak cohort size rather than cumulative creation. The largest run per backend creates and closes 5,392 timers. These finite tests do not prove absence of all leaks or races. Instrumented timing is not performance evidence. Results and source hashes are in `docs/bend-issues/2026-09-19-timer-races.json`; core results are in `2026-09-19-timer-candidate-correctness.json`.

## Cohort cost

`scripts/benchmark-timer-cohorts.py build/timer-races OUTPUT` measures the uninstrumented fixture for three repetitions on one/four threads. Ten rounds of 4,096 timers, retired in reverse creation order, take median 0.663/0.661 seconds with 3,328 KiB peak RSS; the fixed race portion without cohorts takes 0.419/0.446 seconds. At 128 and 1,024 timers peak RSS is 2,048 and 2,304 KiB. These are complete lifecycle measurements including a fixed real-clock race workload, not isolated cancellation latency or proof of a particular scaling law. Queue scanning remains linear per cancellation. Raw samples and fixture/binary/generated-C hashes are in `docs/bend-issues/2026-09-19-timer-cohorts.json`.

## Pure Bend abortable sleep

`packages/runtime/src/abortable-sleep.bend` composes the primitive with the existing native `AbortSignal` and removable deferred observations. Pre-aborted calls return the retained reason immediately. Otherwise an observation watcher competes with timer completion; the winner determines the result. Before returning, the call cancels its observation, joins its watcher and closes its timer. The caller retains ownership of the signal. Zero milliseconds means a literal immediately eligible deadline; any provider event-loop delay normalization belongs in its adapter. This is not yet a claim of upstream retry scheduling parity.

`tests/abortable_sleep_check.py` runs eight repetitions on each backend: 32 normal waits sharing one signal, zero delay, cancellation of a 60-second wait, pre-aborted rejection and signal disposal. Native exit instrumentation verifies zero live timer rows, timer waiters and channel rows. All native one/four-thread and Bun runs pass. Retained observations are in `docs/bend-issues/2026-09-19-abortable-sleep.json`. Provider retry-loop integration and broadcast/deadline tests are now covered below; exact virtual-clock boundaries and exhaustive interleaving coverage are not established.

## Retry-loop integration

The pure Bend `ai/src/utils/provider-retry-sleep.bend` adapter now runs through the actual native retry loop. Twelve real-timer traces pass on one/four threads, including the long-backoff cancellation scenario. Instrumentation verifies expected timer creation counts, cancellation of one parked timer in the abort case, and zero remaining live timers/waiters/channels in every case. The optional-signal and pre-aborted adapter paths also pass on native one/four threads and Bun. Results are retained in `docs/bend-issues/2026-09-19-retry-native-timers.json`. This validates composition with the candidate; it is not a performance comparison or exact virtual-time boundary proof.

## Shared-signal cancellation and deadline races

The expanded `tests/abortable_sleep_check.py` runs eight repetitions per backend. Each process adds eight broadcast cohorts of 128 long sleeps, verifies first-abort reason retention after a second abort with a different reason, checks a separate signal remains usable, and exercises 90 combinations of 0/1/2 ms sleeps and abort delays. Every task is joined before retiring its signal. Deadline races allow either legitimate winner but require the correct retained cancellation reason and eventual cleanup.

All native one/four-thread and Bun runs pass. Every observed run creates and closes 1,151 timers, reaches 128 simultaneously live timers and cancels 1,056 parked waits. Timer creation/cancellation counts are observations, not assumptions about real-clock scheduling. Instrumented exit checks require no live timers or timer waiters; native checks also require no live channel rows. Bun channel rows are not audited. The checker requires actual overlapping live timers and parked cancellations, so a run consisting solely of pre-aborted calls would not pass. Raw measurements and source hashes are retained in `docs/bend-issues/2026-09-19-abortable-sleep-concurrency.json`. These finite instrumented tests provide composition and lifetime evidence, not a performance comparison or a proof of every interleaving.
