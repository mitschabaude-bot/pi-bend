# Terminal input buffering

`packages/tui/src/stdin-buffer.bend` provides immutable terminal input framing. `process` returns the replacement buffer and ordered data/paste events; `flush` returns pending input without invoking callbacks, and `clear`/`destroy` discard it. `pendingTimeout` selects the configured lone-Escape or incomplete-sequence deadline. It supports CSI, SGR and X10 mouse input, SS3, OSC/BEL/ST, DCS, APC, bracketed paste, the WezTerm doubled-Escape case and duplicate printable Kitty events.

Pending payloads are reversed strings. Each character advances a small parser state; completed payloads are reversed once. Paste termination uses a six-character prefix state, without rescanning the accumulated paste. This avoids the reference's repeated prefix slicing and sequence recognition. No host parser or regular expression supplies production behavior.

The original-source runner executes all **59 named upstream tests** with their assertions, records process/flush/clear calls, and replays those calls against the Bend state machine. Together with fragmented and generated protocol inputs, **421 traces** compare emitted events, remaining input and default timeout selection on Bun and O1 native one/four workers. Native checks additionally cover a supplementary Unicode scalar and 50,000-character control-string/paste payloads. These are differential and runtime checks, not universal proofs.

**The upstream suite remains partial.** The pure replay does not establish scheduling or synchronous EventEmitter delivery. The owned asynchronous text driver below now exercises actual scheduling and cancellation; terminal byte decoding and the legacy single-high-byte Meta conversion remain pending.

Native data events contain complete Unicode scalars, rather than JavaScript surrogate halves. Bracketed-paste markers are recognized at sequence boundaries; marker-like text inside an OSC/DCS/APC payload is retained in that control string, rather than triggering the reference's global substring search. Empty input during an unfinished paste produces no spurious key event. These follow native text semantics and avoid malformed-stream side effects. No interactive editor or terminal parity is claimed by this milestone.

```sh
build/bend-process-files/bend2/main.ts tests/stdin-buffer.bend -o build/stdin-buffer.js
BEND=build/bend-process-files/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/stdin-buffer.bend build/stdin-buffer
python3 tests/stdin_buffer_check.py
```

The same module now exposes `createAsync(options, observer)`, `borrowAsync`, `processAsync`, `getBufferAsync`, `flushAsync`, `clearAsync` and `disposeAsync`. One worker owns callback order and at most one timer. Parser transitions, event acceptance and deadlines are serialized; callbacks run outside that lock and can reenter process/clear/flush. A cancelled timer that already completed cannot flush newer input: the worker checks the current deadline under the lock before flushing. Completed input cancels its timer; unfinished paste never starts one. Event insertion uses a tail-recursive reverse onto the pending queue.

`processAsync` returns after committing input, before listeners necessarily run. This is an explicit asynchronous API, not a claim to preserve upstream `EventEmitter`'s synchronous process callbacks; pure `process` still provides immediate events. Already accepted events remain ordered when a callback reenters or `clearAsync` runs. Manual `flushAsync` returns events without publishing them. `clearAsync` preserves reuse, while affine `disposeAsync` permanently retires the driver, unlike upstream's reusable clear-like `destroy`. Disposal drops queued work not yet selected by the worker, cancels its timer and joins any current listener batch before returning. The observer is caller-owned: dispose it afterwards. Join external input producers before disposing the driver; borrowed handles expire on return. A callback must not dispose its own worker, which would self-join.

`tests/stdin_buffer_async_check.py` exercises **21 actual timer and ownership scenarios** on Bun and O1 native one/four workers. The timer cases correspond to upstream lone-Escape, configurable Escape versus sequence timeout, explicit flush, timeout emission and destroy cancellation assertions, with broad waits suitable for a shared build server. Additional checks cover deadline reset, paste inactivity, reset bursts, ordered mixed input, Kitty suppression, reentrant callbacks, clear/reuse, prompt cancellation of a ten-second timer, joining a slow callback and absence of callbacks after disposal. These timing assertions use lower bounds and generous waits, not a real-time upper-latency guarantee. Raw bytes and a synchronous listener wrapper are not covered.

```sh
build/bend-native-toolchain/bend2/main.ts tests/stdin-buffer-async.bend -o build/stdin-buffer-async.js
sh scripts/build-pure.sh tests/stdin-buffer-async.bend build/stdin-buffer-async
python3 tests/stdin_buffer_async_check.py
python3 tests/stdin_buffer_async_check.py --command build/stdin-buffer-async --threads 1
python3 tests/stdin_buffer_async_check.py --command build/stdin-buffer-async --threads 4
```
