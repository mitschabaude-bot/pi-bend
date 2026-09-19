# Owned timer experiment — not installed

This additive primitive bundle appends `base.bend` to the installed Base and adds `effs/timer.c` and `effs/timer.js` in an isolated copy. It does not modify compiler code, the general scheduler, existing effects, or the installation. No C/JS retry policy is introduced: these effects only manage a native timer's deadline, wait, cancellation and retirement.

```sh
python3 scripts/prepare-timer-candidate.py build/bend-timer-candidate-fresh
python3 tests/timer_primitive_check.py build/bend-timer-candidate-fresh
python3 scripts/benchmark-timer.py build/bend-timer-candidate-fresh build/timer-performance.json
```

`Timer.new(U32)` starts a monotonic deadline and returns an affine `Timer` owner plus a duplicable `TimerCancel` capability. `Timer.wait` consumes and returns the owner with `True` for expiration or `False` for cancellation. Completion commits when a wait observes expiry or the poller selects it; cancellation before commitment wins once and removes a parked activation before returning. Cancellation after commitment, after cancellation, or through a retired/stale handle returns `False`. A completed/cancelled timer can be waited on again with the stored outcome. `Timer.close` consumes the owner; the owner cannot be closed while its wait is outstanding. Discarding the affine owner does not automatically close it: callers must retire it explicitly, as with other Bend resources.

The C effect uses a separate index/generation table, with a free list and generation-wrap retirement. Table capacity tracks the maximum concurrent timer count and is retained for reuse. The JS effect uses an opaque object. Both use the existing scheduler. Native cancellation unlinks one item from its singly linked parked queue; JS cancellation removes its wait entry. Those new paths are linear in the number of parked operations. They do not add work to existing scheduler paths when timers are unused. JS cancellation treats a wait already selected by the poller as committed, even before its continuation runs, matching the native commitment point.

Core tests pass on one/four native threads and Bun: immediate and parked expiry, cancellation before/during wait, repeated cancellation, head/middle/tail removal, old capabilities after close/slot reuse, 10,000 serial lifecycles, affine-owner copy rejection, and a program using only new/close. A disposable instrumented C copy observes one actual parked expiration, only three used registry slots, and zero live timer rows/waiters at exit. These observations do not prove general race safety or absence of leaks under every workload.

The 20-round alternating-order comparison preserves existing generated C exactly. Separate checks preserve generated JS exactly for the same fixtures. Median compiler wall time is approximately 1.1% lower for detached sleep and 1.0% higher for UTF-8; shared-host measurements are inconclusive, not evidence of performance neutrality. The candidate remains uninstalled. Completion/cancellation race stress, concurrent sustained resource tests, scaling/throughput measurements and the native abort-signal adapter remain pending. See BEND-020 and the retained raw measurements.
