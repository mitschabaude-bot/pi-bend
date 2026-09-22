# Native child-process output draining

`coding-agent/src/utils/child-process.bend` owns the concurrent stdout/stderr readers and waits for the process leader without reaping it. `waitForChildProcess` takes the process owner/control, both owned output pipes and a borrowed output callback. It returns the process owner and a report containing exit/signal status and retained errors; the caller retires timeout/abort observers before explicitly reaping that owner. Stdin transport, command spawning and Bash-specific result formatting belong to the caller.

After leader exit, every delivered output chunk restarts the 100ms idle grace. EOF on both pipes ends the wait immediately. Idle expiry cancels the pipe reads, waits for their checked closes, and drains every timer completion before closing the event channel. Generation tags prevent an already-fired old timer from ending a newer grace period. A bounded 16-event channel provides backpressure. Output callback failure or a read/wait failure kills the process group, cancels reading, and preserves cleanup errors. Expected ECANCELED from deliberate cancellation is suppressed; unrelated read and close failures remain in the report.

The two `@unsafe` declarations are externally driven IO loops: pipe input and process/timer events determine when they end, rather than a structural input size. No proof claims termination of an arbitrary child process. The loop has no default execution timeout; its caller supplies cancellation and timeout policy.

Build with the additive process primitive patch described in [process-primitive.md](process-primitive.md):

```sh
BEND=build/bend-process-files/bend2/main.ts sh scripts/build-pure.sh tests/child-process.bend build/child-process
python3 tests/child_process_check.py
```

Explicit native one/four-thread runs each pass 29 real-process scenarios and 40 repeated runs in one Bend runtime with stable descriptor counts. Checks cover binary bytes, concurrent output larger than both pipe buffers, normal/signal exit, quiet inherited pipes, sustained post-exit stdout or stderr, consumer failure, repeated timer cancellation, and checked process/pipe retirement. The sustained-output and quiet-pipe cases exercise the behavior of upstream regression #5303; these real-time checks do not reproduce its virtual-clock assertions at precisely 99ms and 100ms. The OS primitives currently target Linux/glibc; JavaScript process execution and Windows remain unfinished. This module alone does not establish public Bash tool parity.
