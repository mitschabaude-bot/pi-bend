# Native ProcessTerminal

`packages/tui/src/terminal.bend` ports the Linux terminal boundary from pinned pi-mono `46c9de402`, `packages/tui/src/terminal.ts`. Protocol recognition and transitions are pure Bend; the owned driver uses the existing strict streaming UTF-8 decoder, StdinBuffer, serial resources, callbacks, cancellable timers and pipes. It does not use Node or a host terminal library in production.

## API and ownership

`start(options,onInput,onResize)` returns an owned `ProcessTerminal`; `borrow` also returns its reusable `Handle`. `startProcess` resolves the environment for fd 0/1, escape timeout, fallback dimensions and optional exact-path write logging. The driver supplies `write`, `getDimensions`/`getColumns`/`getRows`, `kittyProtocolActive`, cursor movement/visibility, clearing, title, progress, `drainInput`, emergency `cancel`, and consuming `stop`. Up/down movement uses a direction plus unsigned line count. `Error` distinguishes system operations, invalid UTF-8, closed state and combined cleanup failures.

Input and resize callbacks are asynchronous, outside state/output locks; input deliveries retain framing order. Kitty negotiation and progress share one persistent publisher, rather than spawning workers per character or per update. `setProgress` writes its initial/clear sequence before returning; the publisher supplies one-second keepalives. Normal sequence timeout and the separate 150 ms negotiation-fragment timeout remain distinct. Paste callbacks preserve the public terminal's opening/closing bracketed-paste sequences.

The caller retains its callback ownership and must join borrowed operations before `stop`, then dispose callbacks. `stop` joins readers, parser and publisher before retiring state, closes owned duplicates and attempts raw-settings restoration even when output or checked closes fail. No callbacks occur after it returns. Output dimensions are queried through the owned output capability, so closing/reusing the original caller descriptor cannot redirect resize queries. Do not consume the terminal owner from one of its own callbacks: stopping there would wait for that callback itself. Handles are borrowed capabilities, not valid after owner retirement.

Graceful stop can wait for output backpressure. `cancel(handle)` is the explicit, repeatable emergency path; follow it with `stop(owner)`. Cancellation cannot guarantee that escape cleanup reaches a blocked/broken output, but cleanup still attempts termios restoration and reports failures. Regular-file operations dispatched to existing IO workers cannot interrupt an already-running kernel syscall: cancellation takes effect when that call completes, and the descriptor remains owned until then. No arbitrary shutdown timeout disguises this limit.

## Minimal OS effects

`patches/bend-terminal-effects.patch` adds `Terminal.acquire`, `Terminal.restore` and `Terminal.dimensions` to Base and the existing process effects. No compiler changes or global installation. Hosted acquire/dimensions explicitly return ENOSYS; only pure protocol code runs under Bun.

Acquisition rejects a second live lease with EBUSY. It captures input termios, owns raw mode and a SIGWINCH self-pipe, and returns existing Pipe/PipeCancel capabilities for input, output and resize notifications. TTY/FIFO descriptors are independently reopened through Linux `/proc/self/fd` so nonblocking flags never mutate the caller's descriptors. Regular descriptors are duplicated to preserve their shared seek offsets; their blocking reads/writes use existing IO workers. The resource row remains 40 bytes before and after the added regular-file tag.

The handler chains a saved ordinary prior SIGWINCH action. Retirement disables its write gate, restores that action only if it still owns the handler, joins in-flight handler use, then closes the notification fd. An externally replaced handler is left intact and reported as EBUSY. A failed restoration retains enough bookkeeping to repair the old action before another acquire, avoiding recursive self-chaining. Arbitrary foreign signal-handler masking/alternate-stack conventions are not claimed as equivalent to independent kernel dispatch.

The private candidate used for validation is `build/bend-terminal-toolchain/bend2/main.ts`. The patch dry-runs cleanly against the parent's `build/bend-process-files` snapshot. Baseline `base.bend` SHA-256: `9c029d77705f0b3eb0ae66273b5e0628382aa83163ee3c20d66b33913119026d`; baseline `effs/process.c`: `7abf6bf70155451ed81cec820508e8be6e7d0ae6d40908bccf852ca0a93a04c2`; candidate `effs/process.c`: `1b563332217e95c94d92b75043407a2c3a16c17871e38768ad403e26bdfdb882`.

## Validation

`terminal_original.mts` executes all 21 named original source tests with their actual assertions. It records 19 pure helper calls for exact replay in Bend, covering configured/invalid/SSH/default timeouts and native/Apple Shift+Enter normalization. It is an oracle, not production glue. `terminal_protocol_reference.mts` runs the actual upstream negotiation methods; 90 ordered traces match Bun and optimized native one/four threads, covering query-before-fallback, zero/nonzero Kitty flags, DA fallback, ordinary input, split responses, invalid continuation replay and timeout cleanup. This includes a 50,000-character unfinished prefix; an initially non-tail-recursive scanner overflowed Bun's stack and was replaced with a tail call. No compiler change was needed.

`terminal_pty_check.py` passes 32 owned-PTY/file scenarios on optimized native one/four threads. These cover actual start/stop raw restoration, input UTF-8 splits and paste, negotiation/fallback order, resize notifications, progress clear/keepalive/order, cursor/title bytes, environment size fallback, idle/max input drain, exact-path logging, emergency cancellation under blocked output, invalid UTF-8, concurrent-acquire rejection, old/external SIGWINCH handlers, failed handler restoration followed by reacquisition, acquisition/cleanup syscall faults, 101-session descriptor stability and 101-session signal-storm retirement. Redirected regular input/output preserve offsets and flags. A test-only 300 ms regular write does not delay an unrelated terminal input callback; cancellation waits for that kernel worker and then restores terminal state. An additional two-PTY regression closes and reuses the caller’s original output fd while live, then verifies resized dimensions and cleanup output still target the owned original terminal. Dimension queries take the existing generation-checked output PipeCancel capability; wrong-kind and retired capabilities return EBADF. Each fixture verifies raw settings and original descriptor flags after stopping, and checks no callbacks follow the final stop.

The existing process suite also passes on one/four threads: 34 lifecycle scenarios and 128 repeated retire/reuse pairs per backend. Its original pipes retain their nonblocking event-loop path. Fifteen alternating baseline/candidate pairs of the same `process-primitive.bend` fixture (`repeat /bin/sh <cwd> cat`, 128 iterations, including reuse checks) measured 198.54/198.29 ms median on one thread and 191.19/193.51 ms on four. Median paired candidate/baseline ratios were 0.987 and 1.008. Raw times and executable hashes are in `terminal-pipe-performance.json`. These are end-to-end child-process measurements on a shared machine, not evidence of a universal speedup; no material regression was observed within that noise.

```sh
# Apply the patch only to a private copy of the already-patched native toolchain.
patch -p1 -d build/bend-terminal-toolchain < patches/bend-terminal-effects.patch
# Point build/bend-native-toolchain at that private copy, or set BEND explicitly.
sh scripts/build-pure.sh tests/terminal-protocol.bend build/terminal-protocol
build/bend-terminal-toolchain/bend2/main.ts tests/terminal-protocol.bend -o build/terminal-protocol.js
python3 tests/terminal_protocol_check.py
sh scripts/build-pure.sh tests/terminal.bend build/terminal
clang -shared -fPIC -O2 tests/terminal_faults.c -ldl -o build/terminal-faults.so
python3 tests/terminal_pty_check.py --threads 1
python3 tests/terminal_pty_check.py --threads 4
sh scripts/build-pure.sh tests/process-primitive.bend build/process-primitive
sh scripts/build-pure.sh tests/process-null-stdin.bend build/process-null-stdin
python3 tests/process_primitive_check.py
```

## Deliberate adaptations and remaining scope

Escape-timeout configuration accepts positive decimal U32 milliseconds, falling back for invalid input. Fractional numbers, exponent/hex notation, whitespace coercion and oversized JavaScript Number values are not recreated. Negotiated numeric flags are bounded U32. These do not change the pinned original test assertions. UTF-8 remains incremental and strict, with no implicit high-byte Meta interpretation; malformed input produces a typed terminal error. Exact-path debug-log failures are reported by `write` while terminal output still proceeds, rather than being silently discarded. Caller-visible asynchronous callback timing is explicit instead of claiming synchronous EventEmitter equivalence.

Linux TTYs, FIFOs and regular redirected files are implemented; socket-backed descriptors and other platform terminal backends are not claimed. Windows VT setup and native macOS modifier-key sensing remain pending; the pure normalization helpers are implemented and replayed, but platform sensing is not wired into this Linux driver. Directory-valued `PI_TUI_WRITE_LOG` auto-generated names remain pending: exact paths append faithfully, directory values currently disable logging. That omission is not claimed as full write-log parity. Full terminal/TUI parity, including those platform paths and higher-level rendering, remains partial.
