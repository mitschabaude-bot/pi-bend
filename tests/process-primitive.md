# Native subprocess effects

`patches/bend-process.patch` adds OS marshalling to Base and one cohesive effect implementation. It changes no compiler or existing effects. The candidate is isolated in `build/bend-native-toolchain`; nothing is installed globally. This implementation targets Linux with glibc's `posix_spawn` session/chdir/closefrom extensions. JavaScript `Process.spawn` explicitly returns ENOSYS; equivalent JavaScript lifecycle support remains unfinished.

`Process.spawn(path, argv, cwd, environment)` takes an exact executable path, arguments excluding argv[0], and OS-form `NAME=value` entries. `IO.environment()` snapshots the inherited environment for Bend to apply overrides. Embedded NUL and malformed environment entries fail before spawning. `Process.spawn` gives all three standard streams pipes; closing stdin sends EOF. The additive `patches/bend-process-null-stdin.patch` adds `Process.spawn_null_stdin` with the same arguments and an actual read-only `/dev/null` descriptor as stdin. Its result contains only `(process, control, (stdout, stdoutCancel), (stderr, stderrCancel))`; no input pipe is allocated or returned. Spawn creates a new session/process group, resets signal defaults and the signal mask, and closes all inherited descriptors above 2 after connecting the standard streams. Parent pipe ends are nonblocking and close-on-exec; child ends remain blocking.

The result contains `(process, control, (stdin, stdinCancel), (stdout, stdoutCancel), (stderr, stderrCancel))`, represented as right-associated pairs. `Process.wait` returns the owner and `ProcessExited{code}` or `ProcessSignalled{signal}` without reaping. The unreaped leader reserves its PID, so a control remains safe while Bend drains inherited descendant pipes. `Process.signal(control, signal)` signals the group with a leader fallback, returning false for retired controls. `Process.close_checked` waits if necessary, reaps on the IO loop, retires the capability, and reports an OS error. It does not kill; callers must arrange cancellation before retirement when needed. Waiting uses the runtime's existing blocking IO worker pool.

`Pipe.read(owner, maximum)` accepts 1..65536 bytes; successful empty output is EOF. `Pipe.write(owner, bytes)` accepts up to 65536 valid byte values and returns the number written, which may be partial. Both return the endpoint owner on success or error. `Pipe.cancel` permanently cancels that endpoint: it wakes pending nonblocking IO with ECANCELED and future IO also fails; it never closes a descriptor under a pending operation. `Pipe.close_checked` consumes and retires the owner, attempting close exactly once. Capability slots use generations and stop recycling on generation exhaustion; stale handles cannot affect reused slots. Every returned owner must be explicitly closed, including error paths.

Shell choice, PATH lookup, environment override policy, signal-to-exit-code conversion, output decoding/truncation, timeout/abort precedence, and upstream's 100ms post-exit idle drain all remain Bend responsibilities. No C code implements a shell tool or its output policy.

## Verification

```
# Apply only to an isolated copy of the current toolchain:
patch -d build/bend-native-toolchain -p1 < patches/bend-process.patch
patch -d build/bend-native-toolchain -p1 < patches/bend-process-null-stdin.patch
patch -d build/bend-native-toolchain -p1 < patches/bend-process-null-stdin.patch
sh scripts/build-pure.sh tests/process-primitive.bend build/process-primitive
sh scripts/build-pure.sh tests/process-null-stdin.bend build/process-null-stdin
sh scripts/build-pure.sh tests/process-null-stdin.bend build/process-null-stdin
python3 tests/process_primitive_check.py
```

The harness exercises actual native 1/native 4 execution, including binary input/output, cwd/environment, concurrent 131072-byte stdout and stderr, partial writes, EPIPE, blocked read/write cancellation, repeatable exit observation, normal/signal status, group cancellation after leader exit, NUL/environment/spawn failures, signal reset, and descriptor isolation. `/proc` confirms a waited leader remains a zombie with its own session/group until retirement and disappears after reap.128 spawn/retire/reuse pairs in each runtime exercise stale process and pipe capabilities while sampling descriptor and child counts. This is syscall/lifecycle coverage, not a claim that the public Bash tool or 100ms policy has been ported.

A minimal spawn/close-only entry point also builds and runs, confirming unused wait/status effects are not required. The JavaScript fixture compiles and reports `spawn-error:38`; this is explicit unsupported behavior, not JavaScript parity. No negative law tests or mutation tests are involved.

Recorded on Linux/glibc 2.39: 27 lifecycle scenarios and 128 repeated retire/reuse pairs pass on each of native 1/native 4. Reuse sampling peaked at 11 descriptors and one unreaped child. The ordinary-O1 fixture build took 4.35 seconds, peaked at 216736 KiB and emitted 668602 bytes of C. These measurements describe this fixture, not public-tool throughput.

Private candidate hashes: `comp.ts` `02aafb1d3ca4131a3edeeb738b606721d44c375e1e6bdda20166801cb11608fb`, `bend.ts` `ab4d244ca0c199856ffdc00ab9f88e50fd50b17ba0b73132f3775fd2f087f951`, patched `base.bend` `65fcb13a076ef98a926992e6fc6104480f7fb97a4616d5e39ca28a9f676eb35a`. Applying the checked-in patch to the captured unmodified Base reconstructs the tested Base/C/JS files byte-for-byte.

The null-stdin follow-up verifies that stdin is a character device rather than a pipe, resolves to `/dev/null`, is read-only, and returns immediate EOF; the existing pipe variant remains observably a pipe. It repeats 32 null-mode lifecycles in one runtime and checks stable descriptor counts, in addition to the original process suite. Both spawn variants remain explicitly unsupported on JavaScript.

With both patches applied, all 34 scenarios plus 128 process/pipe retire-and-reuse pairs and 32 null-stdin lifecycles pass on each native backend. The null-only entry point builds without the pipe-spawn effect reachable; JavaScript reports ENOSYS for that entry point too.
