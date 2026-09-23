# Native child-process output draining

`runtime/src/child-process.bend` owns the concurrent stdout/stderr readers and waits for the process leader without reaping it. `waitForChildProcess` takes the process owner/control, both owned output pipes and a borrowed output callback. It returns the process owner and a report containing exit/signal status and retained errors; the caller retires timeout/abort observers before explicitly reaping that owner. The execution functions below add command spawning and stdin transport; Bash-specific result formatting stays with the caller.

After leader exit, every delivered output chunk restarts the 100ms idle grace. EOF on both pipes ends the wait immediately. Idle expiry cancels the pipe reads, waits for their checked closes, and drains every timer completion before closing the event channel. Generation tags prevent an already-fired old timer from ending a newer grace period. A bounded 16-event channel provides backpressure. Output callback failure or a read/wait failure kills the process group, cancels reading, and preserves cleanup errors. Expected ECANCELED from deliberate cancellation is suppressed; unrelated read and close failures remain in the report.

The two `@unsafe` declarations are externally driven IO loops: pipe input and process/timer events determine when they end, rather than a structural input size. No proof claims termination of an arbitrary child process. The loop has no default execution timeout; its caller supplies cancellation and timeout policy.

Build with the additive process primitive patch described in [process-primitive.md](process-primitive.md):

```sh
BEND=build/bend-process-files/bend2/main.ts sh scripts/build-pure.sh tests/child-process.bend build/child-process
python3 tests/child_process_check.py
```

Explicit native one/four-thread runs each pass 29 real-process scenarios and 40 repeated runs in one Bend runtime with stable descriptor counts. Checks cover binary bytes, concurrent output larger than both pipe buffers, normal/signal exit, quiet inherited pipes, sustained post-exit stdout or stderr, consumer failure, repeated timer cancellation, and checked process/pipe retirement. The sustained-output and quiet-pipe cases exercise the behavior of upstream regression #5303; these real-time checks do not reproduce its virtual-clock assertions at precisely 99ms and 100ms. The OS primitives currently target Linux/glibc; JavaScript process execution and Windows remain unfinished. This module alone does not establish public Bash tool parity.

## Shell execution

`execute(shell, args, command, cwd, env, signal, timeoutSeconds, onData)` appends the command to the supplied argv prefix and uses actual null stdin. `executeStdin` has the same signature but starts the supplied argv unchanged, writes the UTF-8 command through stdin, and closes it. Arguments/environment are owned `List<String>` values, the optional parent is `AbortSignal<Unit>`, timeout seconds are optional native `F64`, and the borrowed callback is the same raw-byte callback used by the draining loop. The result is `Result<&2,&2,ExecutionError,U32>`: normal exit code or 128+signal, with `InvalidTimeout`, `ExecutionAborted`, `ExecutionTimedOut`, or `ExecutionFailed{errors}`. Failures retain the existing typed operation/errno/message records, including cleanup failures.

Timeout validation precedes the pre-abort check, matching upstream. Seconds must be finite and positive, and their unrounded binary64 product with 1000 must be at most 2147483647. Accepted timers floor milliseconds with a minimum of one, including subnormal seconds. Missing timeout creates no timer. The timer begins after successful spawning, so it includes output draining. Observers signal the isolated process group; both registrations are cancelled before either completion is joined, and both are retired before reaping. The final parent-state check takes precedence over a previously fired timeout; abort, timeout, retained errors, then exit status form the settlement order. A signal occurring after that final observation belongs to the caller's next operation.

Stdin writing runs concurrently with both output readers, handles partial writes, and sends at most 65536 bytes per write. Its byte-length bound proves a finite number of positive-progress write iterations without adding an unsafe loop. An early-exiting shell may leave script bytes unread; expected EPIPE follows upstream's ignored stdin error, and deliberate writer retirement suppresses ECANCELED. Other write errors and every checked close error remain visible. After output draining settles, any still-blocked input writer is cancelled and joined before reaping. Caller-owned signals/callbacks are borrowed and never disposed by execution.

```sh
BEND=build/bend-native-toolchain/bend2/main.ts sh scripts/build-pure.sh tests/child-execute.bend build/child-execute
python3 tests/child_execute_check.py
```

Explicit native one/four-thread runs each pass 45 execution scenarios (including 96 repeated normal/abort/timeout lifecycles) and 75 Python-binary64 timeout-conversion comparisons. They cover pre-abort/no-spawn, invalid timeout/no-spawn, signal exits, syscall/output failures, abort after an already-fired timeout, late abort after normal completion, descendant-held pipes, raw binary output, UTF-8 stdin, a 100 KiB script whose child fills stdout before reading the remaining input, early stdin exit, and blocked-writer abort. Existing 29 draining scenarios and 40 same-runtime descriptor checks also remain green. These are native integration checks; JavaScript process spawning still returns ENOSYS, and Windows/shell-selection/public-Bash policy remain outside this dependency.

The generic process runner now lives in runtime so TUI probing can share process ownership, timeout and cleanup behavior without depending on coding-agent. The move changes only imports: independently rebuilt native one/four-thread artifacts pass all 45 execution scenarios, 75 timeout conversions, 29 draining scenarios and 40 descriptor checks per backend. Stdout/stderr are still merged for existing execution callers.

`executeSelected(OutputSelection, ...)` and `waitForSelectedChildProcess(OutputSelection, ...)` add explicit `Merged` or `Stdout` delivery while preserving the original APIs and default merged behavior. Both output pipes still read, report failures, and extend the post-exit idle grace; discarded stderr produces activity events without invoking the caller's callback. The terminal-image integration checks exercise stdout-only binary output, stderr beyond pipe capacity, timeouts, post-exit stderr activity, repeated ownership retirement and the actual tmux probe; see [terminal-image.md](terminal-image.md). All existing merged-output lifecycle checks remain unchanged.
